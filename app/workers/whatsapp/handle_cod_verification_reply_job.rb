module Whatsapp
  # Acts on a buyer's Confirm/Cancel quick-reply tap from the
  # cod_verification template. Receives the inbound message row id;
  # correlates it to the OrderConfirmation via the parent log's payload
  # snapshot, then mirrors what TwillioController#ivr_webhook does for the
  # IVR path:
  #   - cod_confirm → status='COD-Verified', tag the Shopify order
  #   - cod_cancel  → status='COD-Cancelled', tag + cancel the Shopify order
  #
  # Idempotent: a re-delivered webhook (or a buyer mashing the button)
  # short-circuits if the order is already in a terminal verification state.
  class HandleCodVerificationReplyJob < ApplicationJob
    sidekiq_options queue: 'default', retry: 3

    def perform(inbound_message_id)
      inbound = WhatsappInboundMessage.find_by(id: inbound_message_id)
      return Rails.logger.info("[cod_verify_reply] inbound #{inbound_message_id} gone") unless inbound

      received_payload = inbound.payload.to_s
      unless %w[cod_confirm cod_cancel].include?(received_payload)
        return Rails.logger.info("[cod_verify_reply] inbound=#{inbound.id} payload=#{received_payload.inspect} not a cod payload")
      end

      log = inbound.whatsapp_message_log
      return Rails.logger.info("[cod_verify_reply] inbound=#{inbound.id} no parent log — can't route") unless log

      payload = intended_payload(inbound, log, received_payload)

      order_id =
        log.payload_snapshot.is_a?(Hash) ? log.payload_snapshot.dig('order', 'id') : nil
      if order_id.blank?
        return Rails.logger.info("[cod_verify_reply] inbound=#{inbound.id} parent log has no order.id")
      end

      shop = inbound.shop
      oc = shop.order_confirmations.find_by(order_id: order_id.to_s)
      unless oc
        return Rails.logger.info("[cod_verify_reply] inbound=#{inbound.id} no OrderConfirmation for order=#{order_id}")
      end

      reply_to = inbound.from_phone.presence || oc.customer_number
      order_label =
        (log.payload_snapshot.is_a?(Hash) && log.payload_snapshot.dig('order', 'name')).presence ||
        "##{order_id}"

      # Already resolved — webhook retry or the buyer tapping again / the other
      # button. WhatsApp gives us no way to disable the quick-reply buttons once
      # the message is sent, so we enforce "first tap wins" here and tell the
      # buyer their later tap was ignored rather than silently dropping it.
      if %w[COD-Verified COD-Cancelled COD-Auto-Cancelled].include?(oc.status.to_s)
        Rails.logger.info("[cod_verify_reply] order=#{order_id} already terminal=#{oc.status}; ignoring repeat tap")
        already = oc.status.to_s == 'COD-Verified' ? 'confirmed' : 'cancelled'

        # Orders placed through the pre-order OTP checkout are saved as
        # COD-Verified up front (OrderConfirmationCreateJob#save_pre_order_confirmation),
        # yet still get the BSP cod_verification prompt — and their
        # order-confirmation message is held back for this tap. So a Confirm
        # tap on an already-verified order is the moment to send it. Safe on
        # repeat taps: BSP order_created is deduped per order in
        # DispatchEventJob, MSG91 via its TwilioLog checks.
        if payload == 'cod_confirm' && oc.status.to_s == 'COD-Verified'
          send_order_confirmation_message(shop: shop, oc: oc, payload_snapshot: log.payload_snapshot)
        end

        send_reply(shop, reply_to, "Your order #{order_label} is already #{already}. No further action is needed.")
        return
      end

      case payload
      when 'cod_confirm'
        confirm_order(shop: shop, oc: oc, reply_to: reply_to, order_label: order_label, payload_snapshot: log.payload_snapshot)
      when 'cod_cancel'
        cancel_order(shop: shop, oc: oc, reply_to: reply_to, order_label: order_label)
      else
        hold_unverified_cancel(shop: shop, oc: oc, inbound: inbound, reply_to: reply_to, order_label: order_label)
      end
    end

    private

    # Messages sent before payloads were keyed to labels carry positional
    # payloads, so the tapped label is the only reliable signal of intent.
    # A cancel is never executed unless the label backs it up.
    def intended_payload(inbound, log, received_payload)
      label = inbound.display_text.to_s
      components = log.whatsapp_template&.components

      expected =
        if components.present?
          Whatsapp::CodVerificationButtons.payload_for_label(components, label)
        else
          case Whatsapp::CodVerificationButtons.classify(label)
          when :confirm then 'cod_confirm'
          when :cancel then 'cod_cancel'
          end
        end

      if expected && expected != received_payload
        Rails.logger.warn("[cod_verify_reply] inbound=#{inbound.id} label=#{label.inspect} payload=#{received_payload} → acting as #{expected}")
        SlackNotifyJob.perform_async(
          ":warning: (#{Rails.env}) COD verification payload mismatch shop_id=#{inbound.shop_id} inbound=#{inbound.id} label=#{label.inspect} sent=#{received_payload} → treated as #{expected}"
        )
      end

      return expected if expected
      return received_payload if received_payload == 'cod_confirm'

      nil
    end

    def hold_unverified_cancel(shop:, oc:, inbound:, reply_to:, order_label:)
      Rails.logger.warn("[cod_verify_reply] order=#{oc.order_id} cancel payload from unrecognised label #{inbound.display_text.inspect}; not cancelling")
      SlackNotifyJob.perform_async(
        ":warning: (#{Rails.env}) COD cancel HELD for order=#{oc.order_id} shop=#{shop.shopify_domain} — buyer tapped #{inbound.display_text.inspect}, which isn't a Cancel button. Order left as #{oc.status}."
      )
      send_reply(shop, reply_to, "Thanks, we've received your response for order #{order_label}. Our team will get back to you shortly.")
    end

    # Free-form text acknowledgement back to the buyer. Valid because their
    # button tap just opened the 24h customer-service window. Best-effort — a
    # failed reply must not roll back the confirm/cancel that already happened.
    def send_reply(shop, to, body)
      # Reply from the same number the cod_verification message was sent from.
      account = shop.whatsapp_account_for('cod_verification')
      return unless account&.ready_to_send? && to.present?

      Meta::SendTextMessageService.call(account: account, recipient: to, body: body)
    rescue => e
      Rails.logger.warn("[cod_verify_reply] reply send failed shop=#{shop.id} to=#{to}: #{e.class}: #{e.message}")
    end

    def confirm_order(shop:, oc:, reply_to:, order_label:, payload_snapshot: nil)
      Whatsapp::CodVerificationActions.confirm!(shop: shop, oc: oc, payload_snapshot: payload_snapshot)
      Rails.logger.info("[cod_verify_reply] order=#{oc.order_id} → COD-Verified")

      send_reply(shop, reply_to, "✅ Thank you! Your order #{order_label} is confirmed. We'll get it on its way soon.")
    end

    # All verification paths (this one, /order_confirmations/confirm, manual
    # confirm) go through the same notifier so BSP-vs-MSG91 selection lives
    # in one place.
    def send_order_confirmation_message(shop:, oc:, payload_snapshot:)
      Whatsapp::OrderConfirmationNotifier.call(shop: shop, order_confirmation: oc, payload_snapshot: payload_snapshot)
    end

    def cancel_order(shop:, oc:, reply_to:, order_label:)
      result = Whatsapp::CodVerificationActions.cancel!(shop: shop, oc: oc)

      if result.cancelled
        Rails.logger.info("[cod_verify_reply] order=#{oc.order_id} → COD-Cancelled + Shopify cancelled")
        send_reply(shop, reply_to, "Your order #{order_label} has been cancelled as requested. If this was a mistake, please contact us.")
      else
        handle_cancel_failure(shop: shop, oc: oc, reply_to: reply_to, order_label: order_label, result: result)
      end
    end

    # The Shopify order wasn't cancelled. Tailor the buyer message — and whether
    # we alert — to *why*: an order already paid/fulfilled is an expected state
    # the buyer must take up with support, whereas a not-found/API error is a
    # genuine failure the team needs to see.
    def handle_cancel_failure(shop:, oc:, reply_to:, order_label:, result:)
      case result.code
      when :already_paid, :already_fulfilled
        Rails.logger.info("[cod_verify_reply] order=#{oc.order_id} can't auto-cancel: #{result.reason}")
        send_reply(shop, reply_to, "Your order #{order_label} is already being processed and can't be cancelled automatically. Please reply here or contact our support team and we'll help you out.")
      when :already_cancelled
        Rails.logger.info("[cod_verify_reply] order=#{oc.order_id} already cancelled on Shopify")
        send_reply(shop, reply_to, "Your order #{order_label} is already cancelled. No further action is needed.")
      else # :not_found, :error — genuine failure, surface it
        Rails.logger.warn("[cod_verify_reply] order=#{oc.order_id} Shopify cancel failed: #{result.reason || result.error}")
        SlackNotifyJob.perform_async(
          ":warning: (#{Rails.env}) COD cancel FAILED for Shopify order=#{oc.order_id} shop=#{shop.shopify_domain} — #{result.reason || result.error}"
        )
        send_reply(shop, reply_to, "We've received your cancellation request for order #{order_label}. Our team will confirm it shortly.")
      end
    end
  end
end

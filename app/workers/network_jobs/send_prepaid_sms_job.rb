module NetworkJobs
  class SendPrepaidSmsJob < ApplicationJob
    # reminder_id and send_key are optional (default nil) so old in-flight jobs
    # queued before this signature change still deserialize cleanly.
    def perform(shop_id, order_confirmation_id, reminder_id = nil, send_key = nil)
      shop = Shop.find_by(id: shop_id)
      return if shop.blank? || shop.setting&.locked

      order_confirmation = OrderConfirmation.find_by(id: order_confirmation_id)
      return if order_confirmation.blank?

      if order_confirmation.status == 'COD-Prepaid' ||
         !order_confirmation.is_cod_order ||
         is_order_already_paid(order_confirmation) ||
         !is_order_status_eligible(order_confirmation) ||
         is_whatsapp_prepaid_sent_recently(order_confirmation) # Add this check
        return
      end

      # If this send was scheduled from a configured reminder, resolve its
      # per-reminder overrides (template, language, discount). When the reminder
      # was deleted after enqueue, fall through to the legacy single-template
      # path rather than failing the job.
      reminder = reminder_id && shop.setting.find_prepaid_reminder(reminder_id)
      resolved = reminder ? shop.setting.resolve_prepaid_reminder(reminder) : nil

      resp = NetworkServices::SendPrepaidMessageService.call(
        shop, order_confirmation,
        reminder: resolved,
        send_key: send_key || reminder_id
      )
      puts resp
    end

    private

    def is_whatsapp_prepaid_sent_recently(order_confirmation)
      begin
        TwilioLog.where(
          order_confirmation_id: order_confirmation.id,
          ver_type: 'WHATSAPP_COD_PREPAID'
        ).where('created_at > ?', 2.minute.ago).exists?
      rescue => e
        Rails.logger.error("Error checking recent WhatsApp prepaid logs: #{e.message}")
        false # Default to false to allow sending in case of error
      end
    end

    def is_order_status_eligible(order_confirmation)
      begin
        shop = order_confirmation.shop
        return false if shop.blank?

        shop.init_session
        order = ShopifyAPI::Order.find(order_confirmation.order_id)
        return false if order.blank?

        # Return false if cancelled or paid
        return false if order.cancelled_at.present? || order.financial_status == 'paid'
        return false if rabbitpay_partial_order?(order)

        true
      rescue => e
        Rails.logger.error("Error in is_order_status_eligible: #{e.message}")
        true # Defaulting to true in case of exception
      end
    end

    def rabbitpay_partial_order?(order)
      Array(JSON.parse(order.to_json)['note_attributes']).any? do |attr|
        attr['name'] == '_rabbitpay_partial_order' && attr['value'].to_s.strip.casecmp?('true')
      end
    end

    def is_order_already_paid(order_confirmation)
      if order_confirmation.payment_link_id.present?
        Razorpay.setup(
          order_confirmation.shop.setting.payment_provider_api_key,
          order_confirmation.shop.setting.payment_provider_api_secret
        )
        Razorpay.headers = { "Content-type" => "application/json" }
        resp = Razorpay::PaymentLink.fetch(order_confirmation.payment_link_id)
        return resp.present? && resp.status == 'paid'
      else
        provider = order_confirmation.shop.setting.payment_provider
        return true if provider == 'PHONEPE' &&
                       NetworkServices::PhonepeStatusService.call(order_confirmation.shop, order_confirmation)

        return true if provider == 'PAYMOB' &&
                       NetworkServices::PaymobStatusService.call(order_confirmation.shop, order_confirmation)

        return true if provider == 'GE_IDEA' &&
                       NetworkServices::GeideaStatusService.call(order_confirmation.shop, order_confirmation)

        return true if provider == 'PAYU' &&
                       NetworkServices::PayuStatusService.call(order_confirmation.shop, order_confirmation)

        return true if provider == 'CASHFREE' &&
                       NetworkServices::CashfreeStatusService.call(order_confirmation.shop, order_confirmation)
      end
      false
    end
  end
end
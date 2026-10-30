# frozen_string_literal: true

module Whatsapp
  # Decides, right before a resend, whether the message is still worth sending.
  # Returns a reason string to cancel it, or nil to go ahead.
  #
  #   verified     COD verification for an order that is already verified (or paid)
  #   prepaid      COD→prepaid nudge for an order that is already prepaid / part-paid
  #   recovered    abandoned-cart reminder for a cart that turned into an order
  #   superseded   a later reminder for the same cart has already been sent
  #   source_gone  the original row was deleted
  module ReattemptRelevance
    VERIFIED_STATUSES = %w[COD-Verified COD-Manual-Verified COD-Prepaid COD-Partial-Payment-Received].freeze
    PAID_STATUSES = %w[COD-Prepaid COD-Partial-Payment-Received].freeze
    BSP_CART_EVENTS = %w[abandoned_cart cart_abandoned browse_abandoned].freeze
    BSP_SENT_STATUSES = %w[sent delivered read].freeze

    module_function

    def skip_reason(reattempt)
      source = reattempt.source
      return 'source_gone' unless source

      case source
      when TwilioLog then twilio_log_reason(source)
      when AbandonedCart then abandoned_cart_reason(source)
      when WhatsappMessageLog then bsp_reason(source)
      end
    end

    def twilio_log_reason(log)
      order = log.order_confirmation
      case log.ver_type
      when 'WHATSAPP' then 'verified' if verified?(order)
      when 'WHATSAPP_COD_PREPAID' then 'prepaid' if paid?(order)
      end
    end

    def abandoned_cart_reason(cart)
      carts = AbandonedCart.where(shop_id: cart.shop_id, checkout_id: cart.checkout_id)
      return 'recovered' if cart.checkout_id.present? && carts.where("lower(coalesce(notes, '')) = 'recovered'").exists?

      later = carts.where(notif_type: cart.notif_type, status: ReattemptRecorder::MSG91_SUCCESS)
                   .where.not(id: cart.id)
                   .where('created_at > ?', cart.created_at)
      'superseded' if cart.checkout_id.present? && later.exists?
    end

    def bsp_reason(log)
      key = log.event_type_key.to_s
      source_id = log.source_external_id.to_s

      case key
      when 'cod_verification', 'cod_verification_reminder'
        'verified' if verified?(order_for(log))
      when 'cod_to_prepaid'
        'prepaid' if paid?(order_for(log))
      when *BSP_CART_EVENTS
        return nil if source_id.blank?
        return 'recovered' if AbandonedCart.where(shop_id: log.shop_id, checkout_id: source_id)
                                           .where("lower(coalesce(notes, '')) = 'recovered'").exists?

        later = WhatsappMessageLog.where(shop_id: log.shop_id, event_type_key: key, source_external_id: source_id)
                                  .where('stage_index > ?', log.stage_index.to_i)
                                  .where(status: BSP_SENT_STATUSES)
        'superseded' if later.exists?
      end
    end

    def order_for(log)
      return nil if log.source_external_id.blank?

      OrderConfirmation.find_by(shop_id: log.shop_id, order_id: log.source_external_id.to_s)
    end

    def verified?(order)
      return false unless order

      order.is_otp_verified || VERIFIED_STATUSES.include?(order.status.to_s)
    end

    def paid?(order)
      order.present? && PAID_STATUSES.include?(order.status.to_s)
    end
  end
end

module PricingJobs
    class PreviewDynamicChargeJob < ApplicationJob
      sidekiq_options queue: "administration"
  
      DEFAULT_SMS_CHARGE = 0.02
      DEFAULT_IVR_CHARGE = 0.04
  
      def perform(shop_id, start_date, end_date)
        ExchangeRateBank.install!
  
        shop = Shop.find_by(id: shop_id)
        return unless shop&.setting
  
        pricings = TwilioPricing.all.index_by(&:country_code)
        # Same rules DynamicChargeJob bills with, so the preview matches the real charge.
        pricer = MessagePricing.new(
          pricings: pricings,
          charge_overrides: MessagePricing.load_charge_overrides.slice(shop.id)
        )
  
        sms_orders = TwilioLog.where(shop_id: shop.id, is_charged: false, ver_type: ["SMS", "Confirmation-SMS", "Fulfilment-SMS"], status: "SUCCESS", created_at: start_date..end_date)
        ivr_orders = TwilioLog.where(shop_id: shop.id, is_charged: false, ver_type: "IVR", status: "SUCCESS", created_at: start_date..end_date).where.not(status: "Non-COD")
        whatsapp_orders = TwilioLog.where(shop_id: shop.id, is_charged: false, ver_type: MessagePricing::WHATSAPP_TWILIO_VER_TYPES, status: "SUCCESS", created_at: start_date..end_date)
        whatsapp_bsp_orders = WhatsappMessageLog.where(shop_id: shop.id, created_at: start_date..end_date).chargeable
        abandoned_orders = AbandonedCart.where(shop_id: shop.id, is_charged: nil, status: "SUCCESS", notif_type: 'SMS', created_at: start_date..end_date)
        abandoned_orders_whatsapp = AbandonedCart.where(shop_id: shop.id, is_charged: nil, status: "SUCCESS", notif_type: 'WHATSAPP', created_at: start_date..end_date)
        pre_orders_sms = PreOrderOtp.where(shop_id: shop.id, is_charged: nil, status: true, ver_type: 'SMS', created_at: start_date..end_date)
        pre_orders_whatsapp = PreOrderOtp.where(shop_id: shop.id, is_charged: nil, status: true, ver_type: 'WHATSAPP', created_at: start_date..end_date)
        prepaid_orders = shop.order_confirmations.where(status: 'COD-Prepaid', is_prepaid_charged: nil, created_at: start_date..end_date)
  
        sms_charge = sms_orders.sum do |order|
          pricer.sms(shop, order.country_code, order.num_segment) || 0
        end
  
        whatsapp_charge = whatsapp_orders.sum do |order|
          pricer.whatsapp(shop, order.country_code,
                          category: MessagePricing.whatsapp_category_for_ver_type(order.ver_type),
                          india_category: PricingV3India.whatsapp_category_for_ver_type(order.ver_type)) || 0
        end

        whatsapp_bsp_charge = whatsapp_bsp_orders.pluck(:event_type_key).sum do |event_type_key|
          pricer.bsp_whatsapp(shop, category: PricingV3India.whatsapp_category_for_event(event_type_key))
        end
  
        abandoned_charge = abandoned_orders.sum do |order|
          pricer.sms(shop, order.country_code) || 0
        end
  
        abandoned_charge_whatsapp = abandoned_orders_whatsapp.sum do |order|
          pricer.whatsapp(shop, order.country_code, category: :marketing) || 0
        end

        pre_order_charge_sms = pre_orders_sms.sum do |order|
          pricer.sms(shop, order.country_code) || 0
        end

        pre_order_charge_whatsapp = pre_orders_whatsapp.sum do |order|
          pricer.whatsapp(shop, order.country_code, category: :utility) || 0
        end

        pre_order_charge = pre_order_charge_sms + pre_order_charge_whatsapp
  
        ivr_charge = ivr_orders.count * DEFAULT_IVR_CHARGE
  
        prepaid_charge = prepaid_orders.sum do |order|
          ((order.order_amount.to_f) * 0.02) / 80
        end
  
        partial_payment_charge = 0
        if shop.id > 10000
          partial_payment_orders = shop.order_confirmations.where(status: 'COD-Partial-Payment-Received', is_prepaid_charged: nil, created_at: start_date..end_date)
  
          rate = PartialTransactionFee.rate_for(shop, plan: shop.plan, setting: shop.setting)
  
          partial_payment_orders.each do |order|
            begin
              original_currency = order.currency || 'INR'
              full_order = if order.draft_order_id.present?
                             shop.order_confirmations.find_by(order_id: order.draft_order_id) || order
                           else
                             order
                           end
              total_amount = (full_order&.order_amount || 0).to_f
              usd_value = usd_value_from(total_amount, original_currency) * rate
              partial_payment_charge += usd_value
            rescue => e
              Rails.logger.error "Currency conversion failed for order #{order.id}: #{e.message}"
            end
          end
        end
  
        total_estimated_charge = sms_charge + ivr_charge + whatsapp_charge + whatsapp_bsp_charge +
                                 abandoned_charge + pre_order_charge + abandoned_charge_whatsapp +
                                 prepaid_charge + partial_payment_charge
  
        SlackNotifier::CLIENT.ping(
          text: <<~MSG
            🔍 *Preview Charges Report* (#{Rails.env})
  
            🏬 Shop: #{shop.id} - #{shop.shopify_domain}
            📅 Date Range: #{start_date.to_date} to #{end_date.to_date}
            💰 Estimated Total: $#{total_estimated_charge.round(2)}
  
            💡 Breakdown:
            • SMS: $#{sms_charge.round(2)}
            • WhatsApp: $#{whatsapp_charge.round(2)}
            • WhatsApp (BSP): $#{whatsapp_bsp_charge.round(2)}
            • PreOrder OTP (SMS): $#{pre_order_charge_sms.round(2)}
            • PreOrder OTP (WhatsApp): $#{pre_order_charge_whatsapp.round(2)}
            • PreOrder OTP (Total): $#{pre_order_charge.round(2)}
            • Abandoned Cart (SMS): $#{abandoned_charge.round(2)}
            • Abandoned Cart (WhatsApp): $#{abandoned_charge_whatsapp.round(2)}
            • IVR: $#{ivr_charge.round(2)}
            • Prepaid %: $#{prepaid_charge.round(2)}
            • Partial Payment: $#{partial_payment_charge.round(2)}
  
            ✅ *This is a non-charging preview only.*
          MSG
        )
      rescue => e
        SlackNotifier::CLIENT.ping(
          text: "PreviewDynamicChargeJob Error (#{Rails.env}): #{e.message}\n#{e.backtrace.join("\n")}"
        )
      end
  
      private
  
      def usd_value_from(amount, currency)
        money = Money.new((amount * 100).to_i, currency)
        money.exchange_to('USD').to_f
      rescue Money::Bank::UnknownRate
        fallback_rate = ExchangeRateBank.fallback_usd_rate(currency)
        return 0 unless fallback_rate

        amount * fallback_rate
      end
    end
  end
  
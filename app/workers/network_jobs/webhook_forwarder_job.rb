module NetworkJobs
  class WebhookForwarderJob < ApplicationJob
    
    def perform(params,shopify_domain,event)
      begin
        @shop = Shop.find_by(shopify_domain: shopify_domain)
        if !@shop.blank?
          if @shop.setting.blank? && event != 'uninstalled'
            Shops::EnsureSettingService.call(@shop, welcome_email: false)
            @shop.reload
          end
          if event=='fulfiled' && (@shop.setting&.enable_fulfilment_message || @shop.setting&.fulfilment_whatsapp)
            NetworkJobs::SendFulfilmentSmsJob.perform_async(JSON.parse(params.to_json).to_h, @shop.id)
          end
          if event=='order_updated'
            payload_hash = JSON.parse(params.to_json).to_h
            if should_send_fulfilment_on_update?(@shop, payload_hash)
              NetworkJobs::SendFulfilmentSmsJob.perform_async(payload_hash, @shop.id)
            end
          end
          if event=='create'
            OrderConfirmationCreateJob.new.perform(JSON.parse(params.to_json).to_h, @shop.id)
            if !@shop.blank? && @shop.setting&.abandoned_cart_enabled
              AbandonedCartStatusUpdateJob.perform_async(@shop.id,JSON.parse(params.to_json).to_h)
            end
          end
          if event=='uninstalled'
            UninstallNewJob.perform_async(@shop.shopify_domain,JSON.parse(params.to_json).to_h)
          end
          if event=='customer_create'
            # SlackNotifyJob.perform_async(
            #   ":heart:  (#{Rails.env})\n  *Customer Create received #{params}"
            # )
            customer = JSON.parse(params.to_json).to_h
            camelized_hash = customer.transform_keys { |key| key.to_s.camelize(:lower) }
            # SlackNotifyJob.perform_async(
            #   ":heart:  (#{Rails.env})\n  *Customer Create received #{camelized_hash}"
            # )   
            ShopifyServices::CustomerSingleDataSaveService.call(@shop,camelized_hash)
          end
          
        else

          SlackNotifyJob.perform_async(
            ":rage:  (#{Rails.env})\n  *Error in WebhookForwarderJob Shop not found #{shopify_domain} - #{params} "
          )  
        end
      rescue Exception => e
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Error in webhook processign WebhookForwarderJob #{params} #{e} #{e.backtrace} #{shopify_domain}"
        )
      end
    end

    private

    FULFILMENT_VER_TYPES = ['Fulfilment-SMS', 'WHATSAPP-FULFILMENT'].freeze

    def should_send_fulfilment_on_update?(shop, payload)
      return false unless shop.setting&.enable_fulfilment_message || shop.setting&.fulfilment_whatsapp
      return false unless shop_opted_in_for_update_fulfilment?(shop)
      return false unless tracking_present?(payload)
      !fulfilment_already_sent?(shop, payload)
    end

    def shop_opted_in_for_update_fulfilment?(shop)
      raw = GlobalSetting.first&.send_fulfilment_on_update_shops
      return false if raw.blank?
      domains = raw.split(',').map { |d| d.strip.downcase }.reject(&:blank?)
      domains.include?(shop.shopify_domain.to_s.downcase)
    end

    def tracking_present?(payload)
      fulfillment = payload['fulfillments']&.first
      return false if fulfillment.blank?
      fulfillment['tracking_number'].present? || fulfillment['tracking_url'].present?
    end

    def fulfilment_already_sent?(shop, payload)
      order_id = payload['id']
      return false if order_id.blank?
      order_confirmation = OrderConfirmation.find_by(order_id: order_id, shop: shop)
      return false if order_confirmation.blank?
      TwilioLog.where(
        order_confirmation_id: order_confirmation.id,
        ver_type: FULFILMENT_VER_TYPES,
        status: 'SUCCESS'
      ).exists?
    end
  end
end


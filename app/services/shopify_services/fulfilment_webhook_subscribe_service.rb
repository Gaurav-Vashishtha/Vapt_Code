module ShopifyServices
  # Idempotently subscribes the orders/fulfilled webhook to EventBridge so
  # both pipelines (legacy MSG91 fulfilment SMS/WhatsApp + new BSP DispatchEventJob)
  # can receive shipment events from Shopify.
  #
  # Callers:
  #   - SettingsController#create — when fulfilment_whatsapp / enable_fulfilment_message
  #     flips from off → on in the legacy settings.
  #   - Api::Whatsapp::TemplateBindingsController#create — when an `order_fulfilled`
  #     automation is created/activated through the BSP flow.
  #
  # Idempotency: checks for an existing subscription with the same address
  # before creating. Shopify rejects duplicates with 422 and the previous
  # implementation silently swallowed that failure, so first toggles often
  # appeared to "do nothing".
  class FulfilmentWebhookSubscribeService < ApplicationService
    TOPIC = 'orders/fulfilled'.freeze

    def initialize(shop, topic = TOPIC)
      @shop = shop
      @topic = topic.to_s.presence || TOPIC
    end

    def call
      target_address = ENV['AWS_EVENT_BRIDGE_ARN']
      if target_address.blank?
        Rails.logger.warn("[fulfilment_webhook] AWS_EVENT_BRIDGE_ARN missing shop=#{@shop.id}")
        return false
      end

      @shop.init_session

      existing = ShopifyAPI::Webhook.find(:all, params: { topic: @topic }) rescue []
      if Array(existing).any? { |w| w.address.to_s == target_address.to_s }
        Rails.logger.info("[fulfilment_webhook] already subscribed shop=#{@shop.id}")
        return true
      end

      webhook = ShopifyAPI::Webhook.new(
        topic: @topic,
        address: target_address,
        format: 'json'
      )
      if webhook.save
        Rails.logger.info("[fulfilment_webhook] subscribed shop=#{@shop.id} webhook=#{webhook.id}")
        true
      else
        errs = webhook.errors.full_messages.join(', ').presence || 'unknown error'
        Rails.logger.warn("[fulfilment_webhook] subscribe failed shop=#{@shop.id} errors=#{errs}")
        SlackNotifyJob.perform_async(
          ":rage: (#{Rails.env}) Couldn't subscribe #{@topic} webhook for #{@shop.shopify_domain}: #{errs}"
        )
        false
      end
    rescue => e
      Rails.logger.error("[fulfilment_webhook] error shop=#{@shop.id}: #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async(
        ":rage: (#{Rails.env}) #{@topic} webhook subscribe raised for #{@shop.shopify_domain}: #{e.message}"
      )
      false
    end
  end
end

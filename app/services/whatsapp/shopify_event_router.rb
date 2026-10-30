# frozen_string_literal: true

module Whatsapp
  module ShopifyEventRouter
    TOPICS = %w[orders/cancelled fulfillment_events/create].freeze
    CANCEL_REASONS = {
      'customer' => 'Cancelled at your request', 'inventory' => 'Item out of stock', 'fraud' => 'Order could not be verified',
      'declined' => 'Order was not confirmed in time', 'staff' => 'Cancelled by the store', 'other' => 'Cancelled by the store'
    }.freeze

    module_function

    def handles?(topic)
      TOPICS.include?(topic.to_s)
    end

    def call(topic, shop_domain, payload)
      return unless payload.is_a?(Hash)

      case topic.to_s
      when 'orders/cancelled'
        order = payload.merge('cancel_reason_label' => CANCEL_REASONS[payload['cancel_reason'].to_s] || CANCEL_REASONS['other'])
        DispatchEventJob.perform_async('order_cancelled', shop_domain, { 'order' => order })
      when 'fulfillment_events/create'
        FulfillmentEventJob.perform_async(shop_domain, payload)
      end
    rescue StandardError => e
      Rails.logger.error("[whatsapp/shopify_event_router] #{topic} shop=#{shop_domain}: #{e.class}: #{e.message}")
    end
  end
end

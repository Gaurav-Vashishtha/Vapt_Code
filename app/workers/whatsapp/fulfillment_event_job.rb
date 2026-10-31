# frozen_string_literal: true

module Whatsapp
  class FulfillmentEventJob < ApplicationJob
    sidekiq_options queue: 'default', retry: 3

    STATUS_EVENTS = { 'out_for_delivery' => 'order_out_for_delivery', 'delivered' => 'order_delivered' }.freeze

    def perform(shop_domain, event)
      event_key = STATUS_EVENTS[event['status'].to_s]
      return unless event_key

      shop = Shop.find_by(shopify_domain: shop_domain.to_s)
      return unless shop

      keys = [event_key]
      keys += EventRegistry.follow_ups_for(event_key) if event_key == 'order_delivered'
      bound = shop.whatsapp_template_bindings.active.where(event_type_key: keys, stage_index: 0).pluck(:event_type_key)
      return if bound.empty?

      payload = build_payload(shop, event)
      return unless payload

      (keys & bound).each { |key| DispatchEventJob.perform_async(key, shop.shopify_domain, payload) }
    end

    private

    def build_payload(shop, event)
      order_id = event['order_id'].presence
      return nil unless order_id

      # A 401 (token revoked out of band), a 404 or Shopify throttling must not
      # cost the customer their delivery update: SafeOrderReader returns nil
      # instead of raising, and we rebuild the order from the stored
      # OrderConfirmation row so the message still goes out.
      order = ShopifyServices::SafeOrderReader.find_hash(shop, order_id)
      order ||= Notifications::OrderFallback.for(shop, order_id)
      return nil unless order.is_a?(Hash) && order['id'].present?

      fulfillments = Array(order['fulfillments'])
      fulfillment = fulfillments.find { |f| f['id'].to_s == event['fulfillment_id'].to_s } ||
                    fulfillments.max_by { |f| f['updated_at'] || f['created_at'] || '' } || {}
      # Tracking details live on the Shopify fulfilment; when the order came
      # from stored data, take whatever the carrier event itself carried.
      if order['from_stored_data']
        fulfillment = fulfillment.merge(
          {
            'tracking_number'  => event['tracking_number'].presence,
            'tracking_url'     => event['tracking_url'].presence,
            'tracking_company' => event['tracking_company'].presence
          }.compact
        )
      end

      {
        'order' => order,
        'fulfillment' => fulfillment,
        'delivery' => {
          'status' => event['status'],
          'happened_at' => event['happened_at'],
          'estimated_delivery_at' => event['estimated_delivery_at'],
          'estimated_label' => date_label(event['estimated_delivery_at'])
        }
      }
    rescue StandardError => e
      Rails.logger.warn("[whatsapp/fulfillment_event] payload build failed shop=#{shop&.shopify_domain} order=#{event['order_id']}: #{e.class}: #{e.message}")
      nil
    end

    def date_label(value)
      value.present? ? Time.zone.parse(value.to_s).strftime('%-d %b') : nil
    rescue ArgumentError
      nil
    end
  end
end

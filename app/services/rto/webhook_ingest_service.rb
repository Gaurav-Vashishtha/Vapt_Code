# frozen_string_literal: true

module Rto
  class WebhookIngestService < ApplicationService
    def initialize(shopify_domain:, payload:, event:)
      @shopify_domain = shopify_domain
      @payload = payload || {}
      @event = event.to_s
    end

    def call
      sd = ShopDomain.find_or_create_by_domain!(@shopify_domain)
      sd.update_column(:last_webhook_received_at, Time.current) rescue nil

      case @event
      when "create"
        Rto::OrderUpsertService.call(
          shopify_domain: @shopify_domain,
          order_payload: @payload,
          source: "webhook",
          event_type: "orders/create",
          occurred_at: Time.current
        )
      when "fulfiled"
        # Fulfillment payload: store as event; update order fulfillment_status best-effort if order exists.
        order_id = (@payload["order_id"] || @payload["orderId"] || @payload.dig("order", "id")).to_s
        RtoOrderEvent.create!(
          shop_domain: sd,
          order_id: order_id.presence || "unknown",
          event_type: "fulfillments/update",
          occurred_at: Time.current,
          source: "webhook",
          payload_json: @payload
        )

        if order_id.present?
          rec = RtoOrder.find_by(shop_domain: sd, order_id: order_id)
          rec&.update(fulfillment_status: "fulfilled") # conservative
        end
      when "uninstalled"
        # Keep domain data; just note the event.
        RtoOrderEvent.create!(
          shop_domain: sd,
          order_id: "n/a",
          event_type: "app/uninstalled",
          occurred_at: Time.current,
          source: "webhook",
          payload_json: @payload
        )
      else
        # Store unknown webhook event types for future enrichment.
        RtoOrderEvent.create!(
          shop_domain: sd,
          order_id: (@payload["id"] || @payload["order_id"] || "unknown").to_s,
          event_type: "unknown/#{@event}",
          occurred_at: Time.current,
          source: "webhook",
          payload_json: @payload
        )
      end
    end
  end
end


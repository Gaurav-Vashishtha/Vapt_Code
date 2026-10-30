# frozen_string_literal: true

module Rto
  class OrderUpsertService < ApplicationService
    # Call with a ShopifyAPI::Order (REST) or a Hash-like payload containing order fields.
    def initialize(shopify_domain:, order_payload:, source: "webhook", event_type: "orders/updated", occurred_at: nil, webhook_id: nil)
      @shopify_domain = shopify_domain
      @order_payload = order_payload
      @source = source
      @event_type = event_type
      @occurred_at = occurred_at
      @webhook_id = webhook_id
    end

    def call
      sd = ShopDomain.find_or_create_by_domain!(@shopify_domain)
      data = payload_to_hash(@order_payload)
      order_id = data["id"].to_s.presence || data["order_id"].to_s.presence
      raise ArgumentError, "order id missing" if order_id.blank?

      RtoOrderEvent.create!(
        shop_domain: sd,
        order_id: order_id,
        event_type: @event_type,
        occurred_at: @occurred_at,
        source: @source,
        webhook_id: @webhook_id,
        payload_json: data
      )

      attrs = map_order_attrs(data)

      rec = RtoOrder.find_or_initialize_by(shop_domain: sd, order_id: order_id)
      rec.assign_attributes(attrs)
      rec.raw_snapshot = data
      rec.last_fetched_at = Time.current if rec.has_attribute?(:last_fetched_at)
      rec.save!

      OrderMetrics::UpsertService.call(Shop.find_by(shopify_domain: sd.shopify_domain), data, rto_order: rec)

      # Global identity linkage + stats update (best-effort)
      identity = nil
      begin
        identity = CustomerIdentity.find_or_create_by_identifiers!(phone: rec.phone_normalized, email: rec.email_normalized)
      rescue
        identity = nil
      end

      begin
        Rto::StatsUpdaterService.call(order: rec, identity: identity)
      rescue
        nil
      end
      rec
    end

    private
    DELIVERED_SHIPMENT_STATUSES = %w[
      delivered
    ].freeze

    # Shopify fulfillment shipment_status varies by carrier integrations; normalize via substring checks too.
    RTO_SHIPMENT_STATUS_SUBSTRINGS = %w[
      rto
      return_to_sender
      returned_to_sender
    ].freeze

    RETURNED_SHIPMENT_STATUS_SUBSTRINGS = %w[
      returned
    ].freeze

    OUTCOME_STATUSES = {
      cancelled: "cancelled",
      refunded: "refunded",
      rto: "rto",
      returned: "returned",
      delivered: "delivered",
      fulfilled: "fulfilled",
      open: "open"
    }.freeze

    def truthy?(v)
      v == true || v.to_s.downcase == "true"
    end

    def payload_to_hash(obj)
      # ShopifyAPI REST objects contain nested ActiveResource objects (e.g. ShippingAddress)
      # which are safer to normalize via JSON roundtrip for consistent Hash access.
      if obj.is_a?(Hash)
        obj
      else
        JSON.parse(obj.to_json)
      end
    end

    def map_order_attrs(data)
      phone = data["phone"] || data.dig("customer", "phone") || data.dig("shipping_address", "phone") || data.dig("billing_address", "phone")
      email = data["email"] || data.dig("customer", "email")
      ship = data["shipping_address"] || {}
      ship = ship.attributes if ship.respond_to?(:attributes)
      ship = ship.to_h if ship.respond_to?(:to_h) && !ship.is_a?(Hash)

      payment_gateways = data["payment_gateway_names"]
      gateway = if payment_gateways.is_a?(Array)
        payment_gateways.first.to_s
      else
        payment_gateways.to_s
      end

      tags = data["tags"]
      tags_arr =
        case tags
        when Array then tags
        when String then tags.split(",").map(&:strip).reject(&:blank?)
        else []
        end
      base = {
        order_number: data["order_number"]&.to_s,
        shopify_created_at: parse_time(data["created_at"]),
        shopify_updated_at: parse_time(data["updated_at"]),
        processed_at: parse_time(data["processed_at"]),
        cancelled_at: parse_time(data["cancelled_at"]),
        closed_at: parse_time(data["closed_at"]),
        financial_status: data["financial_status"]&.to_s,
        fulfillment_status: data["fulfillment_status"]&.to_s,
        is_cod: cod_like?(gateway),
        total_price: data["total_price"]&.to_d,
        currency: data["currency"]&.to_s,
        gateway: gateway.presence,
        zip: ship["zip"]&.to_s,
        city: ship["city"]&.to_s,
        province: ship["province"]&.to_s,
        country: (ship["country_code"] || ship["country"])&.to_s,
        phone: phone&.to_s,
        phone_normalized: RtoOrder.normalize_phone(phone),
        email: email&.to_s,
        email_normalized: RtoOrder.normalize_email(email),
        tags: tags_arr
      }

      base.merge(derive_outcome_attrs(data, base))
    end

    def parse_time(v)
      return v if v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone)
      return nil if v.blank?
      Time.zone.parse(v.to_s)
    rescue
      nil
    end

    def derive_outcome_attrs(data, base_attrs)
      attrs = {}

      cancelled_at = base_attrs[:cancelled_at]
      financial_status = base_attrs[:financial_status].to_s
      fulfillment_status = base_attrs[:fulfillment_status].to_s

      refunds = data["refunds"]
      refunds = refunds.to_a if refunds.respond_to?(:to_a) && !refunds.is_a?(Array)
      refunds = [] unless refunds.is_a?(Array)

      refund_amount =
        refunds.sum do |r|
          # Many payloads include transactions; fallback to refund_line_items subtotal when missing.
          txns = r.is_a?(Hash) ? r["transactions"] : nil
          if txns.is_a?(Array) && txns.any?
            txns.sum { |t| t.is_a?(Hash) ? t["amount"].to_d : 0.to_d }
          else
            0.to_d
          end
        rescue
          0.to_d
        end

      is_refunded =
        refund_amount.positive? ||
        financial_status.to_s.downcase.in?(%w[refunded partially_refunded])

      fulfillments = data["fulfillments"]
      fulfillments = fulfillments.to_a if fulfillments.respond_to?(:to_a) && !fulfillments.is_a?(Array)
      fulfillments = [] unless fulfillments.is_a?(Array)

      # Pick the latest-updated fulfillment as "best" signal for shipment_status.
      best_f = fulfillments.max_by do |f|
        parse_time(f.is_a?(Hash) ? f["updated_at"] : nil) || Time.at(0)
      end

      shipment_status = best_f.is_a?(Hash) ? best_f["shipment_status"].to_s.downcase : ""
      shipment_updated_at = parse_time(best_f.is_a?(Hash) ? best_f["updated_at"] : nil)

      is_rto = RTO_SHIPMENT_STATUS_SUBSTRINGS.any? { |sub| shipment_status.include?(sub) }
      is_returned = !is_rto && RETURNED_SHIPMENT_STATUS_SUBSTRINGS.any? { |sub| shipment_status.include?(sub) }
      is_delivered = DELIVERED_SHIPMENT_STATUSES.include?(shipment_status)

      # Timestamps: use shipment update time as best-effort marker.
      attrs[:delivered_at] = shipment_updated_at if is_delivered && shipment_updated_at.present?
      attrs[:rto_at] = shipment_updated_at if is_rto && shipment_updated_at.present?
      attrs[:returned_at] = shipment_updated_at if is_returned && shipment_updated_at.present?

      attrs[:is_rto] = is_rto
      attrs[:is_returned] = is_returned
      attrs[:is_refunded] = is_refunded
      attrs[:refund_amount] = refund_amount if refund_amount.positive?

      attrs[:outcome_status] =
        if cancelled_at.present?
          OUTCOME_STATUSES[:cancelled]
        elsif is_refunded
          OUTCOME_STATUSES[:refunded]
        elsif is_rto
          OUTCOME_STATUSES[:rto]
        elsif is_returned
          OUTCOME_STATUSES[:returned]
        elsif is_delivered
          OUTCOME_STATUSES[:delivered]
        elsif fulfillment_status.present?
          OUTCOME_STATUSES[:fulfilled]
        elsif financial_status.present?
          OUTCOME_STATUSES[:open]
        else
          nil
        end

      attrs.compact
    end

    def cod_like?(gateway)
      g = gateway.to_s.downcase
      g.include?("cod") || g.include?("cash")
    end
  end
end


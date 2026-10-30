# frozen_string_literal: true

module Whatsapp
  module AttributionReport
    CAMPAIGN_EVENT = 'campaign_broadcast'
    RECENT_ORDERS = 20
    AGGREGATES = [
      Arel.sql('COUNT(*)'),
      Arel.sql('COALESCE(SUM(order_total), 0)'),
      Arel.sql('COUNT(*) FILTER (WHERE is_cod)')
    ].freeze

    module_function

    def campaign_totals(shop, ids)
      ids = Array(ids).map(&:to_i).select(&:positive?).uniq
      return [] if ids.empty?

      grouped = campaign_scope(shop).where(whatsapp_campaign_id: ids)
                                    .group(:whatsapp_campaign_id, :currency)
                                    .pluck(:whatsapp_campaign_id, :currency, *AGGREGATES)
                                    .group_by(&:first)
      ids.map do |id|
        totals = combine((grouped[id] || []).map { |r| r[1..] }, shop)
        { campaign_id: id, orders: totals[:orders], revenue: totals[:revenue],
          currency: totals[:currency], cod_orders: totals[:cod_orders] }
      end
    end

    def campaign_detail(shop, campaign)
      scope = campaign_scope(shop).where(whatsapp_campaign_id: campaign.id)
      totals = combine(scope.group(:currency).pluck(:currency, *AGGREGATES), shop)
      recent = scope.order(ordered_at: :desc).limit(RECENT_ORDERS)
                    .pluck(:order_name, :order_total, :currency, :ordered_at, :phone_last10, :is_cod)
      totals.merge(
        prepaid_orders: totals[:orders] - totals[:cod_orders],
        avg_order_value: totals[:orders].positive? ? (totals[:revenue] / totals[:orders]).round(2) : 0,
        window_days: RevenueAttribution.window_hours(CAMPAIGN_EVENT) / 24,
        recent_orders: recent.map do |name, total, currency, ordered_at, phone, is_cod|
          { order_name: name, total: total.to_f, currency: currency.presence || shop.currency,
            ordered_at: ordered_at, phone_masked: mask(phone), is_cod: is_cod }
        end
      )
    end

    def notification_totals(shop, days)
      since = days.days.ago
      base = WhatsappOrderAttribution.where(shop_id: shop.id).where('ordered_at >= ?', since)
      notifications = per_event(base.orders.where.not(event_type_key: CAMPAIGN_EVENT), shop)
      conversions = per_event(base.conversions, shop)
      { days: days, notifications: notifications, conversions: conversions }
    end

    def per_event(scope, shop)
      scope.group(:event_type_key, :currency)
           .pluck(:event_type_key, :currency, *AGGREGATES)
           .group_by(&:first)
           .map do |key, rows|
             totals = combine(rows.map { |r| r[1..] }, shop)
             { event_type_key: key, orders: totals[:orders], revenue: totals[:revenue], currency: totals[:currency] }
           end
    end

    def campaign_scope(shop)
      WhatsappOrderAttribution.orders.where(shop_id: shop.id, event_type_key: CAMPAIGN_EVENT)
    end

    # Rows are [currency, count, revenue, cod_count]. Revenue is reported in the
    # currency with the most orders; summing across currencies would be meaningless.
    def combine(rows, shop)
      orders = rows.sum { |r| r[1].to_i }
      cod_orders = rows.sum { |r| r[3].to_i }
      dominant = rows.max_by { |r| r[1].to_i }
      {
        orders: orders,
        revenue: dominant ? dominant[2].to_d.round(2).to_f : 0.0,
        currency: dominant&.dig(0).presence || shop.currency,
        cod_orders: cod_orders
      }
    end

    def mask(phone)
      digits = phone.to_s
      return '' if digits.empty?

      "••••••#{digits[-4..] || digits}"
    end
  end
end

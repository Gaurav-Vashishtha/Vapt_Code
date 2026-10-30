# frozen_string_literal: true

module Whatsapp
  # Last-touch attribution of orders to delivered/read WhatsApp messages,
  # written by Whatsapp::AttributionSweepJob. Re-running any window is safe:
  # rows are upserted on (shop_id, order_id, attribution_type).
  module RevenueAttribution
    ATTRIBUTABLE_EVENTS = %w[campaign_broadcast abandoned_cart cart_abandoned browse_abandoned].freeze
    DEFAULT_WINDOW_HOURS = 72
    WINDOW_HOURS = { 'campaign_broadcast' => 168 }.freeze
    MAX_WINDOW_HOURS = 168
    TOUCH_STATUSES = %i[delivered read].freeze
    CANCELLED_OC_STATUSES = %w[COD-Cancelled COD-Auto-Cancelled COD-Auto-Deleted].freeze
    EXCLUDED_OC_STATUSES = ['Test-Order', *CANCELLED_OC_STATUSES].freeze
    CONVERTED_STATUS = 'COD-Prepaid'
    CONVERSION_EVENT = 'cod_to_prepaid'
    CONVERSION_LOOKBACK = 30.days
    MIN_PHONE_DIGITS = 8
    PHONE_BATCH = 1000
    STATEMENT_TIMEOUT_MS = 60_000
    LAST10_SQL = "right(regexp_replace(coalesce(recipient, ''), '\\D', '', 'g'), 10)"
    AMOUNT_FORMAT = /\A\d+(\.\d+)?\z/
    UNIQUE_KEY = %i[shop_id order_id attribution_type].freeze

    module_function

    def attribute_orders!(shop, from:, to:)
      orders = OrderConfirmation.where(shop_id: shop.id, created_at: from..to)
                                .where('status IS NULL OR status NOT IN (?)', EXCLUDED_OC_STATUSES)
                                .where.not(customer_number: [nil, ''])
                                .pluck(:id, :order_id, :order_number, :order_amount, :currency,
                                       :is_cod_order, :status, :customer_number, :created_at)
                                .map { |r| order_struct(*r) }
                                .select { |o| o[:order_id].present? && o[:phone_last10] }
                                .uniq { |o| o[:order_id] }
      return 0 if orders.empty?

      names, cancelled = shopify_order_state(shop, orders.map { |o| o[:order_id] })
      orders.reject! { |o| o[:status] != CONVERTED_STATUS && cancelled.include?(o[:order_id]) }
      return 0 if orders.empty?

      touches = touches_by_phone(shop, orders.map { |o| o[:phone_last10] }.uniq,
                                 from: from - MAX_WINDOW_HOURS.hours, to: to)

      rows = orders.filter_map do |o|
        touch = last_touch(touches[o[:phone_last10]], o[:ordered_at])
        next unless touch

        base_row(shop, o, names[o[:order_id]]).merge(
          attribution_type: 'order',
          is_cod: o[:is_cod] && o[:status] != CONVERTED_STATUS,
          ordered_at: o[:ordered_at],
          event_type_key: touch[:event_type_key],
          whatsapp_campaign_id: touch[:campaign_id],
          whatsapp_message_log_id: touch[:id],
          touch_at: touch[:at]
        )
      end
      upsert(rows)
    end

    def attribute_conversions!(shop, from:, to:)
      orders = OrderConfirmation.where(shop_id: shop.id, status: CONVERTED_STATUS, updated_at: from..to)
                                .where('created_at >= ?', from - CONVERSION_LOOKBACK)
                                .pluck(:id, :order_id, :order_number, :order_amount, :currency,
                                       :is_cod_order, :status, :customer_number, :created_at,
                                       :confirmed_at, :updated_at)
                                .map { |r| order_struct(*r[0..8]).merge(converted_at: r[9] || r[10]) }
                                .select { |o| o[:order_id].present? }
                                .uniq { |o| o[:order_id] }
      return 0 if orders.empty?

      logs = WhatsappMessageLog.where(shop_id: shop.id, event_type_key: CONVERSION_EVENT, status: TOUCH_STATUSES)
                               .where('created_at >= ?', from - CONVERSION_LOOKBACK)
                               .where("split_part(source_external_id, ':', 2) IN (?)", orders.map { |o| o[:id].to_s })
                               .pluck(:id, :created_at, :source_external_id, :recipient)
                               .group_by { |r| r[2].to_s.split(':')[1].to_i }

      names, = shopify_order_state(shop, orders.map { |o| o[:order_id] })

      rows = orders.filter_map do |o|
        log = (logs[o[:id]] || []).select { |l| l[1] < o[:converted_at] }.max_by { |l| l[1] }
        next unless log

        phone = o[:phone_last10] || last10(log[3])
        next unless phone

        base_row(shop, o, names[o[:order_id]]).merge(
          attribution_type: CONVERSION_EVENT,
          is_cod: false,
          ordered_at: o[:converted_at],
          phone_last10: phone,
          event_type_key: CONVERSION_EVENT,
          whatsapp_campaign_id: nil,
          whatsapp_message_log_id: log[0],
          touch_at: log[1]
        )
      end
      upsert(rows)
    end

    def prune_cancelled!(shop, since: 14.days.ago)
      shop_domain_id = shop_domain_id_for(shop)
      shopify_cancelled = <<~SQL.squish
        EXISTS (SELECT 1 FROM order_metrics om
                WHERE om.shop_id = whatsapp_order_attributions.shop_id
                  AND om.order_id = whatsapp_order_attributions.order_id
                  AND om.delivery_status = 'cancelled')
      SQL
      if shop_domain_id
        shopify_cancelled += ' OR ' + <<~SQL.squish
          EXISTS (SELECT 1 FROM rto_orders ro
                  WHERE ro.shop_domain_id = #{shop_domain_id.to_i}
                    AND ro.order_id = whatsapp_order_attributions.order_id
                    AND ro.cancelled_at IS NOT NULL)
        SQL
      end

      WhatsappOrderAttribution.where(shop_id: shop.id, attribution_type: 'order')
                              .where('ordered_at >= ?', since)
                              .where(<<~SQL.squish, CANCELLED_OC_STATUSES, CONVERTED_STATUS)
                                EXISTS (SELECT 1 FROM order_confirmations oc
                                        WHERE oc.shop_id = whatsapp_order_attributions.shop_id
                                          AND oc.order_id = whatsapp_order_attributions.order_id
                                          AND oc.status IN (?))
                                OR (NOT EXISTS (SELECT 1 FROM order_confirmations oc
                                                WHERE oc.shop_id = whatsapp_order_attributions.shop_id
                                                  AND oc.order_id = whatsapp_order_attributions.order_id
                                                  AND oc.status = ?)
                                    AND (#{shopify_cancelled}))
                              SQL
                              .delete_all
    end

    def with_statement_timeout
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
        yield
      end
    end

    def last10(raw)
      digits = raw.to_s.gsub(/\D/, '')
      return nil if digits.length < MIN_PHONE_DIGITS

      digits.length > 10 ? digits[-10..] : digits
    end

    def parse_amount(raw)
      s = raw.to_s.strip
      s.match?(AMOUNT_FORMAT) ? BigDecimal(s) : 0.to_d
    end

    def order_struct(id, order_id, order_number, amount, currency, is_cod, status, phone, created_at)
      {
        id: id, order_id: order_id.to_s, order_number: order_number, total: parse_amount(amount),
        currency: currency, is_cod: is_cod == true, status: status,
        phone_last10: last10(phone), ordered_at: created_at
      }
    end

    def base_row(shop, order, shopify_name)
      {
        shop_id: shop.id,
        order_id: order[:order_id],
        order_confirmation_id: order[:id],
        order_name: shopify_name.presence || (order[:order_number].present? ? "##{order[:order_number]}" : nil),
        order_total: order[:total],
        currency: order[:currency].presence || shop.currency,
        phone_last10: order[:phone_last10]
      }
    end

    # Order names come from order_metrics; Shopify-side cancellation from
    # order_metrics or rto_orders, whichever has synced (decision D3).
    def shopify_order_state(shop, order_ids)
      names = {}
      cancelled = Set.new
      order_ids.each_slice(PHONE_BATCH) do |ids|
        OrderMetric.where(shop_id: shop.id, order_id: ids).pluck(:order_id, :order_name, :delivery_status).each do |oid, name, status|
          names[oid] = name
          cancelled << oid if status == 'cancelled'
        end
      end
      shop_domain_id = shop_domain_id_for(shop)
      if shop_domain_id
        order_ids.each_slice(PHONE_BATCH) do |ids|
          cancelled.merge(RtoOrder.where(shop_domain_id: shop_domain_id, order_id: ids)
                                  .where.not(cancelled_at: nil).pluck(:order_id))
        end
      end
      [names, cancelled]
    end

    def touches_by_phone(shop, phones, from:, to:)
      touches = Hash.new { |h, k| h[k] = [] }
      phones.each_slice(PHONE_BATCH) do |batch|
        WhatsappMessageLog.where(shop_id: shop.id, status: TOUCH_STATUSES,
                                 event_type_key: ATTRIBUTABLE_EVENTS, created_at: from..to)
                          .where("#{LAST10_SQL} IN (?)", batch)
                          .pluck(:id, :event_type_key, :whatsapp_campaign_id, :created_at, Arel.sql(LAST10_SQL))
                          .each do |id, key, campaign_id, at, phone|
          touches[phone] << { id: id, event_type_key: key, campaign_id: campaign_id, at: at }
        end
      end
      touches
    end

    def last_touch(candidates, ordered_at)
      return nil if candidates.blank?

      candidates.select { |t| t[:at] < ordered_at && t[:at] >= ordered_at - window_hours(t[:event_type_key]).hours }
                .max_by { |t| t[:at] }
    end

    def window_hours(event_type_key)
      WINDOW_HOURS.fetch(event_type_key, DEFAULT_WINDOW_HOURS)
    end

    def upsert(rows)
      return 0 if rows.empty?

      rows.each_slice(500) { |slice| WhatsappOrderAttribution.upsert_all(slice, unique_by: UNIQUE_KEY) }
      rows.size
    end

    def shop_domain_id_for(shop)
      return nil if shop.shopify_domain.blank?

      ShopDomain.where(shopify_domain: shop.shopify_domain.to_s.strip.downcase).pick(:id)
    end
  end
end

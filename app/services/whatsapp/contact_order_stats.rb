module Whatsapp
  # Order history is denormalised onto contacts because segment counts run
  # live in the builder; joining order_confirmations / rto_orders per count
  # would be far too slow on large stores. Only this shop's own orders are
  # used: one merchant's marketing must never see another merchant's data.
  module ContactOrderStats
    module_function

    UNCONFIRMED_COD_STATUSES = %w[Pending COD COD-Pending COD-Potential-Prepaid COD-Fee-Applied].freeze
    PREPAID_STATUSES = %w[COD-Prepaid COD-Partial-Payment-Received].freeze
    EXCLUDED_STATUSES = %w[Test-Order].freeze

    # Status changes (confirmation, COD converted to prepaid) happen within days
    # of the order, so an incremental run only looks at recent orders and
    # stays on the (shop_id, created_at) index.
    INCREMENTAL_LOOKBACK = 14.days
    MAX_INCREMENTAL_PHONES = 20_000
    STATEMENT_TIMEOUT_MS = 300_000

    ORDER_LAST10 = "right(regexp_replace(order_confirmations.customer_number, '\\D', '', 'g'), 10)".freeze
    RTO_LAST10 = 'right(rto_orders.phone_normalized, 10)'.freeze

    def refresh!(shop, since: nil)
      shop_domain_id = ShopDomain.where(shopify_domain: shop.shopify_domain).pick(:id)
      phones = since ? changed_phones(shop.id, shop_domain_id, since) : nil
      return 0 if phones&.empty?

      phones = nil if phones && phones.size > MAX_INCREMENTAL_PHONES
      sql = update_sql(shop.id, shop_domain_id, phones)
      with_statement_timeout { ActiveRecord::Base.connection.exec_update(sql, 'ContactOrderStats') }
    end

    def changed_phones(shop_id, shop_domain_id, since)
      order_phones = OrderConfirmation.where(shop_id: shop_id)
                                      .where(created_at: (since - INCREMENTAL_LOOKBACK)..)
                                      .where('order_confirmations.updated_at >= ?', since)
                                      .where.not(customer_number: [nil, ''])
                                      .distinct
                                      .pluck(Arel.sql(ORDER_LAST10))

      # rto_orders has no (shop_domain_id, updated_at) index; shopify_updated_at
      # is indexed and moves whenever Shopify marks an order returned or RTO.
      rto_phones = if shop_domain_id
                     RtoOrder.where(shop_domain_id: shop_domain_id)
                             .where('rto_orders.shopify_updated_at >= ?', since)
                             .where.not(phone_normalized: [nil, ''])
                             .distinct
                             .pluck(Arel.sql(RTO_LAST10))
                   else
                     []
                   end

      (order_phones | rto_phones).select { |p| p.to_s.length >= 8 }
    end

    def update_sql(shop_id, shop_domain_id, phones)
      conn = ActiveRecord::Base.connection
      q = ->(v) { conn.quote(v) }
      list = ->(arr) { arr.map { |v| q.(v) }.join(', ') }

      phone_filter = ->(expr) { phones ? "AND #{expr} = ANY(ARRAY[#{list.(phones)}]::text[])" : '' }
      cod = "COALESCE(is_cod_order, false) AND COALESCE(status, '') NOT IN (#{list.(PREPAID_STATUSES)})"
      prepaid = "(NOT COALESCE(is_cod_order, false) OR COALESCE(status, '') IN (#{list.(PREPAID_STATUSES)}))"
      unconfirmed = "COALESCE(is_cod_order, false) AND COALESCE(status, '') IN (#{list.(UNCONFIRMED_COD_STATUSES)})"
      rto_scope = shop_domain_id ? "shop_domain_id = #{q.(shop_domain_id.to_i)}" : 'false'

      <<~SQL
        WITH oc AS (
          SELECT #{ORDER_LAST10} AS last10,
                 count(*) FILTER (WHERE #{cod}) AS cod_count,
                 count(*) FILTER (WHERE #{prepaid}) AS prepaid_count,
                 max(created_at) FILTER (WHERE #{cod}) AS last_cod_at,
                 max(created_at) FILTER (WHERE #{unconfirmed}) AS last_unconfirmed_at
          FROM order_confirmations
          WHERE shop_id = #{q.(shop_id.to_i)}
            AND customer_number IS NOT NULL AND customer_number <> ''
            AND COALESCE(status, '') NOT IN (#{list.(EXCLUDED_STATUSES)})
            #{phone_filter.(ORDER_LAST10)}
          GROUP BY 1
        ),
        rto AS (
          SELECT #{RTO_LAST10} AS last10,
                 count(*) FILTER (WHERE is_rto) AS rto_count,
                 count(*) FILTER (WHERE is_returned) AS returned_count
          FROM rto_orders
          WHERE #{rto_scope}
            AND phone_normalized IS NOT NULL AND phone_normalized <> ''
            AND (is_rto OR is_returned)
            #{phone_filter.(RTO_LAST10)}
          GROUP BY 1
        ),
        agg AS (
          SELECT COALESCE(oc.last10, rto.last10) AS last10,
                 COALESCE(oc.cod_count, 0) AS cod_count,
                 COALESCE(oc.prepaid_count, 0) AS prepaid_count,
                 COALESCE(rto.rto_count, 0) AS rto_count,
                 COALESCE(rto.returned_count, 0) AS returned_count,
                 oc.last_cod_at,
                 oc.last_unconfirmed_at
          FROM oc FULL OUTER JOIN rto ON rto.last10 = oc.last10
          WHERE length(COALESCE(oc.last10, rto.last10)) >= 8
        ),
        target AS (
          SELECT c.id,
                 COALESCE(agg.cod_count, 0)::integer AS cod_count,
                 COALESCE(agg.prepaid_count, 0)::integer AS prepaid_count,
                 COALESCE(agg.rto_count, 0)::integer AS rto_count,
                 COALESCE(agg.returned_count, 0)::integer AS returned_count,
                 agg.last_cod_at,
                 agg.last_unconfirmed_at
          FROM whatsapp_contacts c
          LEFT JOIN agg ON agg.last10 = right(c.phone, 10)
          WHERE c.shop_id = #{q.(shop_id.to_i)}
            #{phone_filter.('right(c.phone, 10)')}
        )
        UPDATE whatsapp_contacts w
        SET cod_orders_count = target.cod_count,
            prepaid_orders_count = target.prepaid_count,
            rto_orders_count = target.rto_count,
            returned_orders_count = target.returned_count,
            last_cod_order_at = target.last_cod_at,
            last_unconfirmed_cod_at = target.last_unconfirmed_at,
            order_stats_synced_at = now()
        FROM target
        WHERE w.id = target.id
          AND (w.cod_orders_count, w.prepaid_orders_count, w.rto_orders_count, w.returned_orders_count,
               w.last_cod_order_at, w.last_unconfirmed_cod_at)
              IS DISTINCT FROM
              (target.cod_count, target.prepaid_count, target.rto_count, target.returned_count,
               target.last_cod_at, target.last_unconfirmed_at)
      SQL
    end

    def with_statement_timeout
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
        yield
      end
    end
  end
end

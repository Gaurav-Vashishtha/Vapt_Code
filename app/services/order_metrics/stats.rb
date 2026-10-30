# frozen_string_literal: true

module OrderMetrics
  class Stats
    OC_JOIN = "LEFT JOIN LATERAL (SELECT c.status, c.draft_order_id, c.customer_name FROM order_confirmations c " \
              "WHERE c.shop_id = order_metrics.shop_id AND c.order_id = order_metrics.order_id " \
              "ORDER BY c.id DESC LIMIT 1) oc ON TRUE"
    PARTIAL_SQL = "(order_metrics.is_partial OR (oc.status = 'COD-Partial-Payment-Received' " \
                  "AND COALESCE(oc.draft_order_id, '') = ''))"
    FILTERS = {
      "all" => nil,
      "converted_prepaid" => "order_metrics.is_converted_prepaid",
      "ac_recovered" => "order_metrics.is_ac_recovered",
      "cod_fee" => "order_metrics.cod_fee > 0",
      "partial" => PARTIAL_SQL,
      "otp_verified" => "order_metrics.is_otp_verified",
      "cod_form" => "order_metrics.is_cod_form",
      "upsell" => "order_metrics.upsell_items > 0",
      "free_gift" => "order_metrics.free_gift_items > 0"
    }.freeze
    AC_EVENT_KEYS = %w[abandoned_cart cart_abandoned browse_abandoned].freeze
    PREPAID_VER_TYPE = "WHATSAPP_COD_PREPAID"
    INR_PER_USD = 95.0
    MAX_DAYS = 366
    PAGE_SIZE = 25

    def initialize(shop, from: nil, to: nil, days: nil)
      @shop = shop
      @zone = CodForm::Analytics::ShopTime.zone(shop)
      today = Time.current.in_time_zone(@zone).to_date
      @to = parse_date(to) || today
      @from = parse_date(from) || (@to - ((days.presence || 7).to_i.clamp(1, MAX_DAYS) - 1))
      @from = @to if @from > @to
    end

    def summary
      values = to_values(SUMMARY_COLUMNS, scope.pick(*SUMMARY_COLUMNS.values.map { |sql| Arel.sql(sql) }))
      values = values.merge(legacy_values) { |_, tracked, legacy| tracked + legacy }
      values[:recovered_count], values[:recovered_value] = recovered_carts(charge_window)
      generated = values[:hero_orders_value] + values[:cod_fee_amount]
      charges = charges_breakdown(values[:partial_value])
      total_charges = charges&.values&.sum
      prepaid_cost = charges && (charges[:prepaid_fee] + charges[:prepaid_messages]).round(2)

      {
        range: range_json,
        currency: @shop.currency,
        features: enabled_features,
        store: {
          orders: values[:orders],
          revenue: values[:orders_value],
          cod_orders: values[:cod_orders],
          prepaid_orders: values[:orders] - values[:cod_orders]
        },
        roi: {
          generated: generated,
          charges: total_charges,
          multiple: ratio(generated, total_charges),
          breakdown: charges
        },
        converted_prepaid: {
          count: values[:converted_count],
          value: values[:converted_value],
          charges: prepaid_cost,
          fee: charges&.dig(:prepaid_fee),
          message_charges: charges&.dig(:prepaid_messages),
          multiple: ratio(values[:converted_value], prepaid_cost)
        },
        ac_recovered: {
          count: values[:recovered_count],
          value: values[:recovered_value],
          messages_sent: abandoned_cart_messages_sent,
          charges: charges&.dig(:abandoned_cart),
          multiple: ratio(values[:recovered_value], charges&.dig(:abandoned_cart))
        },
        cod_fee: { count: values[:cod_fee_count], value: values[:cod_fee_amount], by_source: cod_fee_by_source },
        partial: {
          count: values[:partial_count],
          upfront: values[:partial_upfront],
          order_value: values[:partial_value],
          fee: charges&.dig(:partial_fee),
          multiple: ratio(values[:partial_value], charges&.dig(:partial_fee))
        },
        otp_verified: { count: values[:otp_count] },
        cod_form: { count: values[:cod_form_count], value: values[:cod_form_value] },
        upsell: { count: values[:upsell_count], items: values[:upsell_items], value: values[:upsell_revenue] },
        free_gift: {
          count: values[:free_gift_count],
          items: values[:free_gift_items],
          value: values[:free_gift_revenue],
          gift_value: values[:free_gift_value],
          by_rule: free_gift_by_rule
        }
      }
    end

    def orders(filter:, cursor: nil)
      return recovered_cart_orders(cursor) if filter == "ac_recovered"

      rel = scope
      condition = FILTERS[filter]
      rel = rel.where(condition) if condition
      if cursor.present?
        at, id = cursor.to_s.split("_", 2)
        rel = rel.where("(ordered_at, order_metrics.id) < (?, ?)", Time.zone.parse(at.to_s), id.to_i) if at.present? && id.present?
      end

      rows = rel.order(ordered_at: :desc, id: :desc)
                .limit(PAGE_SIZE + 1)
                .select("order_metrics.*", "oc.customer_name AS customer_name", "#{PARTIAL_SQL} AS partial_flag")
                .to_a
      has_next = rows.size > PAGE_SIZE
      rows = rows.first(PAGE_SIZE)

      {
        range: range_json,
        currency: @shop.currency,
        orders: rows.map { |m| order_json(m) },
        next_cursor: has_next ? "#{rows.last.ordered_at.utc.iso8601(6)}_#{rows.last.id}" : nil
      }
    end

    private

    SUMMARY_COLUMNS = {
      orders: "COUNT(*)",
      orders_value: "COALESCE(SUM(total_price), 0)",
      cod_orders: "COUNT(*) FILTER (WHERE is_cod)",
      hero_orders_value: "COALESCE(SUM(total_price) FILTER (WHERE is_converted_prepaid OR is_ac_recovered OR #{PARTIAL_SQL} OR is_cod_form), 0)",
      converted_count: "COUNT(*) FILTER (WHERE is_converted_prepaid)",
      converted_value: "COALESCE(SUM(total_price) FILTER (WHERE is_converted_prepaid), 0)",
      recovered_count: "COUNT(*) FILTER (WHERE is_ac_recovered)",
      recovered_value: "COALESCE(SUM(total_price) FILTER (WHERE is_ac_recovered), 0)",
      cod_fee_count: "COUNT(*) FILTER (WHERE cod_fee > 0)",
      cod_fee_amount: "COALESCE(SUM(cod_fee), 0)",
      partial_count: "COUNT(*) FILTER (WHERE #{PARTIAL_SQL})",
      partial_upfront: "COALESCE(SUM(partial_upfront), 0)",
      partial_value: "COALESCE(SUM(original_total) FILTER (WHERE #{PARTIAL_SQL}), 0)",
      otp_count: "COUNT(*) FILTER (WHERE is_otp_verified)",
      cod_form_count: "COUNT(*) FILTER (WHERE is_cod_form)",
      cod_form_value: "COALESCE(SUM(total_price) FILTER (WHERE is_cod_form), 0)",
      upsell_count: "COUNT(*) FILTER (WHERE upsell_items > 0)",
      upsell_items: "COALESCE(SUM(upsell_items), 0)",
      upsell_revenue: "COALESCE(SUM(upsell_revenue), 0)",
      free_gift_count: "COUNT(*) FILTER (WHERE free_gift_items > 0)",
      free_gift_items: "COALESCE(SUM(free_gift_items), 0)",
      free_gift_value: "COALESCE(SUM(free_gift_value), 0)",
      free_gift_revenue: "COALESCE(SUM(total_price) FILTER (WHERE free_gift_items > 0), 0)"
    }.freeze

    LEGACY_AMOUNT = "CASE WHEN oc.order_amount ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN oc.order_amount::numeric ELSE 0 END"
    LEGACY_LIVE = "COALESCE(oc.status, '') NOT ILIKE '%cancel%' AND r.cancelled_at IS NULL"
    LEGACY_COLUMNS = {
      orders: "COUNT(*) FILTER (WHERE #{LEGACY_LIVE})",
      orders_value: "COALESCE(SUM(#{LEGACY_AMOUNT}) FILTER (WHERE #{LEGACY_LIVE}), 0)",
      cod_orders: "COUNT(*) FILTER (WHERE #{LEGACY_LIVE} AND oc.is_cod_order)",
      converted_count: "COUNT(*) FILTER (WHERE oc.status = 'COD-Prepaid')",
      converted_value: "COALESCE(SUM(#{LEGACY_AMOUNT}) FILTER (WHERE oc.status = 'COD-Prepaid'), 0)",
      partial_count: "COUNT(*) FILTER (WHERE oc.status = 'COD-Partial-Payment-Received')",
      partial_value: "COALESCE(SUM(#{LEGACY_AMOUNT}) FILTER (WHERE oc.status = 'COD-Partial-Payment-Received'), 0)",
      otp_count: "COUNT(*) FILTER (WHERE oc.is_otp_verified AND #{LEGACY_LIVE})",
      cod_form_count: "COUNT(*) FILTER (WHERE oc.source_name = 'codking_form' AND #{LEGACY_LIVE})",
      cod_form_value: "COALESCE(SUM(#{LEGACY_AMOUNT}) FILTER (WHERE oc.source_name = 'codking_form' AND #{LEGACY_LIVE}), 0)",
      cod_form_only_value: "COALESCE(SUM(#{LEGACY_AMOUNT}) FILTER (WHERE oc.source_name = 'codking_form' AND #{LEGACY_LIVE} " \
                           "AND oc.status IS DISTINCT FROM 'COD-Partial-Payment-Received'), 0)"
    }.freeze
    PARTIAL_FIELDS = %w[cod_fee partial_upfront].freeze

    def legacy_window
      return @legacy_window if defined?(@legacy_window)

      start = @from.in_time_zone(@zone).beginning_of_day
      finish = [tracking_since, @to.in_time_zone(@zone).end_of_day].compact.min
      @legacy_window = finish > start ? (start...finish) : nil
    end

    def legacy_values
      window = legacy_window
      return {} unless window

      shop_domain_id = ShopDomain.where(shopify_domain: @shop.shopify_domain).pick(:id) || 0
      row = OrderConfirmation.from("order_confirmations oc")
        .joins(ActiveRecord::Base.sanitize_sql_array(["LEFT JOIN rto_orders r ON r.shop_domain_id = ? AND r.order_id = oc.order_id", shop_domain_id]))
        .where("oc.shop_id = ? AND oc.created_at >= ? AND oc.created_at < ?", @shop.id, window.begin, window.end)
        .where("oc.status IS DISTINCT FROM 'Test-Order'")
        .pick(*LEGACY_COLUMNS.values.map { |sql| Arel.sql(sql) })
      values = to_values(LEGACY_COLUMNS, row)

      values[:recovered_count], values[:recovered_value] = recovered_carts(window)
      values[:hero_orders_value] = values[:converted_value] + values[:recovered_value] + values[:partial_value] +
                                   values.delete(:cod_form_only_value)
      values
    end

    def recovered_cart_orders(cursor)
      carts = AbandonedCart.where(shop_id: @shop.id, updated_at: charge_window)
                           .where("LOWER(notes) = 'recovered'")
                           .group(:checkout_id)
                           .select("checkout_id, MAX(total_price) AS cart_value, MAX(updated_at) AS recovered_at, " \
                                   "MAX(name) AS customer_name, MAX(phone) AS phone")
      rel = AbandonedCart.from(carts, :carts)
      if cursor.present?
        at, id = cursor.to_s.split("_", 2)
        rel = rel.where("(recovered_at, checkout_id) < (?, ?)", Time.zone.parse(at.to_s), id) if at.present? && id.present?
      end
      rows = rel.select("carts.*").order(Arel.sql("recovered_at DESC, checkout_id DESC")).limit(PAGE_SIZE + 1).to_a
      has_next = rows.size > PAGE_SIZE
      rows = rows.first(PAGE_SIZE)

      {
        range: range_json,
        currency: @shop.currency,
        orders: rows.map do |c|
          {
            kind: "cart",
            order_id: c.checkout_id,
            customer_name: c.customer_name.presence || c.phone,
            ordered_at: c.recovered_at.in_time_zone(@zone).iso8601,
            total_price: c.cart_value.to_f,
            is_ac_recovered: true
          }
        end,
        next_cursor: has_next ? "#{rows.last.recovered_at.utc.iso8601(6)}_#{rows.last.checkout_id}" : nil
      }
    end

    def recovered_carts(window)
      carts = AbandonedCart.where(shop_id: @shop.id, updated_at: window)
                           .where("LOWER(notes) = 'recovered'")
                           .group(:checkout_id)
                           .select("MAX(total_price) AS cart_value")
      count, value = AbandonedCart.from(carts, :carts).pick(Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(cart_value), 0)"))
      [count.to_i, value.to_f]
    end

    def to_values(columns, row)
      columns.keys.zip(Array(row).map { |v| v.is_a?(BigDecimal) || v.is_a?(Float) ? v.to_f : v.to_i }).to_h
    end

    def scope
      @scope ||= OrderMetric.joins(OC_JOIN)
                            .where(shop_id: @shop.id)
                            .where(ordered_at: effective_from_time..@to.in_time_zone(@zone).end_of_day)
                            .where.not(delivery_status: "cancelled")
    end

    def tracking_since
      return @tracking_since if defined?(@tracking_since)

      @tracking_since = Rails.cache.fetch("order_metrics:tracking_since:#{@shop.id}", skip_nil: true) do
        OrderMetric.where(shop_id: @shop.id).minimum(:created_at)
      end
    end

    def effective_from_time
      start = @from.in_time_zone(@zone).beginning_of_day
      tracking_since && tracking_since > start ? tracking_since : start
    end

    def range_json
      since_date = tracking_since&.in_time_zone(@zone)&.to_date
      {
        from: @from.to_s,
        to: @to.to_s,
        tracking_since: since_date&.to_s,
        partial: legacy_window.present?,
        partial_fields: legacy_window ? PARTIAL_FIELDS : []
      }
    end

    def free_gift_by_rule
      titles = FreeGifts.config_for(@shop)["rules"].to_h { |rule| [rule["id"], rule["title"].presence || rule.dig("gift", "title")] }
      scope.where("free_gift_items > 0")
           .joins("CROSS JOIN LATERAL jsonb_array_elements_text(COALESCE(order_metrics.free_gift_rule_ids, '[]'::jsonb)) AS fg(rule_id)")
           .group("fg.rule_id")
           .pluck(Arel.sql("fg.rule_id"), Arel.sql("COUNT(*)"), Arel.sql("SUM(total_price)"))
           .map { |rule_id, count, revenue| { rule_id: rule_id, title: titles[rule_id], count: count, value: revenue.to_f } }
    end

    def cod_fee_by_source
      scope.where("cod_fee > 0").group(:cod_fee_source).pluck(:cod_fee_source, Arel.sql("COUNT(*)"), Arel.sql("SUM(cod_fee)"))
           .map { |source, count, amount| { source: source, count: count, value: amount.to_f } }
    end

    SMS_VER_TYPES = ["SMS", "Confirmation-SMS", "Fulfilment-SMS"].freeze
    WHATSAPP_VER_TYPES = ["WHATSAPP", "WHATSAPP_FIRST_PURCHASE", "WHATSAPP-CONFIRMATION", "WHATSAPP-FULFILMENT", "WHATSAPP_COD_PREPAID"].freeze
    IVR_CHARGE = PricingJobs::DynamicChargeJob::DEFAULT_IVR_CHARGE
    AMOUNT_SQL = "CASE WHEN order_amount ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN order_amount::numeric ELSE 0 END"

    def charges_breakdown(partial_value)
      rate = usd_rate
      return nil unless rate

      usd = {
        verification: verification_charges,
        pre_order_otp: pre_order_charges,
        abandoned_cart: abandoned_cart_charges,
        prepaid_fee: prepaid_fee_charges,
        prepaid_messages: prepaid_message_charges
      }
      usd.transform_values { |amount| (amount.to_f * rate).round(2) }
         .merge(partial_fee: (partial_value * partial_fee_rate).round(2))
    end

    def charge_window
      @from.in_time_zone(@zone).beginning_of_day..@to.in_time_zone(@zone).end_of_day
    end

    def verification_charges
      twilio_charges(TwilioLog.where(shop_id: @shop.id, created_at: charge_window).where.not(ver_type: PREPAID_VER_TYPE))
    end

    def prepaid_message_charges
      twilio_charges(TwilioLog.where(shop_id: @shop.id, created_at: charge_window, ver_type: PREPAID_VER_TYPE)) +
        bsp_charges(%w[cod_to_prepaid])
    end

    def twilio_charges(logs)
      billed = logs.sum(:actual_charge_applied)
      return billed unless billable?

      pending = logs.where(is_charged: false, status: "SUCCESS")
      sms = pending.where(ver_type: SMS_VER_TYPES).group(:country_code, :num_segment).count
                   .sum { |(cc, segments), n| n * price_for(cc, :sms_price, segments, "sms") }
      whatsapp = pending.where(ver_type: WHATSAPP_VER_TYPES).group(:country_code, :ver_type).count.sum do |(cc, ver_type), n|
        n * price_for(cc, :whatsapp, nil, "whatsapp",
                      category: MessagePricing.whatsapp_category_for_ver_type(ver_type),
                      india_category: PricingV3India.whatsapp_category_for_ver_type(ver_type))
      end
      billed + sms + whatsapp + pending.where(ver_type: "IVR").count * IVR_CHARGE
    end

    def bsp_charges(event_keys)
      logs = WhatsappMessageLog.where(shop_id: @shop.id, created_at: charge_window, event_type_key: event_keys)
      billed = logs.sum(:actual_charge_applied)
      return billed unless billable?

      billed + logs.chargeable.group(:country_code, :event_type_key).count.sum do |(cc, key), n|
        n * price_for(cc, :bsp_whatsapp, nil, "bsp_whatsapp", category: PricingV3India.whatsapp_category_for_event(key))
      end
    end

    def pre_order_charges
      otps = PreOrderOtp.where(shop_id: @shop.id, created_at: charge_window)
      billed = otps.sum(:actual_charge_applied) + bsp_charges(%w[pre_order_otp])
      return billed unless billable?

      free_india = PreOrderOtpCampaign.free_otp_for_shop?(@shop)
      billed + otps.where(is_charged: nil, status: true).group(:ver_type, :country_code).count.sum do |(ver_type, cc), n|
        next 0 if free_india && cc.to_s.upcase == PreOrderOtpCampaign::FREE_COUNTRY_CODE

        price = ver_type == "WHATSAPP" ? price_for(cc, :whatsapp, nil, "whatsapp", category: :utility) : price_for(cc, :sms_price, nil, "sms")
        n * price
      end
    end

    def abandoned_cart_charges
      carts = AbandonedCart.where(shop_id: @shop.id, created_at: charge_window)
      billed = carts.sum(:actual_charge_applied) + bsp_charges(AC_EVENT_KEYS)
      return billed unless billable?

      pending = carts.where(is_charged: nil, status: "SUCCESS").group(:notif_type, :country_code).count.sum do |(notif_type, cc), n|
        price = case notif_type
                when "SMS" then price_for(cc, :sms_price, nil, "sms")
                when "WHATSAPP" then price_for(cc, :whatsapp, nil, "whatsapp", category: :marketing)
                else 0
                end
        n * price
      end
      billed + pending
    end

    def abandoned_cart_messages_sent
      AbandonedCart.where(shop_id: @shop.id, created_at: charge_window, status: "SUCCESS").count +
        WhatsappMessageLog.where(shop_id: @shop.id, created_at: charge_window, event_type_key: AC_EVENT_KEYS,
                                 status: %i[sent delivered read]).count
    end

    def prepaid_fee_charges
      orders = @shop.order_confirmations.where(status: "COD-Prepaid", created_at: charge_window)
      billed = orders.where(is_prepaid_charged: true).sum(:cod_fee)
      return billed unless billable?

      count, amount = orders.where(is_prepaid_charged: nil).pick(Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(#{AMOUNT_SQL}), 0)"))
      billed + ((amount.to_f - (count.to_i * @shop.setting&.prepaid_discount.to_f)) * 0.02 / 80)
    end

    def billable?
      @shop.charge_id.present? && @shop.setting&.provider.blank?
    end

    # Same rules DynamicChargeJob bills with (MessagePricing). price_key is kept for the call sites' readability.
    def price_for(country_code, _price_key, num_segment, mode, category: nil, india_category: category)
      @pricer ||= MessagePricing.new(
        pricings: TwilioPricing.all.index_by(&:country_code),
        charge_overrides: MessagePricing.load_charge_overrides.slice(@shop.id)
      )
      case mode.to_s
      when "sms" then @pricer.sms(@shop, country_code, num_segment)
      when "bsp_whatsapp" then @pricer.bsp_whatsapp(@shop, category: category)
      else @pricer.whatsapp(@shop, country_code, category: category, india_category: india_category)
      end.to_f
    end

    def enabled_features
      setting = @shop.setting
      return {} unless setting

      {
        converted_prepaid: setting.prepaid_enabled.present?,
        ac_recovered: setting.abandoned_cart_enabled.present? || setting.ac_whatsapp.present?,
        partial: setting.partial_payment_enabled.present?,
        cod_fee: setting.cod_fee_enabled.present? || setting.enable_shipping_cod_fees.present?,
        cod_form: setting.cod_form_enabled.present?,
        otp_verified: setting.enable_pre_order_otp.present? || setting.plus_checkout_otp_extension_enabled.present?,
        upsell: Upsells::Config.sanitize(@shop.additional_setting&.upsell_config)&.dig("enabled") == true,
        free_gift: FreeGifts.config_for(@shop)["enabled"] == true
      }
    end

    def partial_fee_rate
      @shop.id > 10_000 ? PartialTransactionFee.rate_for(@shop) : 0
    end

    def usd_rate
      currency = @shop.currency.presence&.upcase || "USD"
      return 1.0 if currency == "USD"
      return INR_PER_USD if currency == "INR"

      Rails.cache.fetch("order_metrics:usd_rate:#{currency}", expires_in: 6.hours, skip_nil: true) do
        rate = begin
          ExchangeRateBank.resolve.first.get_rate("USD", currency)&.to_f
        rescue StandardError
          nil
        end
        fallback = ExchangeRateBank.fallback_usd_rate(currency)
        rate&.positive? ? rate : (fallback && 1.0 / fallback)
      end
    end

    def ratio(value, cost)
      cost.to_f.positive? ? (value / cost).round(1) : nil
    end

    def order_json(m)
      {
        order_id: m.order_id,
        order_name: m.order_name,
        customer_name: m.customer_name,
        ordered_at: m.ordered_at.in_time_zone(@zone).iso8601,
        total_price: m.total_price.to_f,
        original_total: m.original_total.to_f,
        is_cod: m.is_cod,
        cod_fee: m.cod_fee.to_f,
        cod_fee_source: m.cod_fee_source,
        prepaid_discount: m.prepaid_discount.to_f,
        partial_upfront: m.partial_upfront.to_f,
        discount_total: m.discount_total.to_f,
        discounts: m.discounts,
        is_converted_prepaid: m.is_converted_prepaid,
        is_ac_recovered: m.is_ac_recovered,
        is_partial: m.partial_flag,
        is_otp_verified: m.is_otp_verified,
        is_cod_form: m.is_cod_form,
        upsell_items: m.upsell_items.to_i,
        upsell_revenue: m.upsell_revenue.to_f,
        free_gift_items: m.free_gift_items.to_i,
        free_gift_value: m.free_gift_value.to_f,
        delivery_status: m.delivery_status
      }
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

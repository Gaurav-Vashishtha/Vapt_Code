# frozen_string_literal: true

require "set"

module CodForm
  module Analytics
    # Pure aggregation of cf_* funnel events into cod_form_daily_stats metrics
    # (ARCHITECTURE.md I.1, B.17). No Rails, no I/O.
    #
    #   acc = Rollup::Accumulator.new(convert: ->(cents, currency) { cents })
    #   acc.add("type" => "cf_form_open", "session" => "…", "meta" => {...})
    #   acc.add_button_views("HU|mobile|8111" => 12)
    #   acc.result  # => {["all", ""] => {"form_opens" => 1, …}, ["country", "HU"] => {…}, …}
    module Rollup
      METRIC_KEYS = %w[
        button_views form_opens first_inputs shipping_selected submit_attempts submit_errors orders
        revenue_cents partial_handoffs prepaid_redirects closes otp_sent otp_verified offer_views
        offer_accepts downsell_shown downsell_accepts upsell_views upsell_accepts recovery_opens
        recovered_orders blocked fallbacks
      ].freeze
      # Two additive keys beyond the B.17 list (OTP bypass count for the OTP stats, prepaid orders
      # that started in the form). Readers that do not know them ignore them.
      EXTRA_METRIC_KEYS = %w[otp_bypassed prepaid_orders].freeze
      ALL_METRIC_KEYS = (METRIC_KEYS + EXTRA_METRIC_KEYS).freeze

      DIMENSIONS = %w[all country device product form utm_campaign offer].freeze

      EVENT_METRICS = {
        "cf_form_open" => "form_opens",
        "cf_first_input" => "first_inputs",
        "cf_shipping_selected" => "shipping_selected",
        "cf_submit_attempt" => "submit_attempts",
        "cf_submit_error" => "submit_errors",
        "cf_order_created" => "orders",
        "cf_partial_handoff" => "partial_handoffs",
        "cf_prepaid_redirect" => "prepaid_redirects",
        "cf_prepaid_order" => "prepaid_orders",
        "cf_form_close" => "closes",
        "cf_otp_sent" => "otp_sent",
        "cf_otp_verified" => "otp_verified",
        "cf_otp_bypassed" => "otp_bypassed",
        "cf_offer_view" => "offer_views",
        "cf_offer_accept" => "offer_accepts",
        "cf_downsell_shown" => "downsell_shown",
        "cf_downsell_accept" => "downsell_accepts",
        "cf_upsell_view" => "upsell_views",
        "cf_upsell_accept" => "upsell_accepts",
        "cf_recovery_open" => "recovery_opens",
        "cf_blocked" => "blocked",
        "cf_fallback" => "fallbacks"
      }.freeze

      # Funnel steps count sessions, not events: a buyer who retries a submit three times is
      # one session that reached the step.
      SESSION_UNIQUE_METRICS = %w[form_opens first_inputs shipping_selected submit_attempts].freeze

      MAX_DIMENSION_VALUE = 120

      module_function

      # One-shot form of the accumulator.
      def build(events:, button_views: {}, convert: nil)
        acc = Accumulator.new(convert: convert)
        Array(events).each { |event| acc.add(event) }
        acc.add_button_views(button_views)
        acc.result
      end

      def zero_metrics
        ALL_METRIC_KEYS.to_h { |key| [key, 0] }
      end

      # Sum of several metrics hashes (missing keys count as 0).
      def sum(list)
        total = zero_metrics
        Array(list).each do |metrics|
          next unless metrics.is_a?(Hash)

          metrics.each do |key, value|
            total[key] = total[key].to_i + value.to_i if value.is_a?(Numeric)
          end
        end
        total
      end

      # [dimension, value] pairs an event counts under. Always includes ["all", ""].
      def dimension_values(type, meta)
        meta = meta.is_a?(Hash) ? meta : {}
        pairs = [["all", ""]]
        add_pair(pairs, "country", meta["country"].to_s.upcase)
        add_pair(pairs, "device", meta["device"])
        product_ids = Array(meta["product_ids"])
        product_ids = [meta["product_id"]] if product_ids.empty? && meta["product_id"]
        product_ids.map(&:to_s).uniq.each { |id| add_pair(pairs, "product", id) }
        add_pair(pairs, "form", meta["form_id"])
        add_pair(pairs, "utm_campaign", meta["utm_campaign"])
        offer_ids = Array(meta["offer_ids"]).map(&:to_s)
        offer_ids << meta["offer_id"].to_s if meta["offer_id"]
        offer_ids.uniq.each { |id| add_pair(pairs, "offer", id) }
        pairs
      end

      def add_pair(pairs, dimension, value)
        text = value.to_s.strip
        return if text.empty?

        pairs << [dimension, text[0, MAX_DIMENSION_VALUE]]
      end

      # Keeps at most `limit` values per dimension (largest by form_opens + orders +
      # button_views), so one day of one shop stays bounded. "all" is never dropped.
      def cap_cardinality(result, limit: 500)
        grouped = result.group_by { |(dimension, _), _| dimension }
        kept = {}
        grouped.each do |dimension, entries|
          if dimension != "all" && entries.size > limit
            entries = entries.sort_by do |(_, value), m|
              [-(m["orders"].to_i * 1000 + m["form_opens"].to_i + m["button_views"].to_i), value]
            end.first(limit)
          end
          entries.each { |key, metrics| kept[key] = metrics }
        end
        kept
      end

      class Accumulator
        def initialize(convert: nil)
          @convert = convert
          @metrics = Hash.new { |hash, key| hash[key] = Rollup.zero_metrics }
          @seen = Hash.new { |hash, key| hash[key] = Set.new }
        end

        # event: {"type" => "cf_…", "session" => session token, "meta" => {...}}
        def add(event)
          return unless event.is_a?(Hash)

          type = event["type"].to_s
          metric = EVENT_METRICS[type]
          return if metric.nil?

          meta = event["meta"].is_a?(Hash) ? event["meta"] : {}
          return if meta["test"] == true

          session = event["session"].to_s
          Rollup.dimension_values(type, meta).each do |pair|
            if SESSION_UNIQUE_METRICS.include?(metric) && !session.empty?
              next unless @seen[[pair, metric]].add?(session)
            end
            bucket = @metrics[pair]
            bucket[metric] += 1
            next unless type == "cf_order_created"

            bucket["revenue_cents"] += revenue(meta)
            bucket["recovered_orders"] += 1 if meta["recovered"] == true || meta["source"].to_s == "recovery"
          end
        end

        # counts: {"<country>|<device>|<product_id>" => Integer} (Redis hash of one day)
        def add_button_views(counts)
          return unless counts.is_a?(Hash)

          counts.each do |field, raw|
            count = raw.to_i
            next unless count.positive?

            country, device, product = field.to_s.split("|", 3)
            pairs = [["all", ""]]
            Rollup.add_pair(pairs, "country", country.to_s.upcase)
            Rollup.add_pair(pairs, "device", device)
            Rollup.add_pair(pairs, "product", product)
            pairs.each { |pair| @metrics[pair]["button_views"] += count }
          end
        end

        def result
          @metrics.transform_values(&:dup)
        end

        private

        def revenue(meta)
          cents = meta["value_cents"].to_i
          return 0 unless cents.positive?
          return cents if @convert.nil?

          converted = @convert.call(cents, meta["currency"].to_s.upcase)
          converted.nil? ? cents : converted.to_i
        end
      end
    end
  end
end

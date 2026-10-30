# frozen_string_literal: true

module Churn
  # Risk customers for /support_dashboard/risk_customers.
  #
  # List: stores installed within the last `installed_within` days (default 60)
  # that are on a paid plan OR have more than `min_usage` USD (default 5) of
  # usage charges applied.
  #
  # Header: for stores installed between `rev_from` and `rev_to` — active
  # subscriptions (count + monthly plan value), usage charges applied, and
  # potential revenue (monthly subscriptions + usage applied).
  #
  # "Usage charges applied" = actual_charge_applied on SMS / IVR / WhatsApp,
  # BSP WhatsApp, abandoned-cart and pre-order OTP logs, plus prepaid / partial
  # payment fees — counted once the charge job applies them to the Shopify
  # subscription, billed or not. A reinstall creates a new shops row, so all of
  # it is per current install.
  #
  # The usage sums scan large log tables, so this runs in Churn::RiskCustomersJob
  # ("Load records" button) and the result is cached in Redis.
  class RiskCustomers
    DEFAULT_INSTALLED_WITHIN = 60
    DEFAULT_MIN_USAGE = 5
    DEFAULT_REVENUE_DAYS = 30
    SORTS = %w[usage plan orders customers newest].freeze
    PLAN_PRICE_SQL = "NULLIF(regexp_replace(COALESCE(plans.price, ''), '[^0-9.]', '', 'g'), '')::numeric"
    CACHE_TTL = 24 * 3600
    BUILDING_TTL = 15 * 60

    Row = Struct.new(:shop_id, :paid, :usage, :plan_price, :orders, :customers, keyword_init: true)

    attr_reader :installed_within, :min_usage, :rev_from, :rev_to

    def initialize(installed_within: nil, min_usage: nil, rev_from: nil, rev_to: nil)
      @installed_within = (installed_within.presence || DEFAULT_INSTALLED_WITHIN).to_i.clamp(1, 3650)
      @min_usage = [(min_usage.presence || DEFAULT_MIN_USAGE).to_f, 0].max
      @rev_to = parse_date(rev_to) || Date.current
      @rev_from = parse_date(rev_from) || (@rev_to - (DEFAULT_REVENUE_DAYS - 1))
      @rev_from, @rev_to = @rev_to, @rev_from if @rev_from > @rev_to
    end

    def params
      { installed_within: installed_within, min_usage: min_usage, rev_from: rev_from.iso8601, rev_to: rev_to.iso8601 }
    end

    # ---- cache ---------------------------------------------------------------

    def cache_key
      "churn:risk_customers:v5:#{installed_within}:#{min_usage}:#{rev_from}:#{rev_to}"
    end

    def building_key
      "#{cache_key}:building"
    end

    def cached
      return @cached if defined?(@cached)

      raw = Sidekiq.redis { |r| r.get(cache_key) }
      @cached = raw && JSON.parse(raw)
    rescue => e
      Rails.logger.warn("[Churn::RiskCustomers] cache read failed: #{e.message}")
      @cached = nil
    end

    def loaded?
      cached.present?
    end

    def generated_at
      cached && Time.zone.parse(cached['generated_at'].to_s)
    end

    def rows
      return [] unless loaded?

      @rows ||= cached['rows'].map do |id, paid, usage, price, orders, customers|
        Row.new(shop_id: id, paid: paid, usage: usage.to_f, plan_price: price.to_f, orders: orders.to_i, customers: customers.to_i)
      end
    end

    def counts
      loaded? ? cached['counts'].symbolize_keys : { paid: 0, usage: 0 }
    end

    def summary
      return nil unless loaded?

      s = cached['summary'].symbolize_keys
      s.merge(from: Date.parse(s[:from]), to: Date.parse(s[:to]))
    end

    def building_since
      raw = Sidekiq.redis { |r| r.get(building_key) }
      raw && Time.zone.parse(raw)
    rescue
      nil
    end

    # Enqueue the background build (no-op if one is already running for these params).
    def request_load!
      started = Sidekiq.redis { |r| r.set(building_key, Time.current.iso8601, nx: true, ex: BUILDING_TTL) }
      Churn::RiskCustomersJob.perform_async(params.stringify_keys) if started
      started
    end

    # ---- build (runs in the job) -------------------------------------------

    def build!
      list_since = installed_within.days.ago
      summary_from = rev_from.beginning_of_day
      summary_to = rev_to.end_of_day
      earliest = [list_since, summary_from].min

      shops = self.class.base_scope.where('shops.created_at >= ?', earliest).pluck(:id, :created_at, :customer_count)
      customers = shops.to_h { |id, _, count| [id, count.to_i] }
      shops = shops.map { |id, at, _| [id, at] }
      ids = shops.map(&:first)
      prices = Shop.where(id: ids).joins(:plan).where.not(charge_id: [nil, ''])
                   .where("#{PLAN_PRICE_SQL} > 0").pluck(:id, Arel.sql(PLAN_PRICE_SQL))
                   .to_h { |id, price| [id, price.to_f] }
      usage = self.class.usage_by_shop(ids, since: earliest)
      orders = self.class.orders_by_shop(ids, since: earliest)

      list_ids = shops.select { |_, at| at >= list_since }.map(&:first)
      paid = list_ids.select { |id| prices.key?(id) }
      over = list_ids.select { |id| usage[id].to_f > min_usage }
      rows = (paid | over).map { |id| [id, prices.key?(id), usage[id].to_f.round(2), prices[id].to_f, orders[id].to_i, customers[id].to_i] }

      summary_ids = shops.select { |_, at| at >= summary_from && at <= summary_to }.map(&:first)
      sub_ids = summary_ids.select { |id| prices.key?(id) }
      sub_total = sub_ids.sum { |id| prices[id] }.round(2)
      usage_total = summary_ids.sum { |id| usage[id].to_f }.round(2)

      data = {
        generated_at: Time.current.iso8601,
        rows: rows,
        counts: { paid: paid.size, usage: over.size },
        summary: {
          from: rev_from.iso8601, to: rev_to.iso8601,
          installs: summary_ids.size,
          subscriptions: sub_ids.size,
          subscription_mrr: sub_total,
          usage_total: usage_total,
          usage_stores: summary_ids.count { |id| usage[id].to_f.positive? },
          potential: (sub_total + usage_total).round(2),
          orders: summary_ids.sum { |id| orders[id].to_i },
          customers: summary_ids.sum { |id| customers[id].to_i }
        }
      }
      Sidekiq.redis { |r| r.set(cache_key, data.to_json, ex: CACHE_TTL) }
      data
    ensure
      Sidekiq.redis { |r| r.del(building_key) } rescue nil
    end

    def self.base_scope
      scope = Shop.real_installs
      Shop.column_names.include?('source') ? scope.where(source: 'shopify') : scope
    end

    # Usage applied per shop. Filtering on created_at (every log of a current
    # install is newer than the install) lets Postgres use the
    # (shop_id, created_at, ...) indexes instead of reading each shop's history.
    def self.usage_by_shop(ids, since:)
      totals = Hash.new(0.0)
      return totals if ids.empty?

      ids.each_slice(500) do |batch|
        [TwilioLog, WhatsappMessageLog, AbandonedCart, PreOrderOtp].each do |model|
          model.where(shop_id: batch).where('created_at >= ?', since).where('actual_charge_applied > 0')
               .group(:shop_id).sum(:actual_charge_applied)
               .each { |id, amount| totals[id] += amount.to_f }
        end
        OrderConfirmation.where(shop_id: batch, is_prepaid_charged: true).where('created_at >= ?', since)
                         .where('cod_fee > 0').group(:shop_id).sum(:cod_fee)
                         .each { |id, amount| totals[id] += amount.to_f }
      end
      totals
    end

    # Order confirmations per shop since install, test orders excluded. Uses
    # idx_oc_daily_analytics (shop_id, created_at, status WHERE status <> 'Test-Order').
    def self.orders_by_shop(ids, since:)
      totals = Hash.new(0)
      ids.each_slice(500) do |batch|
        OrderConfirmation.where(shop_id: batch).where('created_at >= ?', since)
                         .where("status <> 'Test-Order'").group(:shop_id).count
                         .each { |id, n| totals[id] += n }
      end
      totals
    end

    private

    def parse_date(value)
      value.present? ? Date.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end
  end
end

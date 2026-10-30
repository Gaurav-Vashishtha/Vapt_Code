# frozen_string_literal: true

module Ops
  # Builds the /codk-ops overview payload for an IST date range.
  # Every query is range-bound on an indexed column or reads a rollup table;
  # nothing here scans customers/customer_addresses or whole order_confirmations.
  class Overview
    TZ = Ops::GmvRollup::TZ
    MAX_DAYS = 400
    TOP_LIMIT = 20
    SUBSCRIPTION_EVENTS = [PartnerAppEvent::CHARGE_ACTIVATED, PartnerAppEvent::CHARGE_CANCELED].freeze
    LIFECYCLE_EVENTS = [PartnerAppEvent::INSTALLED, PartnerAppEvent::UNINSTALLED].freeze

    attr_reader :from, :to

    def initialize(from: nil, to: nil)
      @zone = ActiveSupport::TimeZone[TZ]
      today = @zone.today
      to_d = parse(to) || today
      from_d = parse(from) || (to_d - 29)
      to_d = [to_d, today].min
      from_d, to_d = to_d, from_d if from_d > to_d
      from_d = to_d - (MAX_DAYS - 1) if (to_d - from_d) >= MAX_DAYS
      @from = from_d
      @to = to_d
    end

    def self.cached(from:, to:)
      overview = new(from: from, to: to)
      Rails.cache.fetch("codk_ops:overview:v2:#{overview.from}:#{overview.to}", expires_in: 5.minutes) { overview.call }
    end

    def call
      {
        range: { from: from.to_s, to: to.to_s, days: dates.size, timezone: TZ },
        generated_at: Time.current.iso8601,
        revenue: revenue,
        subscriptions: subscriptions,
        gmv: gmv,
        active_subscriptions: active_subscriptions,
        top_new_shops: top_new_shops,
        churn: churn,
        customer_bulk: Ops::CustomerBulkSummary.new.call
      }
    end

    private

    def parse(value)
      value.present? ? Date.iso8601(value.to_s) : nil
    rescue ArgumentError
      nil
    end

    def dates
      @dates ||= (from..to).to_a
    end

    def start_time
      @start_time ||= @zone.local(from.year, from.month, from.day).utc
    end

    def end_time
      @end_time ||= start_time + dates.size.days
    end

    def ist_date(column)
      Arel.sql("((#{column} AT TIME ZONE 'UTC') AT TIME ZONE '#{TZ}')::date")
    end

    def app_gid
      PartnerApi::GraphqlClient.app_gid
    end

    # ---- 1. Partner revenue per day: usage charges + subscriptions --------
    def revenue
      date_sql = ist_date('occurred_at')
      scope = PartnerSale.where(app_id: app_gid, occurred_at: start_time...end_time)
      rows = scope.group(date_sql, :sale_type)
                  .pluck(date_sql, :sale_type, Arel.sql('SUM(net_amount)'), Arel.sql('SUM(gross_amount)'), Arel.sql('COUNT(*)'))
      currency = scope.group(:currency).order(Arel.sql('COUNT(*) DESC')).limit(1).pluck(:currency).first || 'USD'

      by_day = dates.index_with { { usage: 0.0, subscription: 0.0, adjustment: 0.0, gross: 0.0, usage_count: 0 } }
      rows.each do |day, type, net, gross, count|
        bucket = by_day[day.to_date] or next
        key = %w[usage subscription].include?(type) ? type.to_sym : :adjustment
        bucket[key] += net.to_f
        bucket[:gross] += gross.to_f
        bucket[:usage_count] += count.to_i if type == 'usage'
      end

      days = by_day.map do |day, b|
        net = b[:usage] + b[:subscription] + b[:adjustment]
        { date: day.to_s, usage: b[:usage].round(2), subscription: b[:subscription].round(2),
          adjustment: b[:adjustment].round(2), net: net.round(2), gross: b[:gross].round(2) }
      end
      totals = %i[usage subscription adjustment net gross].index_with { |k| days.sum { |d| d[k] }.round(2) }
      { currency: currency, days: days, totals: totals }
    end

    # ---- 1b. Subscriptions bought / cancelled + installs / uninstalls ------
    def subscriptions
      date_sql = ist_date('occurred_at')
      rows = PartnerAppEvent.live_charges
                            .where(occurred_at: start_time...end_time, event_type: SUBSCRIPTION_EVENTS + LIFECYCLE_EVENTS)
                            .group(date_sql, :event_type)
                            .pluck(date_sql, :event_type,
                                   Arel.sql('COUNT(*)'),
                                   Arel.sql('COUNT(*) FILTER (WHERE charge_amount > 0)'),
                                   Arel.sql('COALESCE(SUM(charge_amount) FILTER (WHERE charge_amount > 0), 0)'))
      blank = -> { { bought: 0, cancelled: 0, mrr_added: 0.0, mrr_lost: 0.0, installs: 0, uninstalls: 0 } }
      by_day = dates.index_with { blank.call }
      rows.each do |day, type, count, paid_count, paid_amount|
        b = by_day[day.to_date] or next
        case type
        when PartnerAppEvent::CHARGE_ACTIVATED then b[:bought] += paid_count.to_i; b[:mrr_added] += paid_amount.to_f
        when PartnerAppEvent::CHARGE_CANCELED then b[:cancelled] += paid_count.to_i; b[:mrr_lost] += paid_amount.to_f
        when PartnerAppEvent::INSTALLED then b[:installs] += count.to_i
        when PartnerAppEvent::UNINSTALLED then b[:uninstalls] += count.to_i
        end
      end
      days = by_day.map { |day, b| b.merge(date: day.to_s, mrr_added: b[:mrr_added].round(2), mrr_lost: b[:mrr_lost].round(2)) }
      totals = %i[bought cancelled mrr_added mrr_lost installs uninstalls].index_with { |k| days.sum { |d| d[k] }.round(2) }
      { days: days, totals: totals, note: 'Paid subscription charges only (amount > 0), test charges excluded.' }
    end

    # ---- 2. GMV from the rollup table, converted to INR --------------------
    def gmv
      rates = Ops::Fx.rates
      rows = OpsGmvDaily.where(stat_date: from..to).to_a
      by_day = dates.index_with { { orders: 0, gmv_inr: 0.0, cod_inr: 0.0, prepaid_inr: 0.0 } }
      unconverted = Hash.new { |h, k| h[k] = { orders: 0, amount: 0.0 } }
      unparsed = 0

      rows.each do |r|
        b = by_day[r.stat_date]
        next unless b
        b[:orders] += r.orders
        unparsed += r.unparsed_orders
        inr = Ops::Fx.to_inr(r.gmv, r.currency, rates)
        if inr.nil?
          unconverted[r.currency][:orders] += r.orders
          unconverted[r.currency][:amount] += r.gmv.to_f
        else
          b[:gmv_inr] += inr
          b[r.is_cod ? :cod_inr : :prepaid_inr] += inr
        end
      end

      days = by_day.map { |day, b| { date: day.to_s, orders: b[:orders], gmv: b[:gmv_inr].round(0), cod: b[:cod_inr].round(0), prepaid: b[:prepaid_inr].round(0) } }
      totals = { orders: days.sum { |d| d[:orders] }, gmv: days.sum { |d| d[:gmv] }, cod: days.sum { |d| d[:cod] }, prepaid: days.sum { |d| d[:prepaid] } }
      {
        currency: 'INR', days: days, totals: totals, unparsed_orders: unparsed,
        unconverted: unconverted.map { |cur, v| { currency: cur, orders: v[:orders], amount: v[:amount].round(2) } },
        fx_rates: rates.slice(*rows.map(&:currency).uniq),
        coverage_from: OpsGmvDaily.minimum(:stat_date)&.to_s,
        rollup_updated_at: OpsGmvDaily.maximum(:updated_at)&.iso8601
      }
    end

    # ---- 3. Active subscriptions (daily snapshot from SubscriptionActiveJob)
    def active_subscriptions
      snaps = OpsDailySnapshot.where(stat_date: from..to).order(:stat_date)
      latest = OpsDailySnapshot.order(stat_date: :desc).first
      {
        series: snaps.map { |s| { date: s.stat_date.to_s, count: s.active_subscriptions, mrr_usd: s.mrr_usd.to_f } },
        latest: latest && { date: latest.stat_date.to_s, count: latest.active_subscriptions, mrr_usd: latest.mrr_usd.to_f,
                            complete: latest.complete, plans: latest.plan_breakdown }
      }
    end

    # ---- 4. Top shops added in range, ranked by orders ---------------------
    def top_new_shops
      shops = Shop.where(created_at: start_time...end_time).select(:id, :shopify_domain, :country_code, :plan_id, :created_at).to_a
      total_new = shops.size
      return { total: 0, shops: [] } if shops.empty?

      ids = shops.map(&:id)
      orders = OrderConfirmation.where(shop_id: ids, created_at: start_time...end_time)
                                .where("status IS DISTINCT FROM 'Test-Order'").group(:shop_id).count
      plans = Plan.where(id: shops.filter_map(&:plan_id).uniq).pluck(:id, :name).to_h
      domains = shops.first(5000).map(&:shopify_domain)
      net = PartnerSale.where(app_id: app_gid, shopify_domain: domains, occurred_at: start_time...end_time)
                       .group(:shopify_domain).sum(:net_amount)

      top = shops.sort_by { |s| [-orders[s.id].to_i, -net[s.shopify_domain].to_f] }.first(TOP_LIMIT).map do |s|
        { domain: s.shopify_domain, country: s.country_code, plan: plans[s.plan_id], installed_at: s.created_at.iso8601,
          orders: orders[s.id].to_i, net_revenue: net[s.shopify_domain].to_f.round(2) }
      end
      { total: total_new, shops: top }
    end

    # ---- 5. Top churned shops in range --------------------------------------
    def churn
      scope = ChurnedStore.where(churned_at: start_time...end_time)
      by_type = scope.group(:churn_type).count
      reasons = scope.where.not(uninstall_reason: [nil, '']).group(:uninstall_reason).order(Arel.sql('COUNT(*) DESC')).limit(8).count
      top = scope.order(Arel.sql('last_30d_net DESC, orders_processed DESC NULLS LAST')).limit(TOP_LIMIT).map do |c|
        { domain: c.shopify_domain, type: c.type_label, churned_at: c.churned_at.iso8601, country: c.country,
          plan: c.plan_name, plan_amount: c.plan_amount&.to_f, tenure_days: c.tenure_days, orders: c.orders_processed.to_i,
          last_30d_net: c.last_30d_net.to_f.round(2), ltv_net: c.ltv_net.to_f.round(2), reason: c.uninstall_reason,
          returned: c.returned }
      end
      {
        total: by_type.values.sum,
        by_type: ChurnedStore::TYPES.map { |key, label| { type: label, count: by_type[key].to_i } },
        reasons: reasons.map { |reason, count| { reason: reason, count: count } },
        shops: top
      }
    end
  end
end

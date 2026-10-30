# frozen_string_literal: true

module Churn
  # Read model for /support_dashboard/churn. Reads churned_stores (built by
  # Churn::ChurnedStoresSyncJob) + partner_sales for the revenue baseline.
  #
  # Rates for a period [from, to]:
  #   Store churn rate        = uninstalls ÷ installed stores at `from`
  #   Subscription churn rate = paying stores lost (cancelled, downgraded, or uninstalled while paying)
  #                             ÷ stores that paid us in the 30 days before `from`
  #   Revenue churn rate      = churned stores' net revenue in their last 30 days
  #                             ÷ total net revenue in the 30 days before `from`
  # All three are NET: churn rows whose store later came back are excluded.
  # The list filters (LTV, last-30d revenue, orders, store age, days with COD
  # King, type, came back, sort) apply to the list only; the aggregates always
  # describe the whole period.
  class Dashboard
    BASELINE = 30.days
    RETURNED_FILTERS = %w[yes no].freeze
    SORTS = {
      'recent' => 'churned_at DESC',
      'ltv' => 'ltv_net DESC, churned_at DESC',
      'last_30d' => 'last_30d_net DESC, churned_at DESC',
      'orders' => 'orders_processed DESC NULLS LAST, churned_at DESC',
      'tenure' => 'tenure_days DESC NULLS LAST, churned_at DESC',
      'store_age' => 'store_created_on ASC NULLS LAST, churned_at DESC'
    }.freeze
    NUMERIC_FILTERS = %i[min_ltv min_last_30d min_orders
                         min_store_age_months max_store_age_months
                         min_tenure_days max_tenure_days].freeze

    attr_reader :from, :to, :churn_type, :returned, :sort, :numeric

    def initialize(from:, to:, churn_type: nil, returned: nil, sort: nil, **numeric)
      @from = from.in_time_zone.beginning_of_day
      @to = to.in_time_zone.end_of_day
      @churn_type = ChurnedStore::TYPES.key?(churn_type) ? churn_type : nil
      @returned = RETURNED_FILTERS.include?(returned) ? returned : nil
      @sort = SORTS.key?(sort) ? sort : 'recent'
      @numeric = numeric.slice(*NUMERIC_FILTERS).compact
    end

    def stores
      n = numeric
      scope = ChurnedStore.in_period(from, to)
      scope = scope.where('ltv_net >= ?', n[:min_ltv]) if n[:min_ltv]
      scope = scope.where('last_30d_net >= ?', n[:min_last_30d]) if n[:min_last_30d]
      scope = scope.where('orders_processed >= ?', n[:min_orders]) if n[:min_orders]
      # Store age = how old the Shopify store was when it churned.
      age_days = Arel.sql('(churned_at::date - store_created_on)')
      scope = scope.where("#{age_days} >= ?", (n[:min_store_age_months] * 30.44).round) if n[:min_store_age_months]
      scope = scope.where("#{age_days} <= ?", (n[:max_store_age_months] * 30.44).round) if n[:max_store_age_months]
      scope = scope.where('tenure_days >= ?', n[:min_tenure_days]) if n[:min_tenure_days]
      scope = scope.where('tenure_days <= ?', n[:max_tenure_days]) if n[:max_tenure_days]
      scope = scope.where(churn_type: churn_type) if churn_type
      scope = scope.where(returned: returned == 'yes') if returned
      scope.reorder(Arel.sql(SORTS[sort]))
    end

    def summary
      @summary ||= build_summary
    end

    private

    # Churn is NET of stores that came back: a store that reinstalled (or took
    # a paid plan again) after churning is not counted in the rates, revenue
    # lost or LTV. They are reported separately as "came back", and the gross
    # figures are kept for the subtext.
    def build_summary
      period = ChurnedStore.in_period(from, to)
      gross = grouped(period)
      lost = grouped(period.where(returned: false))
      by_type = ChurnedStore::TYPES.keys.index_with do |t|
        g = gross[t] || BLANK
        (lost[t] || BLANK).merge(gross_count: g[:count], returned: g[:returned], recovered: g[:recovered])
      end

      totals = distinct_store_totals(period, lost_only: true)
      all_stores = distinct_store_totals(period, lost_only: false)
      totals = totals.merge(returned: all_stores[:returned], recovered: all_stores[:recovered],
                            gross_count: all_stores[:count])

      uninstalls = by_type['uninstalled'][:count]
      sub_churn = ChurnedStore::SUBSCRIPTION_TYPES.sum { |t| by_type[t][:count] }

      # Paying stores lost = stores that stopped paying us in the period, by
      # cancelling/downgrading OR by uninstalling while paying ("paying" = net
      # revenue in the 30 days before churn, the same test as the denominator).
      # Each store counts once; stores that came back are excluded.
      lost_rows = period.where(returned: false)
      paid_uninstall_domains = lost_rows.uninstalls.where('last_30d_net > 0').distinct.pluck(:shopify_domain)
      sub_churn_domains = lost_rows.subscription_churn.distinct.pluck(:shopify_domain)
      paying_lost = (paid_uninstall_domains | sub_churn_domains).size

      active_at_start = active_stores_at(from)
      baseline = PartnerSale.where(app_id: PartnerApi::GraphqlClient.app_gid, occurred_at: (from - BASELINE)...from)
      revenue_base = baseline.sum(:net_amount).to_f
      paying_at_start = baseline.group(:shopify_domain).having('SUM(net_amount) > 0').count.size

      {
        by_type: by_type,
        totals: totals,
        uninstalls: uninstalls,
        uninstalls_gross: by_type['uninstalled'][:gross_count],
        uninstalls_returned: by_type['uninstalled'][:returned],
        subscription_churn: sub_churn,
        subscription_churn_gross: ChurnedStore::SUBSCRIPTION_TYPES.sum { |t| by_type[t][:gross_count] },
        subscription_churn_returned: ChurnedStore::SUBSCRIPTION_TYPES.sum { |t| by_type[t][:returned] },
        active_at_start: active_at_start,
        paying_at_start: paying_at_start,
        revenue_base: revenue_base.round(2),
        store_churn_rate: pct(uninstalls, active_at_start),
        paying_lost: paying_lost,
        paying_lost_uninstalled: (paid_uninstall_domains - sub_churn_domains).size,
        paying_lost_subscription: sub_churn_domains.size,
        subscription_churn_rate: pct(paying_lost, paying_at_start),
        revenue_churn_rate: pct(totals[:revenue_lost], revenue_base),
        baseline_complete: baseline_complete?,
        unsynced_uninstalls: unsynced_uninstalls,
        last_synced_at: ChurnedStore.maximum(:partner_synced_at)
      }
    end

    BLANK = { count: 0, revenue_lost: 0.0, ltv: 0.0, subscription: 0.0, usage: 0.0, returned: 0, recovered: 0.0 }.freeze

    def grouped(scope)
      scope.group(:churn_type).pluck(
        :churn_type,
        Arel.sql('COUNT(*)'),
        Arel.sql('COALESCE(SUM(last_30d_net), 0)'),
        Arel.sql('COALESCE(SUM(ltv_net), 0)'),
        Arel.sql('COALESCE(SUM(subscription_net), 0)'),
        Arel.sql('COALESCE(SUM(usage_net), 0)'),
        Arel.sql('COUNT(*) FILTER (WHERE returned)'),
        Arel.sql('COALESCE(SUM(net_since_return), 0)')
      ).to_h do |type, count, rev30, ltv, sub, usage, returned_count, recovered|
        [type, { count: count.to_i, revenue_lost: rev30.to_f, ltv: ltv.to_f, subscription: sub.to_f,
                 usage: usage.to_f, returned: returned_count.to_i, recovered: recovered.to_f }]
      end
    end

    # A store can churn twice in one period (cancels, then uninstalls days
    # later). Totals count each store once — its latest churn row — so revenue
    # lost and LTV aren't double counted. With lost_only, a store whose latest
    # churn was followed by a return is left out.
    def distinct_store_totals(period, lost_only:)
      latest = period.select('DISTINCT ON (churned_stores.shopify_domain) churned_stores.*')
                     .reorder('churned_stores.shopify_domain, churned_stores.churned_at DESC')
      scope = ChurnedStore.from(latest, :churned_stores)
      scope = scope.where(returned: false) if lost_only
      count, rev30, ltv, sub, usage, returned_count, recovered = scope.pick(
        Arel.sql('COUNT(*)'),
        Arel.sql('COALESCE(SUM(last_30d_net), 0)'),
        Arel.sql('COALESCE(SUM(ltv_net), 0)'),
        Arel.sql('COALESCE(SUM(subscription_net), 0)'),
        Arel.sql('COALESCE(SUM(usage_net), 0)'),
        Arel.sql('COUNT(*) FILTER (WHERE returned)'),
        Arel.sql('COALESCE(SUM(net_since_return), 0)')
      )
      { count: count.to_i, revenue_lost: rev30.to_f, ltv: ltv.to_f, subscription: sub.to_f,
        usage: usage.to_f, returned: returned_count.to_i, recovered: recovered.to_f }
    end

    # The org-wide sync (not the per-store mirror) must have covered the whole
    # 30-day window before `from`, or the denominator is short.
    def baseline_complete?
      covered = Churn::PartnerSalesSyncJob.covered_from
      covered.present? && covered <= from - BASELINE + 1.day
    end

    # Installed stores at `t` = installed now − installed since `t` + uninstalled since `t`.
    # (A reinstall recreates the shops row, so created_at is the latest install.)
    def active_stores_at(t)
      installed = Shop.real_installs
      # shops.source exists in some environments only (not production yet).
      installed = installed.where(source: 'shopify') if Shop.column_names.include?('source')
      now_active = installed.count
      installed_since = installed.where('created_at >= ?', t).count
      # Only stores that were already installed at `t` belong in the base; a
      # store that installed and uninstalled inside the period was never in it.
      uninstalled_since = UninstalledShop.where('created_at >= ?', t)
                                         .pluck(:shop_domain, :shopify_created_date)
                                         .select { |_, installed| installed_before?(installed, t) }
                                         .map(&:first).uniq.size
      [now_active - installed_since + uninstalled_since, 0].max
    end

    def installed_before?(value, t)
      installed = Time.zone.parse(value.to_s) if value.present?
      installed.nil? || installed < t
    rescue ArgumentError
      true
    end

    def unsynced_uninstalls
      UninstalledShop.where(created_at: from..to)
                     .where.not(shop_domain: [nil, ''])
                     .where.not(shop_domain: ChurnedStore.uninstalls.where(churned_at: (from - 1.day)..(to + 1.day)).select(:shopify_domain))
                     .distinct.count(:shop_domain)
    end

    def pct(num, den)
      return nil if den.to_f.zero?
      ((num.to_f / den.to_f) * 100).round(2)
    end
  end
end

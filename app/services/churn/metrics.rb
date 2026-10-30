module Churn
  # Read model for the dashboard. Every method degrades to safe defaults so the
  # page renders before the rollup/Partner-sync jobs have accumulated history.
  class Metrics
    def initialize(days: 30)
      @days = days.to_i
      @from = @days.days.ago
      @to = Time.current
    end

    def kpis
      installs = installs_in(@from, @to)
      uninstalls = uninstalls_in(@from, @to)
      reinstalls = reinstalls_in(@from, @to)
      active = active_shops_count
      start_active = [active + uninstalls - installs, 1].max

      {
        active_shops: active,
        new_installs: installs,
        uninstalls: uninstalls,
        reinstalls: reinstalls,
        logo_churn_rate: pct(uninstalls, start_active),
        net_logo_churn_rate: pct(uninstalls - reinstalls, start_active),
        mrr: mrr_now,
        mrr_prev: mrr_prior,
        net_revenue_churn_rate: net_revenue_churn_rate,
        arpu: arpu,
        at_risk_count: at_risk_summary.values_at('at_risk', 'critical').compact.sum
      }
    rescue => e
      Rails.logger.error("[Churn::Metrics] kpis failed: #{e.class}: #{e.message}")
      {}
    end

    def retention_cohorts(months: 6)
      rows = []
      months.times do |i|
        month_start = (Date.current.beginning_of_month - i.months)
        month_end = month_start.end_of_month
        cohort = ShopInstallation.where(installed_at: month_start.beginning_of_day..month_end.end_of_day)
        size = cohort.count
        next if size.zero?

        rows << {
          cohort: month_start.strftime('%Y-%m'),
          size: size,
          d7: survival(cohort, size, 7),
          d30: survival(cohort, size, 30),
          d60: survival(cohort, size, 60),
          d90: survival(cohort, size, 90)
        }
      end
      rows
    rescue => e
      Rails.logger.error("[Churn::Metrics] retention_cohorts failed: #{e.message}")
      []
    end

    def churn_reasons
      UninstalledShop.where(created_at: @from..@to)
                     .group(:uninstall_reason).count
                     .transform_keys { |k| k.presence || 'unknown' }
                     .sort_by { |_, v| -v }
    rescue => e
      Rails.logger.error("[Churn::Metrics] churn_reasons failed: #{e.message}")
      []
    end

    def feature_state_at_uninstall
      cols = %i[sms confirmation_sms_enabled cod_fee_enabled enable_pre_order_otp
                abandoned_cart_enabled prepaid_enabled partial_payment_enabled
                ac_whatsapp bsp_integrated]
      scope = UninstalledShop.where(created_at: @from..@to)
      total = scope.count
      return { total: 0, features: {} } if total.zero?

      features = cols.index_with { |c| scope.where(c => true).count }
      { total: total, features: features }
    rescue => e
      Rails.logger.error("[Churn::Metrics] feature_state_at_uninstall failed: #{e.message}")
      { total: 0, features: {} }
    end

    def mrr_waterfall
      start_mrr = mrr_prior
      end_mrr = mrr_now
      churned = BillingEvent.of_type('cancelled').in_period(@from, @to).sum(:amount).abs rescue 0
      contraction = BillingEvent.of_type('downgraded').in_period(@from, @to).sum(:amount).abs rescue 0
      new_mrr = BillingEvent.of_type('plan_activated').in_period(@from, @to).sum(:amount) rescue 0
      expansion = BillingEvent.of_type('upgraded').in_period(@from, @to).sum(:amount) rescue 0
      { start: start_mrr, new: new_mrr, expansion: expansion,
        contraction: -contraction, churned: -churned, end: end_mrr }
    end

    def at_risk_worklist(limit: 100)
      date = ChurnRiskSnapshot.maximum(:snapshot_date)
      return [] unless date

      ChurnRiskSnapshot.on_date(date).actionable.by_priority.limit(limit).map do |snap|
        shop = Shop.find_by(id: snap.shop_id)
        {
          shop_id: snap.shop_id,
          domain: snap.shopify_domain,
          owner: shop&.owner_name,
          email: shop&.owner_email,
          phone: shop&.owner_phone,
          band: snap.band,
          score: snap.score,
          mrr: snap.mrr,
          primary_factor: snap.primary_factor,
          reasons: Array(snap.reasons),
          recommended_action: snap.recommended_action
        }
      end
    rescue => e
      Rails.logger.error("[Churn::Metrics] at_risk_worklist failed: #{e.message}")
      []
    end

    def at_risk_summary
      date = ChurnRiskSnapshot.maximum(:snapshot_date)
      return {} unless date
      ChurnRiskSnapshot.on_date(date).group(:band).count
    rescue
      {}
    end

    def top_churn_this_period(limit: 10)
      UninstalledShop.where(created_at: @from..@to)
                     .order(Arel.sql('COALESCE(churn_risk_at_uninstall,0) DESC, COALESCE(order_count,0) DESC'))
                     .limit(limit)
    rescue
      UninstalledShop.none
    end

    private

    def active_shops_count
      Shop.count
    end

    def installs_in(from, to)
      ShopInstallation.where(installed_at: from..to).count
    rescue
      Shop.where(created_at: from..to).count
    end

    def uninstalls_in(from, to)
      c = ShopInstallation.where(uninstalled_at: from..to).count rescue 0
      c.positive? ? c : UninstalledShop.where(created_at: from..to).count
    end

    def reinstalls_in(from, to)
      ShopInstallation.where(installed_at: from..to)
                      .where('shop_domain_id IN (SELECT shop_domain_id FROM shop_installations WHERE uninstalled_at < ?)', to)
                      .count
    rescue
      0
    end

    def survival(cohort, size, age_days)
      churned = cohort.where('uninstalled_at IS NOT NULL AND uninstalled_at <= installed_at + (? * interval \'1 day\')', age_days).count
      pct(size - churned, size)
    rescue
      nil
    end

    def mrr_now
      d = MrrSnapshot.maximum(:snapshot_date)
      d ? MrrSnapshot.on_date(d).sum(:mrr).to_f.round(2) : 0.0
    rescue
      0.0
    end

    def mrr_prior
      target = (@days.days.ago).to_date
      d = MrrSnapshot.where('snapshot_date <= ?', target).maximum(:snapshot_date)
      d ? MrrSnapshot.on_date(d).sum(:mrr).to_f.round(2) : 0.0
    rescue
      0.0
    end

    def net_revenue_churn_rate
      start_mrr = mrr_prior
      return 0.0 if start_mrr.zero?
      churned = (mrr_waterfall[:churned].abs + mrr_waterfall[:contraction].abs)
      expansion = mrr_waterfall[:expansion] + mrr_waterfall[:new]
      pct(churned - expansion, start_mrr)
    rescue
      0.0
    end

    def arpu
      payers = MrrSnapshot.where(snapshot_date: MrrSnapshot.maximum(:snapshot_date)).paying.count
      return 0.0 if payers.zero?
      (mrr_now / payers).round(2)
    rescue
      0.0
    end

    def pct(num, den)
      return 0.0 if den.to_f.zero?
      ((num.to_f / den) * 100).round(2)
    end
  end
end

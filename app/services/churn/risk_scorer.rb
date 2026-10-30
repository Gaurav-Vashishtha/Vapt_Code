module Churn
  # Pure scoring function: takes a features hash for one shop and returns a
  # churn-risk assessment with a recommended action. Kept side-effect free so it
  # is trivially testable and cheap to run in bulk from RollupJob.
  module RiskScorer
    module_function

    BANDS = [
      [70, 'critical'],
      [45, 'at_risk'],
      [20, 'watch'],
      [0,  'healthy']
    ].freeze

    def score(features)
      f = features
      signals = []

      installed_days = f[:installed_days].to_i
      days_since_order = f[:days_since_order]

      if f[:first_order_at].nil? && installed_days >= 7
        signals << signal('never_activated', 35,
          "Installed #{installed_days}d ago but has never processed an order",
          'Onboarding rescue: walk them through go-live; the app has produced zero value so far.')
      end

      if days_since_order
        weight =
          if days_since_order >= 60 then 40
          elsif days_since_order >= 30 then 30
          elsif days_since_order >= 14 then 20
          else 0
          end
        if weight.positive?
          signals << signal('dormancy', weight,
            "No order processed in #{days_since_order} days",
            "Re-engage: confirm the integration still works and offer setup help — #{days_since_order}d of silence.")
        end
      end

      prev = f[:orders_prev_7d].to_i
      curr = f[:orders_7d].to_i
      if prev >= 3 && curr < (prev * 0.5)
        drop = (100 - (curr * 100.0 / prev)).round
        signals << signal('volume_decline', 20,
          "Order volume down #{drop}% week-over-week (#{prev} → #{curr})",
          "Investigate: a #{drop}% drop often signals a checkout/integration break or seasonality — reach out.")
      end

      if f[:onboarding_complete] == false && installed_days >= 3
        signals << signal('onboarding_incomplete', 15,
          'Onboarding never completed (no billing approval)',
          'Guide them through the remaining onboarding steps to reach first value.')
      end

      if f[:paying_recently] && !f[:currently_paying]
        signals << signal('billing_lapsed', 25,
          'Was paying recently but has no active charge now',
          'Billing lapsed: confirm plan/payment status before it becomes an uninstall.')
      end

      if f[:recent_feature_disable].present?
        signals << signal('feature_disabled', 10,
          "Recently turned off #{f[:recent_feature_disable]}",
          "Ask why they disabled #{f[:recent_feature_disable]} and offer an alternative or fix.")
      end

      total = [signals.sum { |s| s[:weight] }, 100].min
      primary = signals.max_by { |s| s[:weight] }

      {
        score: total,
        band: band_for(total),
        primary_factor: primary&.dig(:key),
        reasons: signals.map { |s| s[:reason] },
        recommended_action: primary&.dig(:action) || 'Healthy — no action needed.'
      }
    end

    def band_for(score)
      BANDS.find { |threshold, _| score >= threshold }.last
    end

    def signal(key, weight, reason, action)
      { key: key, weight: weight, reason: reason, action: action }
    end
  end
end

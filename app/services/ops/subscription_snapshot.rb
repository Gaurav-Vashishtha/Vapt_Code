# frozen_string_literal: true

module Ops
  # Persists the daily paid-subscription totals that PricingJobs::SubscriptionActiveJob
  # already computes (previously Slack-only), so the dashboard can chart them.
  module SubscriptionSnapshot
    def self.record!(stats, complete: true)
      date = ActiveSupport::TimeZone[Ops::GmvRollup::TZ].today
      breakdown = (stats[:overall_plan_counts] || {}).to_h.keys.index_with do |plan|
        { count: stats[:overall_plan_counts][plan].to_i, revenue: stats[:overall_plan_revenue][plan].to_f.round(2) }
      end

      snap = OpsDailySnapshot.find_or_initialize_by(stat_date: date)
      snap.update!(
        active_subscriptions: stats[:active_shops].to_i,
        mrr_usd: stats[:overall_total].to_f.round(2),
        shops_scanned: stats[:shop_count].to_i,
        plan_breakdown: breakdown,
        complete: complete
      )
    end
  end
end

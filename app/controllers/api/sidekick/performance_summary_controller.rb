# frozen_string_literal: true

module Api
  module Sidekick
    # Reuses the cached merchant dashboard payload (SummarySnapshot, 10 min TTL)
    # so this stays inside Sidekick's ~1s budget.
    class PerformanceSummaryController < BaseController
      ALLOWED_WINDOWS = [7, 30, 90].freeze

      def show
        days = ALLOWED_WINDOWS.min_by { |w| (w - window_days).abs }
        data = FastDashboardBuilder.call(shop: @shop, window_days: days)

        render json: {
          results: [
            resource_link(
              type: 'performance_summary',
              id: "#{@shop.id}-#{days}",
              name: "COD King performance — last #{days} days",
              meta: data.slice(:window_days, :revenue, :aov, :orders, :partial_payment, :cod_to_prepaid,
                               :funnel, :messages, :rto, :computed_at)
            )
          ]
        }
      end
    end
  end
end

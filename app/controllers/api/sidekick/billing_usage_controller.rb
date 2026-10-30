# frozen_string_literal: true

module Api
  module Sidekick
    class BillingUsageController < BaseController
      def show
        payload = cached('billing_usage') do
          usage = BillingUsageSummary.new(shop: @shop, days: window_days).as_json
          wallet = Wallet.find_by(shopify_domain: @shop.shopify_domain)
          plan = @shop.plan

          {
            plan: plan && { name: plan.name, price: plan.price, currency: plan.try(:currency).presence || @shop.currency }.compact,
            subscribed: @shop.charge_id.present?,
            timeframe: usage[:timeframe],
            totals: usage[:totals],
            # The wallet is free trial credit, only drawn down while there is no plan.
            free_credit_remaining: @shop.charge_id.blank? && wallet ? (wallet.total_balance.to_f - wallet.balance_used.to_f).round(2) : nil
          }.compact
        end

        render json: {
          results: [
            resource_link(
              type: 'billing_usage',
              id: @shop.id,
              name: "Billing & usage — #{@shop.shopify_domain}",
              meta: payload
            )
          ]
        }
      end
    end
  end
end

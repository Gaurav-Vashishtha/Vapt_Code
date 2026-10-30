# frozen_string_literal: true

module Api
  module Sidekick
    # Plan catalog + the store's current plan, and optionally whether one
    # feature is available on it ("can I remove branding on Free?").
    class PlansController < BaseController
      def show
        catalog = ::Sidekick::PlanCatalog
        tier = catalog.tier_for(@shop)
        india = @shop.country_code.to_s.upcase == 'IN'

        render json: {
          current_plan: {
            name: catalog.plan_for(tier)[:name],
            billing_plan_record: @shop.plan&.name,
            subscribed: @shop.charge_id.present?,
            partial_payment_fee: "#{(PartialTransactionFee.rate_for(@shop) * 100).round(2)}%"
          },
          feature: params[:feature].present? ? feature_answer(catalog, tier) : nil,
          plans: catalog::PLANS.map { |plan| plan_row(plan, india, tier) },
          features_by_plan: catalog::FEATURES.group_by { |_key, (_label, min)| min }
                                            .transform_keys { |min| catalog.plan_for(min)[:name] }
                                            .transform_values { |rows| rows.map { |_key, (label, *)| label } },
          results: [{ url: 'app://subscription' }]
        }.compact
      end

      private

      def plan_row(plan, india, current_tier)
        {
          name: plan[:name],
          price: price(plan, india),
          message_rates: plan[:message_rate_discount],
          partial_payment_fee: plan[:partial_payment_fee],
          includes: plan[:highlights],
          current: plan[:tier] == current_tier || nil
        }.compact
      end

      def price(plan, india)
        return 'Free' if plan[:usd].zero?

        usd = "$#{plan[:usd]} USD/month"
        india ? "₹#{plan[:inr].to_s.reverse.scan(/\d{1,3}/).join(',').reverse}/month (#{usd})" : usd
      end

      def feature_answer(catalog, tier)
        key, (label, min_tier, path, note) = catalog.find_feature(params[:feature])
        return { query: params[:feature], found: false, hint: 'Pass one of: ' + catalog::FEATURES.keys.join(', ') } unless key

        available = catalog.rank(tier) >= catalog.rank(min_tier)
        {
          feature: label,
          minimum_plan: catalog.plan_for(min_tier)[:name],
          available_on_current_plan: available,
          note: note,
          open: "app:/#{available ? path : '/subscription'}"
        }.compact
      end
    end
  end
end

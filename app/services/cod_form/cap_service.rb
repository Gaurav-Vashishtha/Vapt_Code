# frozen_string_literal: true

module CodForm
  # Monthly form-order cap (ARCHITECTURE.md J.2, CAP-1..9).
  class CapService
    STATE_TTL = 30.seconds

    class << self
      # => {"state"=>"ok"|"grace"|"flagged"|"fallback","cap"=>Integer|nil,"orders"=>Integer,
      #     "behaviour"=>String,"percent"=>Integer|nil,"period"=>"YYYY-MM","grace_orders"=>Integer,
      #     "overage_rate"=>Float|nil,"over_by"=>Integer}
      def state(shop, fresh: false)
        CodForm::Cache.store.delete(cache_key(shop.id)) if fresh
        CodForm::Cache.store.fetch(cache_key(shop.id), expires_in: STATE_TTL) { compute(shop) }
      end

      # "YYYY-MM" in the shop's time zone (UTC for an unknown zone).
      def period_for(shop, time = Time.current)
        zone = ScheduledShopReport.extract_iana_from_shop_timezone(shop.owner_timezone)
        time.in_time_zone(zone).strftime("%Y-%m")
      rescue StandardError
        time.utc.strftime("%Y-%m")
      end

      # Counts one order (CAP-1/2). Test sessions go to test_orders_count and never touch the cap.
      # Returns the new value of the incremented counter.
      def record_order!(shop, session, partial: false)
        period = period_for(shop, Time.current)
        if session.respond_to?(:is_test) && session.is_test
          return CodForm::OrderUsage.increment!(shop_id: shop.id, period: period, column: :test_orders_count)
        end

        before = state(shop, fresh: true)
        count = CodForm::OrderUsage.increment!(shop_id: shop.id, period: period, column: :orders_count)
        CodForm::OrderUsage.increment!(shop_id: shop.id, period: period, column: :partial_orders_count) if partial
        CodForm::Cache.store.delete(cache_key(shop.id))
        notify_if_crossed(shop, period, before, count)
        count
      end

      private

      def cache_key(shop_id)
        "codf:cap:#{shop_id}"
      end

      def compute(shop)
        period = period_for(shop, Time.current)
        resolved = resolve(shop)
        orders = CodForm::OrderUsage.for(shop.id, period).orders_count.to_i
        result = CodForm::Engine::CapResolver.state(resolved: resolved, orders_count: orders)
        {
          "state" => result["state"], "cap" => resolved["cap"], "orders" => orders,
          "behaviour" => resolved["behaviour"], "percent" => result["percent"], "period" => period,
          "grace_orders" => resolved["grace_orders"], "overage_rate" => resolved["overage_rate"]&.to_f,
          "over_by" => result["over_by"]
        }
      end

      def resolve(shop)
        global = CodForm::GlobalSetting.current
        tier = Sidekick::PlanCatalog.tier_for(shop)
        CodForm::Engine::CapResolver.resolve(
          limits: with_plan_cap(CodForm::PlanLimit.active.map(&:to_engine_hash), tier, plan_cap(shop)),
          shop_id: shop.id,
          tier: tier,
          country_group_ids: CodForm::CountryGroup.for_country(shop.country_code).pluck(:id),
          global: { "at_cap_behaviour" => global.at_cap_behaviour, "grace_orders" => global.grace_orders.to_i }
        )
      end

      # plans.cod_form_orders of the shop's plan (the Free plan for a shop without one).
      # nil = the plan sets no limit (or the column is not migrated yet).
      UNLIMITED_FROM = 100_000

      def plan_cap(shop)
        plan = shop.plan || Plan.find_by(name: "Free")
        value = plan.try(:cod_form_orders)
        value.nil? ? nil : [value.to_i, 0].max
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CapService] plan cap unavailable shop_id=#{shop.id} #{e.class}")
        nil
      end

      # The plan's own limit takes the place of the plan row of plan_limits (whose other
      # settings, such as the behaviour at the cap, are kept). A limit set for one shop or for a
      # country group in plan_limits still comes first (CapResolver's order).
      def with_plan_cap(limits, tier, cap)
        return limits if cap.nil?

        # A plan with UNLIMITED_FROM orders or more is unlimited: no cap, no notices, no meter.
        cap = nil if cap >= UNLIMITED_FROM

        tier = tier.to_s
        row = limits.find { |limit| limit["scope_type"].to_s == "plan" && limit["scope_key"].to_s == tier } || {}
        others = limits.reject { |limit| limit["scope_type"].to_s == "plan" && limit["scope_key"].to_s == tier }
        others + [row.merge("scope_type" => "plan", "scope_key" => tier, "monthly_cap" => cap, "active" => true)]
      end

      # A notice threshold (50 / 80 / 100 %) or a cap state change was crossed by this order:
      # tell the merchant and refresh `cap_fallback` in the storefront metafield.
      def notify_if_crossed(shop, period, before, count)
        cap = before["cap"]
        return unless cap.is_a?(Integer) && cap.positive?

        thresholds = Array(CodForm::GlobalSetting.current.usage_notice_thresholds).map(&:to_i)
        crossed = thresholds.any? do |percent|
          mark = (cap * percent / 100.0).ceil
          count >= mark && (count - 1) < mark
        end
        after = state(shop, fresh: true)
        state_changed = after["state"] != before["state"]
        return unless crossed || state_changed

        CodForm::CapNotifyJob.perform_async(shop.id, period) if crossed
        CodForm::MetafieldSyncJob.perform_async(shop.id) if state_changed
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CapService] notify failed shop_id=#{shop.id} #{e.class}")
      end
    end
  end
end

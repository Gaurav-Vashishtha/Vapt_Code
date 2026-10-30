# frozen_string_literal: true

module CodForm
  module Engine
    # Monthly order cap (ARCHITECTURE E.13 / J.2, CAP-1..9).
    class CapResolver
      BEHAVIOURS = %w[fallback grace flag_only].freeze

      class << self
        # limits = plan_limits rows (string keys). country_group_ids = the shop's groups, in position order.
        # global = {"at_cap_behaviour","grace_orders"}
        # => {"cap"=>Integer|nil,"behaviour","grace_orders","overage_rate","source"}
        def resolve(limits:, shop_id:, tier:, country_group_ids:, global:)
          rows = Array(limits).select { |row| row.is_a?(Hash) && row["active"] != false }
          tier = tier.to_s
          chain = []

          shop_row = rows.find { |row| row["scope_type"].to_s == "shop" && row["scope_key"].to_s == shop_id.to_s }
          chain << ["shop", shop_row] if shop_row

          Array(country_group_ids).each do |group_id|
            group_rows = rows.select { |row| row["scope_type"].to_s == "country_group" && row["scope_key"].to_s == group_id.to_s }
            specific = group_rows.find { |row| row["plan_tier"].to_s == tier && !tier.empty? }
            generic = group_rows.find { |row| row["plan_tier"].to_s.empty? }
            chain << ["country_group", specific] if specific
            chain << ["country_group", generic] if generic
          end

          plan_row = rows.find { |row| row["scope_type"].to_s == "plan" && row["scope_key"].to_s == tier }
          chain << ["plan", plan_row] if plan_row

          global = global.is_a?(Hash) ? global : {}
          source, first = chain.first
          behaviour = chain.map { |_, row| row["at_cap_behaviour"].to_s }.find { |value| BEHAVIOURS.include?(value) }
          behaviour ||= BEHAVIOURS.include?(global["at_cap_behaviour"].to_s) ? global["at_cap_behaviour"].to_s : "fallback"
          grace = chain.map { |_, row| row["grace_orders"] }.find { |value| value.is_a?(Integer) }
          grace ||= global["grace_orders"].is_a?(Integer) ? global["grace_orders"] : 0
          overage = chain.map { |_, row| row["overage_rate"] }.find { |value| !value.nil? && !value.to_s.strip.empty? }

          {
            "cap" => first && first["monthly_cap"].is_a?(Integer) ? [first["monthly_cap"], 0].max : nil,
            "behaviour" => behaviour,
            "grace_orders" => [grace, 0].max,
            "overage_rate" => overage,
            "source" => source || "none"
          }
        end

        # orders_count = form orders already counted in the period.
        # => {"state"=>"ok"|"grace"|"flagged"|"fallback","over_by"=>Integer,"percent"=>Integer|nil}
        def state(resolved:, orders_count:)
          resolved = resolved.is_a?(Hash) ? resolved : {}
          cap = resolved["cap"]
          orders = [orders_count.to_i, 0].max
          return { "state" => "ok", "over_by" => 0, "percent" => nil } unless cap.is_a?(Integer)

          percent = cap.zero? ? 100 : (orders * 100) / cap
          over_by = [orders - cap, 0].max
          state =
            if orders < cap then "ok"
            else
              case resolved["behaviour"].to_s
              when "flag_only" then "flagged"
              when "grace" then orders >= cap + resolved["grace_orders"].to_i ? "fallback" : "grace"
              else "fallback"
              end
            end
          { "state" => state, "over_by" => over_by, "percent" => percent }
        end
      end
    end
  end
end

# frozen_string_literal: true

module CodForm
  # Setup health items and checklist of the Setup screen (D.15 `GET /cod_form/setup`, DSH-6, DSH-11).
  #
  # `items` / `checklist` are pure (plain hashes in, plain hashes out) and are unit-tested without
  # Rails: ruby test/services/cod_form/setup_health_test.rb. `call` gathers the facts from the
  # database. The merchant-facing copy lives in the admin locale file
  # (`cod_form.setup.health_<code>`, ARCHITECTURE.md H.8); this class only emits codes.
  class SetupHealth
    CODES = %w[embed_off legacy_embed_on no_shipping_rate no_country cap_reached cap_flagged
               otp_unavailable rule_cod_fee_ignored zip_allow_list_no_exact].freeze

    SHIPPING_PATH = "/features/cod-form/shipping"
    SETUP_PATH = "/features/cod-form"
    COD_FEES_PATH = "/features/cod-fees"
    LIMIT_COD_PATH = "/features/limit-cod"
    OTP_PATH = "/features/otp/pre-order"
    PLANS_PATH = "/subscription"
    OTP_BYPASS_EVENT = "cf_otp_bypassed"

    class << self
      # facts (string keys):
      #   "mode"                    "legacy" | "cod_form"
      #   "embed"                   {"enabled", "legacy_enabled", "theme_editor_url", "legacy_theme_editor_url"}
      #   "express_active"          Setting#enable_pre_order_otp || Setting#partial_payment_enabled
      #   "shipping_rate_count"     active rates
      #   "countries"               general.countries
      #   "cap"                     {"state", "cap"} (CodForm::CapService.state)
      #   "otp_bypassed_24h"        cf_otp_bypassed events in the last 24 h
      #   "rule_cod_fee_ignored"    enabled COD-type partial rule with amount > 0 while cod_fee_enabled is false
      #   "allow_zip_patterns"      CodForm::Engine::PostalMatcher.parse(Setting#selected_zips)
      #   "cod_only_through_form"   general.cod_only_through_form
      # => [{"code", "severity", "count", "action_url"}], most severe first.
      def items(facts)
        list = []
        live = facts["mode"] == "cod_form"
        embed = facts["embed"].is_a?(Hash) ? facts["embed"] : {}

        if embed["enabled"] == false
          list << item("embed_off", live ? "critical" : "warning", nil, embed["theme_editor_url"])
        end
        if embed["legacy_enabled"] == true && facts["express_active"]
          # PM Q3: warn, never block.
          list << item("legacy_embed_on", "info", nil, embed["legacy_theme_editor_url"] || embed["theme_editor_url"])
        end
        if facts["shipping_rate_count"].to_i.zero?
          list << item("no_shipping_rate", live ? "critical" : "warning", nil, SHIPPING_PATH)
        end
        # `countries: []` means "every country" on the storefront (B.1.1), so this is a warning only.
        if Array(facts["countries"]).empty?
          list << item("no_country", "warning", nil, SETUP_PATH)
        end

        cap = facts["cap"].is_a?(Hash) ? facts["cap"] : {}
        case cap["state"]
        when "fallback" then list << item("cap_reached", "critical", cap["cap"], PLANS_PATH)
        when "grace" then list << item("cap_reached", "warning", cap["cap"], PLANS_PATH)
        when "flagged" then list << item("cap_flagged", "info", cap["cap"], PLANS_PATH)
        end

        bypassed = facts["otp_bypassed_24h"].to_i
        list << item("otp_unavailable", "warning", bypassed, OTP_PATH) if bypassed.positive?
        list << item("rule_cod_fee_ignored", "info", nil, COD_FEES_PATH) if facts["rule_cod_fee_ignored"]

        patterns = Array(facts["allow_zip_patterns"])
        if patterns.any? && patterns.none? { |pattern| pattern["type"] == "exact" } && !facts["cod_only_through_form"]
          list << item("zip_allow_list_no_exact", "critical", nil, LIMIT_COD_PATH)
        end

        rank = { "critical" => 0, "warning" => 1, "info" => 2 }
        list.each_with_index.sort_by { |entry, index| [rank[entry["severity"]], index] }.map(&:first)
      end

      # DSH-6. facts: "embed" (as above), "setup_state" (cod_form_shop_configs.setup_state),
      # "shipping_rate_count", "test_order_done".
      def checklist(facts)
        state = facts["setup_state"].is_a?(Hash) ? facts["setup_state"] : {}
        embed = facts["embed"].is_a?(Hash) ? facts["embed"] : {}
        [
          { "key" => "embed", "done" => embed["enabled"] == true },
          { "key" => "preset", "done" => present?(state["preset_chosen_at"]) },
          { "key" => "shipping_rate", "done" => facts["shipping_rate_count"].to_i.positive? || present?(state["shipping_rate_added_at"]) },
          { "key" => "test_order", "done" => present?(state["test_order_at"]) || facts["test_order_done"] == true }
        ]
      end

      # => {"health" => [...], "checklist" => [...]}
      def call(shop, config, embed:, cap: nil)
        facts = facts_for(shop, config, embed: embed, cap: cap)
        { "health" => items(facts), "checklist" => checklist(facts) }
      end

      def facts_for(shop, config, embed:, cap: nil)
        setting = shop.setting
        general = config.general.is_a?(Hash) ? config.general : {}
        {
          "mode" => config.storefront_mode,
          "embed" => embed,
          "express_active" => setting.present? && (setting.enable_pre_order_otp == true || setting.partial_payment_enabled == true),
          "shipping_rate_count" => CodForm::ShippingRate.where(shop_id: shop.id, active: true).count,
          "countries" => general["countries"],
          "cap" => cap || safe { CodForm::CapService.state(shop) } || {},
          "otp_bypassed_24h" => otp_bypassed_count(shop),
          "rule_cod_fee_ignored" => rule_cod_fee_ignored?(shop, setting),
          "allow_zip_patterns" => setting.present? ? (safe { CodForm::Engine::PostalMatcher.parse(setting.selected_zips.to_s) } || []) : [],
          "cod_only_through_form" => general["cod_only_through_form"] == true,
          "setup_state" => config.setup_state,
          "test_order_done" => test_order_done?(shop, config)
        }
      end

      private

      def item(code, severity, count, action_url)
        { "code" => code, "severity" => severity, "count" => count, "action_url" => action_url }
      end

      def present?(value)
        !(value.nil? || value.to_s.strip.empty?)
      end

      def safe
        yield
      rescue StandardError => e
        Rails.logger.warn("[CodForm::SetupHealth] #{e.class}")
        nil
      end

      # PM Q15: count of orders placed without OTP because the send failed, last 24 h.
      def otp_bypassed_count(shop)
        safe do
          FormFunnelEvent.where(shop_id: shop.id, event_type: OTP_BYPASS_EVENT)
                         .where("occurred_at >= ?", 24.hours.ago).count
        end.to_i
      end

      # PM Q6: the form uses only the COD fees setting; a COD-type rule's fee is ignored.
      def rule_cod_fee_ignored?(shop, setting)
        return false if setting.blank? || setting.cod_fee_enabled == true
        return false unless setting.partial_payment_enabled == true

        safe do
          shop.partial_rule_sets.where(is_enabled: true, amount_type: "cod").where("amount > 0").exists?
        end == true
      end

      def test_order_done?(shop, config)
        return true if present?(config.setup_state["test_order_at"])

        safe { CodForm::Session.where(shop_id: shop.id, is_test: true).where.not(order_id: nil).exists? } == true
      end
    end
  end
end

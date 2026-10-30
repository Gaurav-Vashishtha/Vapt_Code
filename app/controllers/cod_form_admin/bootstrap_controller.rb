# frozen_string_literal: true

module CodFormAdmin
  # GET /cod_form/bootstrap — everything the React module needs before it renders a screen
  # (H.3 `useCodFormBootstrap`). Exempt from `require_module!`: a shop without the module gets
  # `module_enabled: false` and the Settings group stays hidden (DSH-4).
  class BootstrapController < BaseController
    skip_before_action :require_module!

    # Same threshold as CapService's UNLIMITED_FROM and the UI's UNLIMITED_FORM_ORDERS.
    UNLIMITED_FORM_ORDERS = 100_000

    def show
      enabled = module_enabled?
      render json: {
        "module_enabled" => enabled,
        "mode" => @config.storefront_mode,
        "legacy_mode_label" => legacy_mode_label,
        # DSH-9: the Summary opt-in card was closed by the merchant (POST setup/dismiss_optin).
        "optin_dismissed" => @config.setup_state.is_a?(Hash) && @config.setup_state["dismissed_optin_at"].present?,
        "tier" => Sidekick::PlanCatalog.tier_for(@shop),
        "gates" => gates,
        "usage" => enabled ? usage_summary : nil,
        "currency" => @shop.currency,
        "money_format" => @shop.money_format,
        "shop_country" => @shop.country_code.to_s.upcase.presence,
        "locales" => locales,
        # The form asks for an OTP only while pre-order OTP is on (OTP verification screen).
        "otp_enabled" => CodForm::OtpService.on?(@shop.setting, @config.general),
        # Plans page: COD Form orders per month of each plan that sets a limit ({"Pro" => 500}).
        "plan_form_orders" => enabled ? plan_form_orders : {},
        "preview" => {
          "asset_base" => @config.asset_base.presence || ENV["COD_FORM_ASSET_BASE"].presence,
          "frame_url" => "/cod_form/preview_frame"
        }
      }
    end

    private

    def plan_form_orders
      return {} unless Plan.column_names.include?("cod_form_orders")

      orders = Plan.where.not(cod_form_orders: nil).pluck(:name, :cod_form_orders).to_h
      # A shop or country-group limit (e.g. Launch markets) overrides every plan's own limit
      # (CapResolver order), so show that instead of the plan numbers.
      override = form_orders_override
      return orders if override == :none

      shown = override.nil? ? UNLIMITED_FORM_ORDERS : override
      orders.transform_values { shown }
    rescue StandardError
      {}
    end

    # :none when only plan limits apply to this shop, else the shop / country-group monthly cap
    # (nil = unlimited) that takes precedence over the plan's.
    def form_orders_override
      limits = CodForm::PlanLimit.active.map(&:to_engine_hash).reject { |limit| limit["scope_type"].to_s == "plan" }
      return :none if limits.empty?

      global = CodForm::GlobalSetting.current
      resolved = CodForm::Engine::CapResolver.resolve(
        limits: limits,
        shop_id: @shop.id,
        tier: Sidekick::PlanCatalog.tier_for(@shop),
        country_group_ids: CodForm::CountryGroup.for_country(@shop.country_code).pluck(:id),
        global: { "at_cap_behaviour" => global.at_cap_behaviour, "grace_orders" => global.grace_orders.to_i }
      )
      resolved["source"].to_s.in?(%w[shop country_group]) ? resolved["cap"] : :none
    end

    # What "legacy" means for this shop (B.1): Express when the Express checkout is in use.
    def legacy_mode_label
      setting = @shop.setting
      express = setting.present? && (setting.enable_pre_order_otp == true || setting.partial_payment_enabled == true)
      express ? "express" : "checkout"
    end

    # The shop's primary locale first, the form language chosen in Setup, English always
    # available, then every language the merchant added in a form's Texts tab — so button labels,
    # offer titles and thank-you messages can be translated (and saved) in those languages too.
    def locales
      primary = @shop.primary_locale.to_s.split("-").first.to_s.downcase
      ([primary.presence, setup_language, "en"].compact + form_locales).uniq.first(CodForm::Engine::FormConfig::MAX_LOCALES + 1)
    end

    def setup_language
      general = @config.respond_to?(:general) && @config.general.is_a?(Hash) ? @config.general : {}
      CodForm::Engine::FormConfig.language(general["language"]).presence
    rescue StandardError
      nil
    end

    def form_locales
      CodForm::Form.where(shop_id: @shop.id).active.pluck(:draft_config).flat_map do |config|
        texts = config.is_a?(Hash) ? config["texts"] : nil
        texts.is_a?(Hash) ? texts.keys.map(&:to_s) : []
      end.select { |code| code.match?(Validators::LOCALE_RE) }
    rescue StandardError
      []
    end
  end
end

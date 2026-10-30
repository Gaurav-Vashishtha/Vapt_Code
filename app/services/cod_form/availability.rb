# frozen_string_literal: true

module CodForm
  # Is the COD Form module usable for this shop right now? (ARCHITECTURE.md F.1, A.3, NFR-12)
  #
  #   CodForm::Availability.call(shop) # => {available: true|false, fallback: nil|"kill_switch"|"module_disabled"}
  #
  # Extra key `mode_off: true` marks the one case a staff preview may pass: everything is on
  # except storefront_mode (the merchant is testing before going live, C.1.2 `test_only`).
  class Availability
    class << self
      def call(shop, config: nil)
        return unavailable("kill_switch") if CodForm::GlobalSetting.current.kill_switch

        config ||= CodForm::ShopConfig.for(shop)
        return unavailable("module_disabled") unless config.module_enabled?
        return unavailable("module_disabled") unless CodForm::Gates.allowed?(shop, "cod_form_core", config: config)
        return unavailable("module_disabled").merge(mode_off: true) unless config.cod_form_mode?

        { available: true, fallback: nil }
      end

      # May this request proceed? `test` = a valid preview token / a test session.
      def usable?(availability, test: false)
        availability[:available] || (availability[:mode_off] == true && test)
      end

      private

      def unavailable(code)
        { available: false, fallback: code }
      end
    end
  end
end

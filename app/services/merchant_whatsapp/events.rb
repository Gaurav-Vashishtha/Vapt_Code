# frozen_string_literal: true

module MerchantWhatsapp
  module Events
    module_function

    KEYS = %w[
      installed activation_pending_charge activation_done upgrade_done
      first_order_otp first_partial_order first_notification_sent
      first_cart_recovered first_cod_to_prepaid uninstalled
    ].freeze

    def fire(event_key, shop_id: nil, uninstalled_shop_id: nil)
      return unless Config.enabled?

      DispatchEventJob.perform_async(event_key.to_s, shop_id, uninstalled_shop_id)
    rescue => e
      Rails.logger.warn("[MerchantWhatsapp::Events] fire failed #{event_key}: #{e.class}: #{e.message}")
    end
  end
end

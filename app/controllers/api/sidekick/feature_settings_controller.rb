# frozen_string_literal: true

module Api
  module Sidekick
    class FeatureSettingsController < BaseController
      def show
        render json: {
          results: [
            resource_link(
              type: 'feature_settings',
              id: @shop.id,
              name: "COD King feature settings — #{@shop.shopify_domain}",
              meta: feature_flags(@shop.setting)
            )
          ]
        }
      end

      private

      # Only flags a merchant can change in the app. `whatsapp_enabled` is left
      # out on purpose: it is an internal OTP-fallback switch (default true)
      # that merchants cannot see, so reporting it read as "WhatsApp is on".
      def feature_flags(setting)
        return {} unless setting

        {
          cod_form_enabled: setting.cod_form_enabled,
          pre_order_otp_enabled: setting.enable_pre_order_otp,
          post_order_sms_otp_enabled: setting.sms,
          otp_wait_time_seconds: setting.otp_wait_time,
          otp_max_retries: setting.max_retries,
          cancel_unverified_notification_enabled: setting.cancel_notif_enabled,
          whatsapp_auto_verify: setting.auto_verify,
          partial_payment_enabled: setting.partial_payment_enabled,
          cod_fee_enabled: setting.cod_fee_enabled,
          cod_to_prepaid_enabled: setting.prepaid_enabled,
          confirmation_sms_enabled: setting.confirmation_sms_enabled,
          confirmation_whatsapp_enabled: setting.confirmation_whatsapp,
          fulfilment_whatsapp_enabled: setting.fulfilment_whatsapp,
          abandoned_cart_enabled: setting.abandoned_cart_enabled,
          abandoned_cart_whatsapp_enabled: setting.ac_whatsapp,
          first_purchase_whatsapp_enabled: setting.first_purchase_whatsapp_enabled
        }
      end
    end
  end
end

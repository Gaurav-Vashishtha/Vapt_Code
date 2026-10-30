# frozen_string_literal: true

module CodForm
  module Integrations
    # Lookups shared by the integration clients and jobs: is a provider connected for the shop,
    # is its gate open, and bookkeeping of last success / last error on cod_form_integrations.
    module Registry
      GATES = { "google_sheets" => "google_sheets", "klaviyo" => "klaviyo_omnisend", "omnisend" => "klaviyo_omnisend" }.freeze

      module_function

      # The connected CodForm::Integration row, or nil (not connected, or gate closed).
      # A row in "error" still counts as connected-with-a-problem: the next success clears it.
      def active(shop, provider)
        provider = provider.to_s
        gate = GATES[provider]
        return nil if gate && !gate?(shop, gate)

        row = CodForm::Integration.find_by(shop_id: shop.id, provider: provider)
        return nil if row.nil? || row.status == CodForm::Integration::STATUS_DISCONNECTED
        return nil unless row.credentials.is_a?(Hash) && row.credentials.values.any?(&:present?)

        row
      end

      def gate?(shop, key)
        CodForm::Gates.allowed?(shop, key)
      rescue StandardError => e
        Rails.logger.warn("[codf/integrations] gate check failed shop=#{shop&.id} key=#{key} #{e.class}")
        false
      end

      # config.events.<key> — on unless switched off (B.18).
      def event_enabled?(integration, key)
        config = integration.config.is_a?(Hash) ? integration.config : {}
        events = config["events"].is_a?(Hash) ? config["events"] : {}
        events[key.to_s] != false
      end

      def success!(integration)
        return if integration.last_success_at && integration.last_success_at > 5.minutes.ago &&
                  integration.status == CodForm::Integration::STATUS_CONNECTED

        integration.update_columns(status: CodForm::Integration::STATUS_CONNECTED, last_error: nil,
                                   last_success_at: Time.current, updated_at: Time.current)
      rescue StandardError
        nil
      end

      # message: short, shown to the merchant. Never pass response bodies, keys or buyer data.
      def error!(integration, message)
        integration.update_columns(status: CodForm::Integration::STATUS_ERROR,
                                   last_error: message.to_s[0, CodForm::Integration::LAST_ERROR_MAX],
                                   updated_at: Time.current)
      rescue StandardError
        nil
      end
    end
  end
end

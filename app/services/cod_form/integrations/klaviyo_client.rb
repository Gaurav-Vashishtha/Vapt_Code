# frozen_string_literal: true

module CodForm
  module Integrations
    # Klaviyo Events API (ARCHITECTURE.md I.4, INT-2, ABN-4).
    #   POST https://a.klaviyo.com/api/events/
    #   Authorization: Klaviyo-API-Key <private key>, revision header, JSON:API body.
    #
    #   KlaviyoClient.track(shop, event: "COD Form Order Placed", profile: {...}, properties: {...})
    #     -> {"ok", "status", "retryable", "skipped", "error"}
    # Never raises. Never logs the key, the profile or the properties.
    class KlaviyoClient
      URL = "https://a.klaviyo.com/api/events/"
      PROVIDER = "klaviyo"
      DEFAULT_REVISION = "2026-07-15"
      EVENT_KEYS = { EventPayloads::EVENT_ORDER => "order", EventPayloads::EVENT_ABANDONED => "abandoned" }.freeze

      def self.track(shop, event:, profile:, properties:, time: nil, value_cents: nil, currency: nil, unique_id: nil)
        integration = Registry.active(shop, PROVIDER)
        return CodForm::Tracking::Http.skipped("not_connected") if integration.nil?

        key = EVENT_KEYS[event.to_s]
        return CodForm::Tracking::Http.skipped("event_disabled") if key && !Registry.event_enabled?(integration, key)

        api_key = integration.credentials["private_api_key"].to_s
        return CodForm::Tracking::Http.skipped("not_connected") if api_key.empty?

        body = EventPayloads.klaviyo(event: event, profile: profile, properties: properties, time: time,
                                     value_cents: value_cents, currency: currency, unique_id: unique_id)
        return CodForm::Tracking::Http.skipped("no_identifier") if body.nil?

        response = CodForm::Tracking::Http.post_json(
          URL, body,
          headers: {
            "Authorization" => "Klaviyo-API-Key #{api_key}",
            "revision" => ENV.fetch("KLAVIYO_API_REVISION", nil).presence || DEFAULT_REVISION,
            "Accept" => "application/vnd.api+json",
            "Content-Type" => "application/vnd.api+json"
          }
        )
        outcome = CodForm::Tracking::Http.outcome(response)
        outcome["response"] = {}
        if outcome["ok"]
          Registry.success!(integration)
        elsif [401, 403].include?(response.status)
          Registry.error!(integration, "Klaviyo rejected the API key (HTTP #{response.status}). Reconnect Klaviyo.")
        elsif !outcome["retryable"]
          Registry.error!(integration, "Klaviyo rejected an event (HTTP #{response.status}).")
        end
        outcome
      rescue StandardError => e
        CodForm::Tracking::Http.failed(e.class.name)
      end
    end
  end
end

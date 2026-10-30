# frozen_string_literal: true

module CodForm
  module Integrations
    # Omnisend Events API (ARCHITECTURE.md I.4, INT-2, ABN-4).
    #   POST https://api.omnisend.com/v5/events   header X-API-KEY
    #
    #   OmnisendClient.track(shop, event: "COD Form Abandoned", profile: {...}, properties: {...})
    # Never raises. Never logs the key, the contact or the properties.
    class OmnisendClient
      URL = "https://api.omnisend.com/v5/events"
      PROVIDER = "omnisend"
      EVENT_KEYS = { EventPayloads::EVENT_ORDER => "order", EventPayloads::EVENT_ABANDONED => "abandoned" }.freeze

      def self.track(shop, event:, profile:, properties:, time: nil, event_id: nil)
        integration = Registry.active(shop, PROVIDER)
        return CodForm::Tracking::Http.skipped("not_connected") if integration.nil?

        key = EVENT_KEYS[event.to_s]
        return CodForm::Tracking::Http.skipped("event_disabled") if key && !Registry.event_enabled?(integration, key)

        api_key = integration.credentials["api_key"].to_s
        return CodForm::Tracking::Http.skipped("not_connected") if api_key.empty?

        body = EventPayloads.omnisend(event: event, profile: profile, properties: properties, time: time, event_id: event_id)
        return CodForm::Tracking::Http.skipped("no_identifier") if body.nil?

        response = CodForm::Tracking::Http.post_json(URL, body, headers: { "X-API-KEY" => api_key })
        outcome = CodForm::Tracking::Http.outcome(response)
        outcome["response"] = {}
        if outcome["ok"]
          Registry.success!(integration)
        elsif [401, 403].include?(response.status)
          Registry.error!(integration, "Omnisend rejected the API key (HTTP #{response.status}). Reconnect Omnisend.")
        elsif !outcome["retryable"]
          Registry.error!(integration, "Omnisend rejected an event (HTTP #{response.status}).")
        end
        outcome
      rescue StandardError => e
        CodForm::Tracking::Http.failed(e.class.name)
      end
    end
  end
end

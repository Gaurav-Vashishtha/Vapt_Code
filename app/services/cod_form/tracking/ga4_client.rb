# frozen_string_literal: true

module CodForm
  module Tracking
    # GA4 Measurement Protocol (ARCHITECTURE.md I.3).
    #   POST https://www.google-analytics.com/mp/collect?measurement_id=<G-…>&api_secret=<secret>
    # pixel_id = measurement id, access_token = API secret. No PII is sent.
    # The URL carries the secret and is never logged.
    class Ga4Client
      COLLECT_URL = "https://www.google-analytics.com/mp/collect"
      DEBUG_URL = "https://www.google-analytics.com/debug/mp/collect"

      # validate: true posts to the debug endpoint, which returns validation messages and
      # records nothing (used by the pixel test button).
      def self.send_event(pixel:, event:, validate: false)
        secret = pixel["access_token"].to_s
        return Http.skipped("no_access_token") if secret.empty?

        body = Payloads.ga4(pixel: pixel, event: event)
        return Http.skipped("event_disabled") if body.nil?

        url = "#{validate ? DEBUG_URL : COLLECT_URL}" \
              "?measurement_id=#{URI.encode_www_form_component(pixel['pixel_id'])}" \
              "&api_secret=#{URI.encode_www_form_component(secret)}"
        outcome = Http.outcome(Http.post_json(url, body))
        raw = outcome["response"].is_a?(Hash) ? outcome["response"] : {}
        messages = Array(raw["validationMessages"]).first(5).map do |m|
          m.is_a?(Hash) ? m["description"].to_s[0, 200] : m.to_s[0, 200]
        end
        outcome["response"] = validate ? { "validation_messages" => messages } : {}
        outcome
      end
    end
  end
end

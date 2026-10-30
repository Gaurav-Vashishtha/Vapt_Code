# frozen_string_literal: true

module CodForm
  module Tracking
    # Snapchat Conversions API v3 (ARCHITECTURE.md I.3, TRK-8).
    #   POST https://tr.snapchat.com/v3/<pixel_id>/events?access_token=…
    # The token is a query parameter by Snap's design; the URL is never logged.
    class SnapchatClient
      BASE = "https://tr.snapchat.com/v3"

      # validate: true posts to /events/validate (nothing is recorded; pixel test button).
      def self.send_event(pixel:, event:, validate: false)
        token = pixel["access_token"].to_s
        return Http.skipped("no_access_token") if token.empty?

        body = Payloads.snapchat(pixel: pixel, event: event)
        return Http.skipped("event_disabled") if body.nil?

        url = "#{BASE}/#{URI.encode_www_form_component(pixel['pixel_id'])}/events#{validate ? '/validate' : ''}" \
              "?access_token=#{URI.encode_www_form_component(token)}"
        outcome = Http.outcome(Http.post_json(url, body))
        raw = outcome["response"].is_a?(Hash) ? outcome["response"] : {}
        outcome["response"] = { "status" => raw["status"], "reason" => raw["reason"].to_s[0, 200] }
                              .reject { |_, v| v.nil? || v == "" }
        outcome
      end
    end
  end
end

# frozen_string_literal: true

module CodForm
  module Tracking
    # Meta Conversions API (ARCHITECTURE.md I.3).
    #   POST https://graph.facebook.com/v19.0/<pixel_id>/events
    # The token travels in the query string as the Graph API expects; the URL is never logged.
    class MetaClient
      API_VERSION = "v19.0"

      # pixel: server pixel hash (PixelResolver.server_pixels). event: EventBuilder.build.
      def self.send_event(pixel:, event:)
        token = pixel["access_token"].to_s
        return Http.skipped("no_access_token") if token.empty?

        body = Payloads.meta(pixel: pixel, event: event)
        return Http.skipped("event_disabled") if body.nil?

        url = "https://graph.facebook.com/#{API_VERSION}/#{URI.encode_www_form_component(pixel['pixel_id'])}/events" \
              "?access_token=#{URI.encode_www_form_component(token)}"
        slim(Http.outcome(Http.post_json(url, body)))
      end

      # Keep only what is safe and useful from Meta's answer.
      def self.slim(outcome)
        raw = outcome["response"].is_a?(Hash) ? outcome["response"] : {}
        error = raw["error"].is_a?(Hash) ? raw["error"] : {}
        outcome["response"] = {
          "events_received" => raw["events_received"],
          "error_code" => error["code"],
          "error_message" => error["message"].to_s[0, 200]
        }.reject { |_, v| v.nil? || v == "" }
        outcome
      end
    end
  end
end

# frozen_string_literal: true

module CodForm
  module Tracking
    # Pinterest Conversions API (ARCHITECTURE.md I.3, TRK-8).
    #   POST https://api.pinterest.com/v5/ad_accounts/<ad_account_id>/events   Authorization: Bearer
    # config.ad_account_id is required (C.6); pixel_id is the tag id (browser only).
    class PinterestClient
      BASE = "https://api.pinterest.com/v5/ad_accounts"

      # validate: true adds ?test=true (the event is checked, not recorded; pixel test button).
      def self.send_event(pixel:, event:, validate: false)
        token = pixel["access_token"].to_s
        return Http.skipped("no_access_token") if token.empty?

        account = (pixel["config"] || {})["ad_account_id"].to_s.strip
        return Http.skipped("no_ad_account_id") if account.empty?

        body = Payloads.pinterest(pixel: pixel, event: event)
        return Http.skipped("event_disabled") if body.nil?

        url = "#{BASE}/#{URI.encode_www_form_component(account)}/events#{validate ? '?test=true' : ''}"
        outcome = Http.outcome(Http.post_json(url, body, headers: { "Authorization" => "Bearer #{token}" }))
        raw = outcome["response"].is_a?(Hash) ? outcome["response"] : {}
        outcome["response"] = {
          "num_events_received" => raw["num_events_received"],
          "num_events_processed" => raw["num_events_processed"],
          "message" => raw["message"].to_s[0, 200]
        }.reject { |_, v| v.nil? || v == "" }
        outcome
      end
    end
  end
end

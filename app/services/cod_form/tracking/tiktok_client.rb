# frozen_string_literal: true

module CodForm
  module Tracking
    # TikTok Events API (ARCHITECTURE.md I.3).
    #   POST https://business-api.tiktok.com/open_api/v1.3/event/track/   header Access-Token
    class TiktokClient
      URL = "https://business-api.tiktok.com/open_api/v1.3/event/track/"

      def self.send_event(pixel:, event:)
        token = pixel["access_token"].to_s
        return Http.skipped("no_access_token") if token.empty?

        body = Payloads.tiktok(pixel: pixel, event: event)
        return Http.skipped("event_disabled") if body.nil?

        outcome = Http.outcome(Http.post_json(URL, body, headers: { "Access-Token" => token }))
        raw = outcome["response"].is_a?(Hash) ? outcome["response"] : {}
        # TikTok answers HTTP 200 with a non-zero "code" for rejected events.
        code = raw["code"]
        if outcome["ok"] && !code.nil? && code.to_i != 0
          outcome["ok"] = false
          outcome["error"] = "tiktok code #{code.to_i}"
          # 40100 = rate limit, 5xxxx = TikTok-side error
          outcome["retryable"] = code.to_i == 40_100 || code.to_i >= 50_000
        end
        outcome["response"] = { "code" => code, "message" => raw["message"].to_s[0, 200] }
        outcome
      end
    end
  end
end

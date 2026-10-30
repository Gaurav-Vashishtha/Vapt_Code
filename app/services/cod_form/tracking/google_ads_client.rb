# frozen_string_literal: true

module CodForm
  module Tracking
    # Google Ads conversion (TRK-7, ARCHITECTURE.md I.3).
    #
    # Server side there is exactly one Google Ads conversion: the shop's existing
    # Setting#google_conversion_id / google_conversion_token, uploaded by the existing
    # NetworkServices::GoogleConversionService. `tracking_pixels` rows of platform google_ads
    # ("AW-…" + conversion label) are browser-only: the upload API needs an OAuth token and a
    # conversion action resource name, which those rows do not hold.
    #
    # call_purchase accepts `gclid:` only. Do not pass gbraid / wbraid / gad_* — that is the
    # ArgumentError waiting in the unused caller in cod_order_create_service.rb.
    class GoogleAdsClient
      FormOrder = Struct.new(:id, :total_price, :currency, keyword_init: true)

      # session: CodForm::Session (ordered). setting: the shop's Setting. event: EventBuilder.build.
      def self.send_purchase(session:, setting:, event:)
        return Http.skipped("not_configured") if setting.nil?
        return Http.skipped("not_configured") if setting.google_conversion_id.to_s.strip.empty? ||
                                                 setting.google_conversion_token.to_s.strip.empty?

        gclid = (event["user"] || {})["gclid"].to_s.strip
        return Http.skipped("no_gclid") if gclid.empty?

        order = FormOrder.new(
          id: session.order_id.to_s,
          total_price: format("%.2f", event["value_cents"].to_i / 100.0),
          currency: event["currency"]
        )
        result = NetworkServices::GoogleConversionService.call_purchase(order, setting, gclid: gclid)
        result = {} unless result.is_a?(Hash)
        return Http.failed(result["error"].to_s[0, 120]) if result["error"]

        partial = result["partialFailureError"].is_a?(Hash) ? result["partialFailureError"] : nil
        return Http.failed("partial failure #{partial['code']}") if partial

        { "ok" => true, "status" => 200, "retryable" => false, "skipped" => nil, "error" => nil, "response" => {} }
      end

      # tracking_pixels rows of platform google_ads have no server call.
      def self.send_event(pixel:, event:)
        Http.skipped("browser_only")
      end
    end
  end
end

# frozen_string_literal: true

module CodForm
  # Thin wrapper around Rto::DecisionService (F18). Never raises: nil means "no decision".
  # Callers invoke it only when RTO gating or risk-based OTP is on and gated in, and only
  # once phone and zip are known.
  class RiskService
    class << self
      # => {"band"=>"low"|"medium"|"high","score"=>Integer,"checked_at"=>ISO8601} or nil
      def call(shop:, phone:, email:, zip:, country:, total_cents:)
        return nil if phone.to_s.strip.empty? || zip.to_s.strip.empty?

        decision = Rto::DecisionService.call(
          shopify_domain: shop.shopify_domain,
          phone: phone,
          email: email.to_s.strip.presence,
          zip: zip.to_s.strip,
          country: country.to_s.upcase.presence,
          cart: { total: total_cents.to_i / 100.0 }
        )
        return nil unless decision.is_a?(Hash)

        band = (decision[:band] || decision["band"]).to_s
        return nil unless %w[low medium high].include?(band)

        {
          "band" => band,
          "score" => (decision[:risk_score] || decision["risk_score"]).to_i,
          "checked_at" => Time.current.utc.iso8601
        }
      rescue StandardError => e
        Rails.logger.warn("[CodForm::RiskService] shop_id=#{shop.id} #{e.class}")
        nil
      end
    end
  end
end

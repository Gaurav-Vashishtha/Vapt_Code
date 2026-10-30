# frozen_string_literal: true

module CodForm
  module Engine
    # When the OTP step is required (ARCHITECTURE E.13, OTP-1, OTP-6, OTP-7).
    class OtpPolicy
      BAND_RANK = { "low" => 0, "medium" => 1, "high" => 2 }.freeze
      DEFAULT_TARGET_BAND = "medium"

      class << self
        # risk_band = the buyer's RTO band (nil when unknown); target_band = general.otp.risk_band.
        def required?(shop_enabled:, mode:, risk_band: nil, target_band: nil, verified: false)
          return false unless shop_enabled == true
          return false if verified == true

          case mode.to_s
          when "order_first" then false
          when "risk_based"
            target = BAND_RANK[target_band.to_s.downcase] || BAND_RANK[DEFAULT_TARGET_BAND]
            rank = BAND_RANK[risk_band.to_s.downcase]
            !rank.nil? && rank >= target
          else true # "before_order" (default)
          end
        end
      end
    end
  end
end

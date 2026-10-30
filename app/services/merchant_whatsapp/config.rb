# frozen_string_literal: true

module MerchantWhatsapp
  module Config
    module_function

    def enabled?
      ENV["MERCHANT_WA_ENABLED"].to_s.strip.downcase.in?(%w[1 true yes on])
    end

    def dry_run?
      return true unless enabled?

      ENV["MERCHANT_WA_DRY_RUN"].to_s.strip.downcase.in?(%w[1 true yes on])
    end

    def live?
      enabled? && !dry_run?
    end

    def min_gap_hours
      value = ENV.fetch("MERCHANT_WA_MIN_GAP_HOURS", 24).to_i
      value.positive? ? value : 24
    end

    # Send-window restriction is disabled for now — set
    # MERCHANT_WA_QUIET_HOURS_ENABLED=true to re-enable it.
    def quiet_hours_enabled?
      ENV["MERCHANT_WA_QUIET_HOURS_ENABLED"].to_s.strip.downcase.in?(%w[1 true yes on])
    end

    def quiet_hours_start
      ENV.fetch("MERCHANT_WA_QUIET_START", 9).to_i
    end

    def quiet_hours_end
      ENV.fetch("MERCHANT_WA_QUIET_END", 20).to_i
    end

    def test_domains
      ENV["MERCHANT_WA_TEST_DOMAINS"].to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def restricted_to_test_domains?
      test_domains.any?
    end
  end
end

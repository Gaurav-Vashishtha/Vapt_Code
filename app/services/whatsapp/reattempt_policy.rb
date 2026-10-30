# frozen_string_literal: true

module Whatsapp
  # Env-driven retry schedule, one per flow:
  #
  #   MSG91_WHATSAPP_RETRY_DELAYS_HOURS=1,3,12,24
  #   MSG91_WHATSAPP_RETRY_ERROR_CODES=131049
  #   BSP_WHATSAPP_RETRY_DELAYS_HOURS=1,3,12,24
  #   BSP_WHATSAPP_RETRY_ERROR_CODES=131049
  #
  # Delays are hours measured from the FIRST failure (1,3,12,24 → the last try
  # is 24h after the message first failed). Unset or empty delays turn retries
  # off for that flow. After the last delay the message is dropped.
  class ReattemptPolicy
    DEFAULT_ERROR_CODES = %w[131049].freeze
    MAX_DELAY_HOURS = 168

    def self.for(flow)
      new(flow.to_s)
    end

    attr_reader :flow

    def initialize(flow)
      raise ArgumentError, "unknown flow #{flow}" unless WhatsappReattempt::FLOWS.include?(flow)

      @flow = flow
    end

    def delays_hours
      @delays_hours ||= ENV[env_key('DELAYS_HOURS')].to_s.split(',')
                                                     .map { |v| Float(v.strip, exception: false) }
                                                     .compact
                                                     .select { |h| h.positive? && h <= MAX_DELAY_HOURS }
                                                     .sort
    end

    def error_codes
      @error_codes ||= begin
        raw = ENV[env_key('ERROR_CODES')].to_s.split(',').map(&:strip).reject(&:empty?)
        raw.presence || DEFAULT_ERROR_CODES
      end
    end

    def enabled?
      delays_hours.any?
    end

    # "131049", 131049 and "131049: This message was not delivered…" all match.
    def retryable?(code)
      enabled? && error_codes.include?(self.class.normalize_code(code))
    end

    def max_attempts
      delays_hours.length
    end

    # When the next resend is due, given how many resends were already made.
    # nil once every delay is used up (→ drop).
    def next_retry_at(first_failed_at, attempts_made)
      hours = delays_hours[attempts_made.to_i]
      return nil unless hours

      first_failed_at + (hours * 3600).round
    end

    def self.normalize_code(code)
      code.to_s[/\d+/].to_s
    end

    private

    def env_key(suffix)
      "#{flow.upcase}_WHATSAPP_RETRY_#{suffix}"
    end
  end
end

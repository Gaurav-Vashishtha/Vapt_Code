module Whatsapp
  # Campaign-level retry-on-failure. Only Meta's frequency/throughput throttles
  # are retryable — those failures are about WHEN the message was sent, so a
  # later attempt can succeed:
  #   131049 per-user marketing limit ("healthy ecosystem")
  #   131048 spam rate limit on the sender
  #   130429 cloud API throughput limit
  #   131056 recipient-pair rate limit
  # Everything else (no WhatsApp on the number 131026, template/parameter
  # errors, registration problems) fails the same way every time and is final.
  module CampaignRetryPolicy
    RETRYABLE_CODES = %w[131049 131048 130429 131056].freeze
    MAX_STEPS = 5
    MAX_DELAY_HOURS = 168
    DEFAULT_DELAYS_HOURS = [6, 12].freeze

    module_function

    def enabled?(campaign)
      config(campaign)['enabled'] == true && delays(campaign).any?
    end

    def delays(campaign)
      raw = config(campaign)['delays_hours']
      raw = DEFAULT_DELAYS_HOURS if raw.blank?
      Array(raw).map(&:to_f).select { |h| h.positive? && h <= MAX_DELAY_HOURS }.first(MAX_STEPS)
    end

    def max_attempts(campaign)
      1 + delays(campaign).length
    end

    def retryable_code?(code)
      RETRYABLE_CODES.include?(code.to_s[/\d+/].to_s)
    end

    # Returns true when the recipient was parked for a later attempt instead of
    # being finalized as failed. attempt_count already includes the attempt
    # that just failed, so delays[attempt-1] is that failure's backoff step.
    def schedule_retry!(recipient, campaign, error_code:, error_message: nil, at: Time.current)
      return false unless campaign && enabled?(campaign)
      return false unless retryable_code?(error_code)

      attempt = [recipient.attempt_count.to_i, 1].max
      delay_hours = delays(campaign)[attempt - 1]
      return false unless delay_hours

      recipient.update_columns(
        status: 'retry_pending',
        next_retry_at: at + delay_hours.hours,
        error_code: error_code.to_s.presence,
        error_message: error_message.to_s.presence&.truncate(1000),
        updated_at: Time.current
      )
      true
    end

    def sanitize_config(raw)
      h = (raw || {}).to_h.stringify_keys
      delays = Array(h['delays_hours']).map(&:to_f).select { |v| v.positive? && v <= MAX_DELAY_HOURS }.first(MAX_STEPS)
      { 'enabled' => ActiveModel::Type::Boolean.new.cast(h['enabled']) == true, 'delays_hours' => delays }
    end

    def config(campaign)
      campaign.retry_config.is_a?(Hash) ? campaign.retry_config : {}
    end
  end
end

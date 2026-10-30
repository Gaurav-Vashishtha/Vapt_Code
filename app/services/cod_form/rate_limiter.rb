# frozen_string_literal: true

# Fixed-window counters on CodForm::Cache.store (Redis in production) for the limits
# that Rack::Attack cannot key (they need the parsed body): per phone OTP
# sends and per phone order submits (ARCHITECTURE.md D.0.4).
#
# Key building and window maths are pure Ruby and tested standalone.
module CodForm
  class RateLimiter
    PREFIX = "codf"

    # name => [limit, period seconds]
    DEFAULTS = {
      "otp_phone"      => [5, 600],
      "order_phone"    => [5, 600],
      "otp_verify"     => [10, 600],
      "discount_code"  => [20, 600]
    }.freeze

    class << self
      # Counts one hit. Returns true while the caller is within the limit,
      # false once the limit is exceeded. Fails open when the cache is down.
      def hit!(key, limit:, period:, now: nil, store: nil)
        store ||= default_store
        return true if store.nil? || key.to_s.empty? || limit.to_i <= 0

        count = store.increment(window_key(key, period, now), 1, expires_in: period.to_i + 5)
        return true if count.nil?

        count.to_i <= limit.to_i
      rescue StandardError
        true
      end

      # Seconds until the current window of `period` ends.
      def retry_after(period, now: nil)
        period = period.to_i
        return 0 if period <= 0

        period - (epoch(now) % period)
      end

      # "codf:otp:<shop_id>:<phone>" / "codf:order:<shop_id>:<phone>" (D.0.4).
      def otp_key(shop_id, phone_digits)
        subject_key("otp", shop_id, phone_digits)
      end

      def order_key(shop_id, phone_digits)
        subject_key("order", shop_id, phone_digits)
      end

      def subject_key(kind, shop_id, subject)
        subject = normalize_subject(subject)
        return nil if subject.empty? || shop_id.to_s.empty?

        [PREFIX, kind.to_s, shop_id.to_s, subject].join(":")
      end

      # Keeps keys short and free of separators / whitespace.
      def normalize_subject(subject)
        subject.to_s.downcase.gsub(/[^a-z0-9@._\-]/, "")[0, 120].to_s
      end

      def window_key(key, period, now = nil)
        period = [period.to_i, 1].max
        "#{key}:#{epoch(now) / period}"
      end

      def default_limit(name)
        DEFAULTS.fetch(name.to_s)
      end

      private

      def epoch(now)
        (now || Time.now).to_i
      end

      def default_store
        defined?(Rails) && Rails.respond_to?(:cache) ? CodForm::Cache.store : nil
      end
    end
  end
end

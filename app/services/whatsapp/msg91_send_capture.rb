# frozen_string_literal: true

module Whatsapp
  # MSG91 send logs don't keep what was sent, and twilio_logs.sid has no index.
  # So each retry-eligible MSG91 marketing send is remembered in Redis for a
  # short while, keyed by the id MSG91 returned. When MSG91's delivery webhook
  # reports a retryable failure for that id, the request is copied into a
  # WhatsappReattempt row and resent from there.
  #
  # Only COD King's own MSG91 account is covered: shops with their own MSG91
  # key (setting.whatsapp_operator_config) are skipped.
  module Msg91SendCapture
    KEY_PREFIX = 'wa:msg91:capture:'
    DEFAULT_TTL_HOURS = 48

    module_function

    # source: the TwilioLog / AbandonedCart row the send was logged on.
    def remember(shop:, source:, provider_id:, url:, body:)
      return unless provider_id.present? && source&.id
      return unless ReattemptPolicy.for('msg91').enabled?
      return if shop&.setting&.whatsapp_operator_config.present?

      value = {
        'source_type' => source.class.name,
        'source_id' => source.id,
        'shop_id' => shop&.id,
        'url' => url,
        'body' => body.is_a?(String) ? JSON.parse(body) : body.as_json
      }.to_json
      Sidekiq.redis { |r| r.set(key(provider_id), value, ex: ttl_seconds) }
    rescue StandardError => e
      Rails.logger.warn("[msg91_capture] could not remember #{provider_id}: #{e.class}: #{e.message}")
    end

    # First capture found for any of the ids a webhook event carries.
    def fetch(provider_ids)
      ids = Array(provider_ids).map(&:to_s).reject(&:empty?).uniq
      return nil if ids.empty?

      values = Sidekiq.redis { |r| r.mget(*ids.map { |id| key(id) }) }
      ids.zip(values).each do |id, raw|
        next if raw.blank?

        return JSON.parse(raw).merge('provider_id' => id)
      end
      nil
    rescue StandardError => e
      Rails.logger.warn("[msg91_capture] fetch failed: #{e.class}: #{e.message}")
      nil
    end

    def key(id)
      "#{KEY_PREFIX}#{id}"
    end

    def ttl_seconds
      hours = ENV.fetch("MSG91_WHATSAPP_RETRY_CAPTURE_TTL_HOURS", nil).to_f
      ((hours.positive? ? hours : DEFAULT_TTL_HOURS) * 3600).round
    end
  end
end

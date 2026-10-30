# frozen_string_literal: true

module Whatsapp
  module ClickTracker
    PURPOSE = 'whatsapp_link_click'
    EXPIRES_IN = 120.days

    module_function

    def wrap(url, shop_id:, event_type_key:, source_external_id: nil, stage_index: 0, recipient: nil)
      return url if url.blank? || disabled?

      data = {
        's' => shop_id, 'e' => event_type_key.to_s, 'x' => source_external_id.to_s.presence,
        'g' => stage_index.to_i, 'r' => recipient.to_s.gsub(/\D/, '').last(10).presence, 'u' => url.to_s
      }.compact
      "https://#{host}/wa/r/#{encryptor.encrypt_and_sign(data, expires_in: EXPIRES_IN, purpose: PURPOSE)}"
    rescue StandardError => e
      Rails.logger.warn("[whatsapp/click_tracker] wrap failed: #{e.class}: #{e.message}")
      url
    end

    def read(token)
      data = encryptor.decrypt_and_verify(token.to_s, purpose: PURPOSE)
      data.is_a?(Hash) && data['u'].to_s.match?(%r{\Ahttps?://}i) ? data : nil
    rescue StandardError
      nil
    end

    def record!(data)
      WhatsappLinkClick.create!(
        shop_id: data['s'], event_type_key: data['e'], source_external_id: data['x'],
        stage_index: data['g'].to_i, recipient_last10: data['r'],
        destination_host: (URI.parse(data['u']).host rescue nil), clicked_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[whatsapp/click_tracker] record failed: #{e.class}: #{e.message}")
      nil
    end

    def disabled?
      ENV['WHATSAPP_CLICK_TRACKING_DISABLED'].present? || ENV['APP_HOST'].blank?
    end

    def host
      ENV['APP_HOST']
    end

    def encryptor
      @encryptor ||= ActiveSupport::MessageEncryptor.new(
        Rails.application.key_generator.generate_key(PURPOSE, 32),
        cipher: 'aes-256-gcm', serializer: JSON, url_safe: true
      )
    end
  end
end

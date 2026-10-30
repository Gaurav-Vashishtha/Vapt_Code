# frozen_string_literal: true

module CustomBranded
  # Fires a SAMPLE webhook at the configured partner URL, exactly like a real
  # delivery: Meta-native payload shape, X-CB-Shop-Domain + X-CB-Signature
  # headers, and a CustomBrandedWebhookDelivery row (fields prefixed "test:").
  # The only extra is the X-CB-Test: true header and wamid.TEST… ids, so the
  # consumer can tell it apart. Synchronous (5s timeout) — the caller gets the
  # partner endpoint's actual response back.
  class WebhookTester < ApplicationService
    class Error < StandardError; end

    EVENTS = %w[delivery_status inbound_reply template_review].freeze
    HTTP_TIMEOUT = 5

    def initialize(client:, event:)
      @client = client
      @event = event.to_s
    end

    def call
      raise Error, "unknown event #{@event.inspect} — use one of: #{EVENTS.join(', ')}" unless EVENTS.include?(@event)

      url = ENV['CB_WEBHOOK_FORWARD_URL'].to_s
      raise Error, 'CB_WEBHOOK_FORWARD_URL is not configured' if url.blank?

      payload = build_payload
      body = payload.to_json

      headers = {
        'Content-Type' => 'application/json',
        'X-CB-Shop-Domain' => client.domain,
        'X-CB-Test' => 'true'
      }
      secret = ENV['CB_WEBHOOK_FORWARD_SECRET'].to_s
      headers['X-CB-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}" if secret.present?

      delivery = record_delivery(payload)

      begin
        response = HTTParty.post(url, body: body, headers: headers, timeout: HTTP_TIMEOUT)
        delivery&.update_columns(response_code: response.code, delivered_at: Time.current)
        {
          delivered: response.success?,
          response_code: response.code,
          response_body: response.body.to_s.truncate(500),
          forward_url: url,
          signed: secret.present?,
          payload: payload
        }
      rescue StandardError => e
        delivery&.update_columns(error: e.message.to_s.truncate(250))
        {
          delivered: false,
          response_code: nil,
          error: e.message,
          forward_url: url,
          signed: secret.present?,
          payload: payload
        }
      end
    end

    private

    attr_reader :client, :event

    def account
      @account ||= client.default_whatsapp_account
    end

    def waba_id
      account&.waba_id.presence || 'TEST_WABA_ID'
    end

    def phone_number_id
      account&.phone_number_id.presence || 'TEST_PHONE_NUMBER_ID'
    end

    def display_phone
      account&.display_phone_number.to_s.gsub(/\D/, '').presence || '919876543210'
    end

    def test_id
      "wamid.TEST#{SecureRandom.hex(8)}"
    end

    def build_payload
      value =
        case event
        when 'delivery_status'
          {
            'messaging_product' => 'whatsapp',
            'metadata' => { 'display_phone_number' => display_phone, 'phone_number_id' => phone_number_id },
            'statuses' => [{
              'id' => test_id, 'status' => 'delivered',
              'timestamp' => Time.current.to_i.to_s, 'recipient_id' => '919876543210'
            }]
          }
        when 'inbound_reply'
          {
            'messaging_product' => 'whatsapp',
            'metadata' => { 'display_phone_number' => display_phone, 'phone_number_id' => phone_number_id },
            'messages' => [{
              'id' => test_id, 'from' => '919876543210', 'type' => 'button',
              'timestamp' => Time.current.to_i.to_s,
              'button' => { 'payload' => 'Need help', 'text' => 'Need help' },
              'context' => { 'id' => test_id }
            }]
          }
        when 'template_review'
          {
            'event' => 'APPROVED',
            'message_template_name' => client.whatsapp_templates.first&.name || 'order_shipped',
            'message_template_language' => 'en',
            'reason' => nil
          }
        end

      field = event == 'template_review' ? 'message_template_status_update' : 'messages'
      {
        'object' => 'whatsapp_business_account',
        'entry' => [{ 'id' => waba_id, 'changes' => [{ 'field' => field, 'value' => value }] }]
      }
    end

    def record_delivery(payload)
      CustomBrandedWebhookDelivery.create!(
        custom_branded_client_id: client.id,
        fields: "test:#{event}",
        payload: payload
      )
    rescue StandardError => e
      Rails.logger.warn("[cb_webhook_test] could not record delivery: #{e.message}")
      nil
    end
  end
end

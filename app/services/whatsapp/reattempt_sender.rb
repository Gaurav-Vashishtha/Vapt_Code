# frozen_string_literal: true

require 'httparty'

module Whatsapp
  # Resends one message for a WhatsappReattempt, on the original row.
  # Returns Result(ok, provider_message_id, error_code, error_message).
  module ReattemptSender
    Result = Struct.new(:ok, :provider_message_id, :error_code, :error_message, keyword_init: true)

    module_function

    def call(reattempt)
      reattempt.bsp? ? send_bsp(reattempt) : send_msg91(reattempt)
    end

    # Same request MSG91 accepted the first time, on COD King's account key.
    def send_msg91(reattempt)
      url = reattempt.request['url'].presence
      body = reattempt.request['body']
      return Result.new(ok: false, error_code: 'no_request', error_message: 'original request not captured') if url.blank? || body.blank?

      response = HTTParty.post(
        url,
        headers: { 'Content-Type' => 'application/json', 'authkey' => ENV.fetch("MSG91_AUTHKEY", nil).to_s },
        body: body.to_json,
        timeout: 20
      )
      resp = response.parsed_response.is_a?(Hash) ? response.parsed_response : (JSON.parse(response.body) rescue {})
      provider_id = resp.dig('data', 'message_uuid').presence || resp['request_id'].presence

      if resp['status'] == 'success' && provider_id
        Msg91SendCapture.remember(
          shop: reattempt.shop, source: reattempt.source, provider_id: provider_id, url: url, body: body
        )
        Result.new(ok: true, provider_message_id: provider_id)
      else
        Result.new(ok: false, error_code: "http_#{response.code}", error_message: resp.presence&.to_json || response.body.to_s)
      end
    rescue StandardError => e
      Result.new(ok: false, error_code: e.class.name, error_message: e.message)
    end

    # Replays the stored template send onto the same WhatsappMessageLog row.
    def send_bsp(reattempt)
      log = ResendMessageLogService.call(log: reattempt.source, in_place: true)
      Result.new(ok: true, provider_message_id: log.meta_message_id)
    rescue ResendMessageLogService::Error => e
      log = reattempt.source&.reload
      Result.new(ok: false, error_code: log&.error_code.presence || 'resend_error', error_message: e.message)
    rescue StandardError => e
      Result.new(ok: false, error_code: e.class.name, error_message: e.message)
    end
  end
end

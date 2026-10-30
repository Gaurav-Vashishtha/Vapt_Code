# frozen_string_literal: true

module Whatsapp
  # Handles MSG91 WhatsApp delivery-report events (see Msg91WebhookController).
  #
  #   failed with a retryable code (MSG91_WHATSAPP_RETRY_ERROR_CODES, e.g.
  #     "131049: This message was not delivered to maintain healthy ecosystem
  #     engagement.") → start / continue the retry schedule.
  #   delivered / read for a message we resent → mark the retry delivered.
  #
  # Messages are matched by the ids MSG91 returned at send time, through the
  # short-lived Redis capture (Msg91SendCapture) — never by scanning twilio_logs.
  class Msg91DeliveryReportJob < ApplicationJob
    sidekiq_options queue: 'default', retry: 3

    def perform(events_json)
      Array(JSON.parse(events_json)).each { |event| handle(event) }
    end

    private

    def handle(event)
      return if event['direction'].present? && event['direction'].to_s != '1' # inbound

      # MSG91 leaves unknown template fields as literal "{{field}}" — never treat those as ids.
      ids = [event['requestId'], event['uuid'], event['crqid'], event['oneApiRequestId']]
            .map(&:to_s).reject { |v| v.empty? || v.start_with?('{{') }
      return if ids.empty?

      case event['eventName'].to_s.downcase
      when 'failed'
        code = ReattemptPolicy.normalize_code(event['reason'])
        return unless ReattemptPolicy.for('msg91').retryable?(code)

        capture = Msg91SendCapture.fetch(ids)
        return Rails.logger.info("[msg91_dlr] #{code} for uncaptured message #{ids.inspect}") unless capture

        ReattemptRecorder.record_msg91_failure(capture: capture, error_code: code, error_message: event['reason'])
      when 'delivered', 'read'
        reattempt = WhatsappReattempt.where(flow: 'msg91', status: 'sent', provider_message_id: ids).first
        ReattemptRecorder.record_delivered(reattempt)
      end
    rescue StandardError => e
      Rails.logger.error("[msg91_dlr] event failed #{event.inspect}: #{e.class}: #{e.message}")
    end
  end
end

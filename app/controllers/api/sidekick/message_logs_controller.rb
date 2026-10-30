# frozen_string_literal: true

module Api
  module Sidekick
    # Individual SMS / WhatsApp sends, mainly to answer "why didn't my customer
    # get the message?". Covers both the shared COD King number (TwilioLog)
    # and the merchant's own WhatsApp number (WhatsappMessageLog).
    class MessageLogsController < BaseController
      FAILED_TWILIO = %w[failed undelivered].freeze

      def search
        phone = params[:phone].to_s.gsub(/\D/, '').last(10).presence
        since = window_days(default: 7, max: 30).days.ago
        only_failed = ActiveModel::Type::Boolean.new.cast(params[:failed_only])

        logs = (twilio_logs(phone, since, only_failed) + branded_logs(phone, since, only_failed))
               .sort_by { |log| log[:_meta][:sent_at].to_s }
               .reverse
               .first(result_limit)

        render json: { results: logs }
      end

      private

      def twilio_logs(phone, since, only_failed)
        return [] if params[:channel].to_s == 'branded_whatsapp'

        scope = TwilioLog.where(shop_id: @shop.id, created_at: since..).order(created_at: :desc)
        scope = scope.where('customer_number LIKE ?', "%#{phone}") if phone
        scope = scope.where("status IN (?) OR status LIKE '{%'", FAILED_TWILIO) if only_failed
        scope = scope.where('ver_type ILIKE ?', "%#{params[:channel]}%") if %w[sms whatsapp].include?(params[:channel].to_s)

        scope.limit(result_limit).map do |log|
          status, error = twilio_status(log.status)
          resource_link(
            type: 'message_log',
            id: "twilio-#{log.id}",
            name: "#{log.ver_type} to #{log.customer_number} — #{status || 'unknown'}",
            meta: {
              sender: 'COD King number',
              message_type: log.ver_type,
              phone: log.customer_number,
              status: status,
              error: error,
              sent_at: log.created_at&.iso8601
            }
          )
        end
      end

      def branded_logs(phone, since, only_failed)
        return [] if %w[sms whatsapp].include?(params[:channel].to_s)

        scope = @shop.whatsapp_message_logs.where(created_at: since..).order(created_at: :desc)
        scope = scope.where('recipient LIKE ?', "%#{phone}") if phone
        scope = scope.failed if only_failed

        scope.limit(result_limit).map do |log|
          resource_link(
            type: 'message_log',
            id: "branded-#{log.id}",
            name: "Business Brand WhatsApp #{log.event_type_key} — #{log.status}",
            meta: {
              sender: 'Merchant WhatsApp number',
              message_type: log.event_type_key,
              phone: log.recipient,
              status: log.status,
              error: [log.error_code, log.error_message].compact_blank.join(': ').presence,
              sent_at: log.created_at&.iso8601
            }
          )
        end
      end
    end
  end
end

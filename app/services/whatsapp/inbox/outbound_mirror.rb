# frozen_string_literal: true

module Whatsapp
  module Inbox
    class OutboundMirror < ApplicationService
      LOG_LAST10_SQL = "right(regexp_replace(recipient, '\\D', '', 'g'), 10)"
      LOG_STATUS_MAP = {
        'queued' => 'queued', 'sent' => 'sent', 'delivered' => 'delivered', 'read' => 'read',
        'failed' => 'failed', 'retry_pending' => 'queued', 'dropped' => 'failed'
      }.freeze

      def self.render_body(template, body_parameters)
        text = template ? Whatsapp::TemplateComponents.text_of(template.components, 'BODY') : ''
        values = parameter_strings(body_parameters)
        text.gsub(Whatsapp::TemplateComponents::PLACEHOLDER) { values[Regexp.last_match(1).to_i - 1].to_s }
      end

      def self.parameter_strings(body_parameters)
        Array(body_parameters).map do |p|
          next p.to_s unless p.is_a?(Hash)

          p = p.stringify_keys
          (p['text'] || p.dig('currency', 'fallback_value') || p.dig('date_time', 'fallback_value')).to_s
        end
      end

      def initialize(log, conversation: nil)
        @log = log
        @conversation = conversation
      end

      def call
        return nil if InboundRecorder.disabled? || !mirrorable?

        conversation = @conversation || find_conversation
        return nil if conversation.nil? || conversation.shop_id != log.shop_id

        message = upsert(conversation)
        WhatsappConversation.touch_last_message!(
          conversation.id, at: message.occurred_at, direction: 'outbound',
                           preview: message.body.presence || "Template: #{log.template_name}"
        )
        message
      end

      private

      attr_reader :log

      def mirrorable?
        log.shop_id.present? && log.whatsapp_account_id.present? && log.meta_message_id.present? &&
          !log.event_type_key.to_s.start_with?('inbox_')
      end

      def find_conversation
        last10 = WhatsappConversation.phone_last10(log.recipient)
        return nil if last10.length < 10

        WhatsappConversation.where(whatsapp_account_id: log.whatsapp_account_id, phone_last10: last10)
                            .order(last_inbound_at: :desc).first
      end

      def upsert(conversation)
        attempts = 0
        begin
          message = WhatsappConversationMessage.find_or_initialize_by(whatsapp_message_log_id: log.id)
          message.assign_attributes(attributes_for(conversation, message))
          message.save!
          message
        rescue ActiveRecord::RecordNotUnique
          attempts += 1
          raise if attempts > 1

          retry
        end
      end

      def attributes_for(conversation, message)
        snapshot = log.payload_snapshot.is_a?(Hash) ? log.payload_snapshot : {}
        params = Array(snapshot['body_parameters'])
        status = LOG_STATUS_MAP.fetch(log.status.to_s, 'sent')
        attrs = {
          whatsapp_conversation_id: conversation.id,
          shop_id: conversation.shop_id,
          direction: :outbound,
          source: source,
          kind: 'template',
          body: self.class.render_body(log.whatsapp_template, params).presence,
          content: {
            'template_name' => log.template_name,
            'language' => log.whatsapp_template&.language,
            'event_type_key' => log.event_type_key,
            'campaign_id' => log.whatsapp_campaign_id,
            'body_parameters' => self.class.parameter_strings(params)
          },
          meta_message_id: log.meta_message_id,
          occurred_at: log.sent_at || log.created_at || Time.current,
          sent_at: log.sent_at,
          delivered_at: log.delivered_at,
          read_at: log.read_at,
          failed_at: log.failed_at,
          error_code: status == 'failed' ? log.error_code : nil,
          error_message: status == 'failed' ? log.error_message : nil
        }
        attrs[:status] = status if message.new_record? || message.meta_message_id != log.meta_message_id ||
                                   WhatsappConversationMessage::STATUS_ORDER[status] > WhatsappConversationMessage::STATUS_ORDER[message.status.to_s].to_i
        attrs
      end

      def source
        return 'campaign' if log.whatsapp_campaign_id.present?
        return 'payment_link' if log.event_type_key.to_s == 'cod_to_prepaid'

        'notification'
      end
    end
  end
end

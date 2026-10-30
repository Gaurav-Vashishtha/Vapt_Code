# frozen_string_literal: true

module Whatsapp
  module Inbox
    # Template sends are real billed template messages: they go through
    # Meta::SendTemplateMessageService and get a whatsapp_message_logs row.
    class TemplateSender < ApplicationService
      class Invalid < FreeformSender::Invalid; end
      class SendFailed < FreeformSender::SendFailed; end

      EVENT_KEY = 'inbox_template'
      MARKETING_EVENT_KEY = 'inbox_template_marketing'

      def self.customer_opted_out?(conversation)
        keys = [conversation.customer_wa_id.to_s.gsub(/\D/, ''), conversation.phone_last10.to_s].reject(&:blank?).uniq
        keys.any? && WhatsappOptOut.where(shop_id: conversation.shop_id, phone_normalized: keys).exists?
      end

      def initialize(conversation:, agent:, template:, body_parameters: [], header_parameters: nil, resolve: false)
        @conversation = conversation
        @agent = agent
        @template = template
        @body_parameters = Array(body_parameters)
        @header_parameters = header_parameters
        @resolve = resolve ? true : false
      end

      def call
        account = conversation.whatsapp_account
        raise FreeformSender::NotReady, 'WhatsApp number is not ready to send' unless account&.ready_to_send?

        validate!(account)
        meta_params = body_parameters.map do |p|
          p.is_a?(Hash) ? p.stringify_keys : { 'type' => 'text', 'text' => p.to_s }
        end
        row = create_row(meta_params)
        log = send_template(account, row, meta_params)
        link!(row, log)
        now = Time.current
        WhatsappConversation.touch_last_message!(
          conversation.id, at: row.occurred_at, direction: 'outbound',
                           preview: row.body.presence || "Template: #{template.name}"
        )
        ConversationState.on_agent_reply!(conversation, agent: agent, at: now, resolve: resolve)
        row
      end

      private

      attr_reader :conversation, :agent, :template, :body_parameters, :header_parameters, :resolve

      def event_type_key
        template.marketing? ? MARKETING_EVENT_KEY : EVENT_KEY
      end

      def validate!(account)
        raise Invalid, 'Template not found' if template.nil?
        raise Invalid, 'Template is not approved' unless template.approved?
        raise Invalid, 'Template belongs to another WhatsApp number' unless template.whatsapp_account_id == account.id
        if template.marketing? && self.class.customer_opted_out?(conversation)
          raise Invalid, 'This customer unsubscribed from marketing messages. Pick a non-marketing template.'
        end

        body_text = Whatsapp::TemplateComponents.text_of(template.components, 'BODY')
        needed = Whatsapp::TemplateComponents.placeholders(body_text).uniq.size
        values = OutboundMirror.parameter_strings(body_parameters)
        raise Invalid, "Fill in all #{needed} template variables" if values.size < needed || values.first(needed).any?(&:blank?)

        header = Whatsapp::TemplateComponents.find(template.components, 'HEADER')
        if header && header['format'].to_s == 'TEXT' && header_parameters.blank? &&
           Whatsapp::TemplateComponents.placeholders(header['text']).any?
          raise Invalid, 'Templates with a variable in the header cannot be sent from the inbox'
        end
      end

      def create_row(meta_params)
        WhatsappConversationMessage.create!(
          whatsapp_conversation_id: conversation.id,
          shop_id: conversation.shop_id,
          direction: :outbound,
          source: 'agent',
          kind: 'template',
          body: OutboundMirror.render_body(template, meta_params).presence,
          content: {
            'template_name' => template.name,
            'language' => template.language,
            'event_type_key' => event_type_key,
            'campaign_id' => nil,
            'body_parameters' => OutboundMirror.parameter_strings(meta_params)
          },
          agent_id: agent&.id,
          status: :queued,
          media_state: :none,
          occurred_at: Time.current
        )
      end

      def send_template(account, row, meta_params)
        header = header_parameters.presence || [template.media_header_param(nil, conversation.shop)].compact
        log = Meta::SendTemplateMessageService.call(
          account: account,
          template: template,
          recipient: conversation.customer_wa_id,
          body_parameters: meta_params,
          header_parameters: header.presence,
          event_type_key: event_type_key,
          source_external_id: "inbox:#{row.id}",
          payload_snapshot: { 'inbox_conversation_id' => conversation.id }
        )
        if log.nil?
          row.update!(status: :failed, failed_at: Time.current, error_message: 'Duplicate send was skipped')
          raise SendFailed.new('Duplicate send was skipped', nil)
        end
        log
      rescue Meta::SendTemplateMessageService::Error => e
        failed_log = WhatsappMessageLog.where(shop_id: conversation.shop_id, event_type_key: event_type_key,
                                              source_external_id: "inbox:#{row.id}").order(:id).last
        code = failed_log&.error_code.to_s
        row.update!(status: :failed, failed_at: Time.current, error_code: code.presence,
                    error_message: e.message.to_s.truncate(1000), whatsapp_message_log_id: failed_log&.id)
        raise SendFailed.new(e.message, code.match?(/\A\d+\z/) ? code.to_i : nil)
      end

      def link!(row, log)
        log.reload
        status = OutboundMirror::LOG_STATUS_MAP.fetch(log.status.to_s, 'sent')
        row.update!(
          whatsapp_message_log_id: log.id,
          meta_message_id: log.meta_message_id,
          status: status,
          sent_at: log.sent_at || Time.current,
          delivered_at: log.delivered_at,
          read_at: log.read_at
        )
      end
    end
  end
end

# frozen_string_literal: true

module Whatsapp
  module Inbox
    module AutoLabeler
      CANCEL_PATTERN = /(?<![[:alnum:]])cancel/i

      module_function

      def call(message)
        return nil unless message&.inbound? && message.shop_id

        conversation = WhatsappConversation.find_by(id: message.whatsapp_conversation_id, shop_id: message.shop_id)
        return nil unless conversation

        keys = system_keys_for(message)
        return nil if keys.empty?

        WhatsappInboxLabel.ensure_defaults!(conversation.shop)
        label_ids = WhatsappInboxLabel.where(shop_id: conversation.shop_id, system_key: keys).pluck(:id)
        WhatsappConversationLabel.add!(conversation, label_ids, source: 'auto')
        keys
      end

      def system_keys_for(message)
        keys = []
        log = replied_to_log(message)
        keys << (log.whatsapp_campaign_id.present? ? 'campaign_reply' : 'notification_reply') if log
        keys << 'cancel_request' if message.kind == 'text' && CANCEL_PATTERN.match?(message.body.to_s)
        keys
      end

      def replied_to_log(message)
        return nil if message.whatsapp_inbound_message_id.blank?

        log_id = WhatsappInboundMessage.where(id: message.whatsapp_inbound_message_id, shop_id: message.shop_id)
                                       .pick(:whatsapp_message_log_id)
        log_id && WhatsappMessageLog.find_by(id: log_id)
      end
    end
  end
end

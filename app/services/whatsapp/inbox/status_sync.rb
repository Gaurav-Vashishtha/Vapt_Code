# frozen_string_literal: true

module Whatsapp
  module Inbox
    module StatusSync
      # Meta #131047: more than 24 hours since the customer last replied.
      REENGAGEMENT_REQUIRED_CODE = 131_047

      module_function

      def apply(meta_message_id, status, at, error = nil)
        return false if meta_message_id.blank? || status.blank?

        message = WhatsappConversationMessage.find_by(meta_message_id: meta_message_id.to_s)
        return false if message.nil?

        message.advance_status!(status, at: at || Time.current, error: error)
        if status.to_s == 'failed' && error.is_a?(Hash) && error['code'].to_i == REENGAGEMENT_REQUIRED_CODE
          WhatsappConversation.where(id: message.whatsapp_conversation_id)
                              .update_all(window_closed_hint_at: Time.current, updated_at: Time.current)
        end
        true
      end
    end
  end
end

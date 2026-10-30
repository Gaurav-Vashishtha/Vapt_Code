# frozen_string_literal: true

module Whatsapp
  module Inbox
    class MarkReadJob < ApplicationJob
      sidekiq_options queue: 'whatsapp_inbox', retry: 1, lock: :until_executed

      def perform(conversation_id)
        conversation = WhatsappConversation.find_by(id: conversation_id)
        ReadReceipt.call(conversation) if conversation
      end
    end
  end
end

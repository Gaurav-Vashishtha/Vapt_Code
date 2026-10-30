# frozen_string_literal: true

module Whatsapp
  module Inbox
    class BackfillThreadJob < ApplicationJob
      sidekiq_options queue: 'low', retry: 1

      DAYS = 30
      LIMIT = 500

      def perform(conversation_id)
        conversation = WhatsappConversation.find_by(id: conversation_id)
        return if conversation.nil? || conversation.whatsapp_account_id.nil?

        WhatsappMessageLog
          .where(whatsapp_account_id: conversation.whatsapp_account_id, shop_id: conversation.shop_id)
          .where("#{OutboundMirror::LOG_LAST10_SQL} = ?", conversation.phone_last10)
          .where('created_at >= ?', DAYS.days.ago)
          .where.not(meta_message_id: nil)
          .includes(:whatsapp_template)
          .order(created_at: :desc)
          .limit(LIMIT)
          .each do |log|
            OutboundMirror.call(log, conversation: conversation)
          rescue StandardError => e
            Rails.logger.error("[Whatsapp::Inbox::BackfillThreadJob] conversation=#{conversation.id} log=#{log.id} #{e.class}: #{e.message}")
          end
      end
    end
  end
end

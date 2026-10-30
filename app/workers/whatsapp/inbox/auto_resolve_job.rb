# frozen_string_literal: true

module Whatsapp
  module Inbox
    class AutoResolveJob < ApplicationJob
      sidekiq_options queue: 'low', retry: 1

      SILENCE = 72.hours

      def perform
        cutoff = SILENCE.ago
        WhatsappConversation.where(status: :pending)
                            .where('status_changed_at < ?', cutoff)
                            .where('last_inbound_at < status_changed_at')
                            .find_each { |conversation| resolve(conversation, cutoff) }
      end

      private

      def resolve(conversation, cutoff)
        conversation.with_lock do
          next unless conversation.status.to_s == 'pending'
          next unless conversation.status_changed_at < cutoff && conversation.last_inbound_at < conversation.status_changed_at

          ConversationState.resolve!(conversation, by: 'auto')
        end
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::Inbox::AutoResolveJob] conversation=#{conversation.id} #{e.class}: #{e.message}")
      end
    end
  end
end

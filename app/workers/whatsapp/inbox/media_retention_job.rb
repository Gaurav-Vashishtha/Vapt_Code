# frozen_string_literal: true

module Whatsapp
  module Inbox
    class MediaRetentionJob < ApplicationJob
      sidekiq_options queue: 'low', retry: 1

      RETENTION = 90.days

      def perform
        WhatsappConversationMessage
          .media_stored
          .where('occurred_at < ?', RETENTION.ago)
          .includes(media_file_attachment: :blob)
          .find_each do |message|
            message.media_file.purge if message.media_file.attached?
            message.update_columns(media_state: WhatsappConversationMessage.media_states['purged'], updated_at: Time.current)
          rescue StandardError => e
            Rails.logger.error("[Whatsapp::Inbox::MediaRetentionJob] message=#{message.id} #{e.class}: #{e.message}")
          end
      end
    end
  end
end

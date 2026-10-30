# frozen_string_literal: true

module Whatsapp
  module Inbox
    class DownloadMediaJob < ApplicationJob
      sidekiq_options queue: 'whatsapp_inbox', retry: 3

      sidekiq_retries_exhausted do |job, _error|
        WhatsappConversationMessage.where(id: job['args'].first, media_state: :pending)
                                   .update_all(media_state: WhatsappConversationMessage.media_states['failed'], updated_at: Time.current)
      end

      def perform(message_id)
        return unless MediaStore.enabled?

        message = WhatsappConversationMessage.find_by(id: message_id)
        return if message.nil? || message.media_id.blank?
        return if message.media_stored? || message.media_purged?

        account = message.whatsapp_conversation&.whatsapp_account
        return mark_failed(message) if account.nil?

        data = MediaFetcher.fetch(account, message.media_id)
        mime = message.media_mime_type.presence || data[:mime_type]
        MediaStore.attach!(message, io: StringIO.new(data[:bytes]), filename: file_name(message, mime), content_type: mime)
        message.update!(media_state: :stored, media_size: data[:bytes].bytesize, media_mime_type: mime,
                        media_sha256: message.media_sha256.presence || data[:sha256])
      rescue MediaFetcher::Expired, MediaFetcher::TooLarge => e
        Rails.logger.info("[Whatsapp::Inbox::DownloadMediaJob] message=#{message_id} #{e.class}: #{e.message}")
        mark_failed(message) if message
      end

      private

      def mark_failed(message)
        message.update!(media_state: :failed)
      end

      def file_name(message, mime)
        return message.media_file_name if message.media_file_name.present?

        ext = Rack::Mime::MIME_TYPES.key(mime.to_s.split(';').first.to_s.strip)
        "#{message.kind}-#{message.id}#{ext || '.bin'}"
      end
    end
  end
end

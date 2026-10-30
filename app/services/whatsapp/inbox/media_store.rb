# frozen_string_literal: true

module Whatsapp
  module Inbox
    module MediaStore
      # Meta keeps media ids retrievable for about 30 days.
      PROXY_MAX_AGE = 29.days
      PURPOSE = 'whatsapp_inbox_media'

      module_function

      def s3?
        ENV['WHATSAPP_MEDIA_S3_BUCKET'].present?
      end

      # Production web and worker dynos do not share a disk, so Disk storage
      # only works outside production.
      def enabled?
        s3? || !Rails.env.production?
      end

      # analyzed/identified skip ActiveStorage's analyze job, whose queue is not
      # processed by this app's Sidekiq.
      def attach!(message, io:, filename:, content_type:)
        message.media_file.attach(
          io: io, filename: filename, content_type: content_type,
          metadata: { 'analyzed' => true, 'identified' => true }
        )
      end

      def url_for(message, expires_in: 1.hour)
        return nil if message.nil? || message.media_purged?

        if message.media_stored?
          if s3? && message.media_file.attached?
            inline = message.media_file.content_type.to_s.match?(WhatsappInboxMediaController::INLINE_TYPES)
            return message.media_file.url(expires_in: expires_in, disposition: inline ? :inline : :attachment)
          end

          return proxy_url(message, expires_in)
        end
        return nil if message.media_id.blank? || message.occurred_at.nil? || message.occurred_at < PROXY_MAX_AGE.ago

        proxy_url(message, expires_in)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Inbox::MediaStore] url failed message=#{message&.id}: #{e.class}: #{e.message}")
        nil
      end

      def proxy_url(message, expires_in)
        host = ENV['APP_HOST'].presence || 'app.codking.tech'
        "https://#{host}/whatsapp_inbox_media/#{token_for(message, expires_in)}"
      end

      def token_for(message, expires_in)
        verifier.generate(message.id, expires_in: expires_in, purpose: PURPOSE)
      end

      def message_id_for(token)
        verifier.verified(token.to_s, purpose: PURPOSE)
      rescue StandardError
        nil
      end

      def verifier
        @verifier ||= ActiveSupport::MessageVerifier.new(
          Rails.application.key_generator.generate_key(PURPOSE, 32),
          digest: 'SHA256', serializer: JSON, url_safe: true
        )
      end
    end
  end
end

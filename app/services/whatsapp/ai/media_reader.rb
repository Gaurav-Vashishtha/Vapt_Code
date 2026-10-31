# frozen_string_literal: true

require 'tempfile'

module Whatsapp
  module Ai
    module MediaReader
      TRANSCRIBE_ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'
      TIMEOUT = 30
      MAX_IMAGE_BYTES = 4.megabytes
      MAX_AUDIO_BYTES = 16.megabytes
      IMAGE_LIMIT = 2
      IMAGE_TYPES = %r{\Aimage/(jpeg|png|webp|gif)\z}
      AUDIO_EXTENSIONS = { 'audio/ogg' => 'ogg', 'audio/mpeg' => 'mp3', 'audio/mp4' => 'm4a', 'audio/aac' => 'm4a',
                           'audio/amr' => 'amr', 'audio/wav' => 'wav', 'audio/webm' => 'webm' }.freeze

      module_function

      def enabled?
        ENV.fetch("WHATSAPP_AI_MEDIA_DISABLED", nil).blank? && Config.api_key.present?
      end

      def transcribe_model
        ENV.fetch("WHATSAPP_AI_TRANSCRIBE_MODEL", nil).presence || 'gpt-4o-mini-transcribe'
      end

      def transcript(message)
        return nil unless enabled? && message.inbound? && message.kind.to_s == 'audio'

        content = message.content.is_a?(Hash) ? message.content : {}
        return content['transcript'] if content['transcript'].present?
        return nil if content['transcript_failed']

        data = fetch(message, MAX_AUDIO_BYTES)
        text = data && transcribe(data[:bytes], data[:mime_type])
        store(message, content, text.present? ? { 'transcript' => text } : { 'transcript_failed' => true })
        text.presence
      end

      def image_data_url(message)
        return nil unless enabled? && message.inbound? && message.kind.to_s == 'image'

        data = fetch(message, MAX_IMAGE_BYTES)
        return nil unless data

        mime = data[:mime_type].to_s.split(';').first.to_s.strip
        return nil unless mime.match?(IMAGE_TYPES)

        "data:#{mime};base64,#{Base64.strict_encode64(data[:bytes])}"
      end

      def fetch(message, max_bytes)
        if message.media_stored? && message.media_file.attached?
          return nil if message.media_file.byte_size.to_i > max_bytes

          return { bytes: message.media_file.download, mime_type: message.media_mime_type.presence || message.media_file.content_type }
        end
        return nil if message.media_id.blank? || message.media_purged?

        account = message.whatsapp_conversation&.whatsapp_account
        data = Whatsapp::Inbox::MediaFetcher.fetch(account, message.media_id, max_bytes: max_bytes)
        { bytes: data[:bytes], mime_type: message.media_mime_type.presence || data[:mime_type] }
      rescue StandardError => e
        Rails.logger.info("[Whatsapp::Ai::MediaReader] fetch failed message=#{message.id}: #{e.class}: #{e.message}")
        nil
      end

      def transcribe(bytes, mime_type)
        ext = AUDIO_EXTENSIONS[mime_type.to_s.split(';').first.to_s.strip] || 'ogg'
        Tempfile.create(['voice', ".#{ext}"]) do |file|
          file.binmode
          file.write(bytes)
          file.flush
          file.rewind
          response = HTTParty.post(
            TRANSCRIBE_ENDPOINT,
            headers: { 'Authorization' => "Bearer #{Config.api_key}" },
            body: { file: file, model: transcribe_model },
            multipart: true,
            timeout: TIMEOUT
          )
          unless response.code.to_i.between?(200, 299)
            Rails.logger.warn("[Whatsapp::Ai::MediaReader] transcription HTTP #{response.code}: #{response.body.to_s.first(200)}")
            return nil
          end
          JSON.parse(response.body.to_s)['text'].to_s.strip.first(2000).presence
        end
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::MediaReader] transcription failed: #{e.class}: #{e.message}")
        nil
      end

      def store(message, content, extra)
        message.update_column(:content, content.merge(extra))
      rescue StandardError => e
        Rails.logger.info("[Whatsapp::Ai::MediaReader] could not cache result message=#{message.id}: #{e.class}")
      end
    end
  end
end

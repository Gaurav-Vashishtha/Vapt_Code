# frozen_string_literal: true

require 'httparty'

module Whatsapp
  module Inbox
    module MediaFetcher
      class Error < StandardError; end
      class Expired < Error; end
      class TooLarge < Error; end

      MAX_BYTES = 25.megabytes
      # Meta answers GET /{media_id} for an expired or unknown id with #100.
      MISSING_MEDIA_CODE = 100

      module_function

      def metadata(account, media_id)
        raise Expired, 'no media id' if media_id.blank?

        Meta::GraphClient.new(token: account.system_user_token, timeout: 10).get(media_id.to_s)
      rescue Meta::GraphClient::Error => e
        raise Expired, e.message if e.status.to_i == 404 || e.code.to_i == MISSING_MEDIA_CODE

        raise Error, e.message
      end

      # Meta media urls live about 5 minutes and need the same bearer token.
      def download(account, url, max_bytes: MAX_BYTES)
        raise Error, 'no media url' if url.blank?

        buffer = String.new(encoding: Encoding::BINARY)
        response = HTTParty.get(
          url,
          headers: { 'Authorization' => "Bearer #{account.system_user_token}", 'User-Agent' => 'CODKing-Inbox/1.0' },
          timeout: 30,
          stream_body: true
        ) do |fragment|
          next unless fragment.code.to_i == 200

          buffer << fragment.to_s
          raise TooLarge, "media larger than #{max_bytes} bytes" if buffer.bytesize > max_bytes
        end
        raise Expired, "media download HTTP #{response.code}" if response.code.to_i == 404
        raise Error, "media download HTTP #{response.code}" unless response.code.to_i == 200

        buffer
      rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
        raise Error, "#{e.class}: #{e.message}"
      end

      def fetch(account, media_id, max_bytes: MAX_BYTES)
        raise Error, 'no account' if account.nil? || account.system_user_token.blank?

        meta = metadata(account, media_id)
        if meta['file_size'].to_i > max_bytes
          raise TooLarge, "media is #{meta['file_size']} bytes"
        end

        bytes = download(account, meta['url'], max_bytes: max_bytes)
        { bytes: bytes, mime_type: meta['mime_type'].to_s.presence || 'application/octet-stream', sha256: meta['sha256'] }
      end

      def stream(message)
        fetch(message.whatsapp_conversation&.whatsapp_account, message.media_id)
      end
    end
  end
end

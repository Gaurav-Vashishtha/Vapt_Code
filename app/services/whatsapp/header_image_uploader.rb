require 'digest'

module Whatsapp
  class HeaderImageUploader
    CACHE_TTL = 6.hours

    def self.call(account:, url:)
      return nil if url.blank? || account.nil? || account.phone_number_id.blank?

      Rails.cache.fetch(cache_key(account, url), expires_in: CACHE_TTL, skip_nil: true) do
        bytes = fetch_bytes(url)
        jpeg = bytes.present? ? Whatsapp::ImageTranscoder.to_jpeg(bytes) : nil
        next nil if jpeg.blank?

        Meta::MessagesMediaUploadService.call(account: account, bytes: jpeg, mime_type: 'image/jpeg')
      end
    rescue => e
      Rails.logger.warn("[whatsapp/header_upload] account=#{account&.id} url=#{url}: #{e.class}: #{e.message}")
      nil
    end

    def self.cache_key(account, url)
      "whatsapp/header_media_id/#{account.id}/#{Digest::MD5.hexdigest(url.to_s)}"
    end

    def self.fetch_bytes(url)
      resp = HTTParty.get(url, timeout: 25, follow_redirects: true)
      return nil unless resp.success?

      resp.body
    end
  end
end

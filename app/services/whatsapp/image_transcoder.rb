module Whatsapp
  # Meta's WhatsApp media headers accept only JPEG/PNG; HEIC/HEIF (iPhone
  # uploads) and WebP are rejected with 131053. libvips is loaded lazily and is
  # optional — a build without the HEIF loader just returns nil here, and the
  # header pipeline falls back to the branded logo, so a missing codec never
  # breaks a send.
  class ImageTranscoder
    MAX_DIMENSION = 1280
    JPEG_QUALITY = 80

    def self.to_jpeg(bytes)
      return nil if bytes.blank?
      return nil unless vips_available?

      image = Vips::Image.thumbnail_buffer(bytes.b, MAX_DIMENSION, size: :down)
      image = image.flatten(background: 255) if image.has_alpha?
      image.jpegsave_buffer(Q: JPEG_QUALITY, strip: true, interlace: true)
    rescue => e
      Rails.logger.warn("[whatsapp/transcode] decode failed: #{e.class}: #{e.message}")
      nil
    end

    def self.vips_available?
      return @vips_available unless @vips_available.nil?

      @vips_available =
        begin
          require 'vips'
          true
        rescue LoadError => e
          Rails.logger.warn("[whatsapp/transcode] libvips unavailable, HEIC/WebP headers fall back to the branded logo: #{e.message}")
          false
        end
    end
  end
end

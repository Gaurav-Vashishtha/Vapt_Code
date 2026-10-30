require 'net/http'
require 'net/http/post/multipart'
require 'stringio'

module Meta
  # Uploads media via Meta's *Messages* Media API (distinct from the Resumable
  # Upload API). Returns a media_id usable as the `image.id` / `video.id` /
  # `document.id` parameter when sending template messages.
  #
  # Why a second upload path: Meta's two upload APIs are not interchangeable.
  #   - Resumable Upload (`/{app_id}/uploads`) → returns a HANDLE only valid for
  #     the template's `example.header_handle` during review.
  #   - Messages Media   (`/{phone_number_id}/media`) → returns a MEDIA_ID only
  #     valid for the `image`/`video`/`document` parameter at send time.
  # We do both at template-create time so the merchant's upload survives review
  # AND can be delivered to recipients without re-uploading.
  #
  # We use Net::HTTP + multipart-post directly because Meta is strict about the
  # multipart body shape: the `file` part needs an explicit filename and
  # Content-Type, and only `messaging_product` + `file` + optional `type`
  # should appear (HTTParty's automatic multipart sometimes mangles these).
  class MessagesMediaUploadService < ApplicationService
    class Error < StandardError; end

    BASE = 'https://graph.facebook.com'.freeze

    def initialize(account:, bytes:, mime_type:, file_name: nil)
      @account = account
      @bytes = bytes
      @mime_type = mime_type.to_s.presence || 'application/octet-stream'
      @file_name = file_name.presence || default_file_name(mime_type)
    end

    def call
      raise Error, 'account has no phone_number_id' if account.phone_number_id.blank?
      raise Error, 'account has no system_user_token' if account.system_user_token.blank?
      raise Error, 'bytes are required' if bytes.blank?

      uri = URI.parse("#{BASE}/#{version}/#{account.phone_number_id}/media")

      io = StringIO.new(bytes.b)
      upload = UploadIO.new(io, mime_type, file_name)

      req = Net::HTTP::Post::Multipart.new(
        uri.request_uri,
        'messaging_product' => 'whatsapp',
        'type'              => mime_type,
        'file'              => upload
      )
      req['Authorization'] = "Bearer #{account.system_user_token}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60
      http.open_timeout = 10

      resp = http.request(req)

      unless resp.is_a?(Net::HTTPSuccess)
        raise Error, error_from(resp)
      end

      parsed = JSON.parse(resp.body || '{}')
      parsed['id'].presence || raise(Error, 'Meta did not return a media_id')
    end

    private

    attr_reader :account, :bytes, :mime_type, :file_name

    def version
      ENV.fetch('META_GRAPH_API_VERSION', 'v22.0')
    end

    def default_file_name(mime)
      case mime
      when %r{image/jpe?g} then 'upload.jpg'
      when 'image/png'     then 'upload.png'
      when 'image/webp'    then 'upload.webp'
      when 'video/mp4'     then 'upload.mp4'
      when 'application/pdf' then 'upload.pdf'
      else                      'upload.bin'
      end
    end

    def error_from(resp)
      parsed = JSON.parse(resp.body || '{}') rescue {}
      msg = parsed.dig('error', 'message') || parsed['error'] || "HTTP #{resp.code}"
      "Failed to upload messages media: #{msg}"
    end
  end
end

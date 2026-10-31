require 'httparty'

module Meta
  # Wraps Meta's Resumable Upload API. Two HTTP calls:
  #   1. POST /{app_id}/uploads?file_length=…&file_type=… → { id: "upload:..." }
  #   2. POST /{upload_id} with Authorization: OAuth {token}, file_offset: 0
  #      and the raw bytes as body → { h: "<media_handle>" }
  #
  # The returned handle is what goes into a template's
  # `components[i].example.header_handle` array.
  class ResumableUploadService < ApplicationService
    class Error < StandardError; end

    BASE = 'https://graph.facebook.com'.freeze

    def initialize(account:, bytes: nil, file: nil, mime_type:, file_name: nil)
      @account = account
      @bytes = bytes
      @file = file
      @mime_type = mime_type.to_s.presence || 'application/octet-stream'
      @file_name = file_name
    end

    def call
      raise Error, 'META_APP_ID is not configured' if ENV.fetch("META_APP_ID", nil).blank?
      raise Error, 'account has no system_user_token' if account.system_user_token.blank?

      data = bytes || (file && file.read.b)
      raise Error, 'bytes or file is required' if data.blank?

      session_id = start_session(data.bytesize)
      upload_bytes(session_id, data)
    end

    private

    attr_reader :account, :file, :bytes, :mime_type, :file_name

    def version
      ENV.fetch('META_GRAPH_API_VERSION', 'v22.0')
    end

    def start_session(length)
      url = "#{BASE}/#{version}/#{ENV.fetch("META_APP_ID", nil)}/uploads"
      resp = HTTParty.post(
        url,
        query: {
          file_length: length,
          file_type: mime_type,
          file_name: file_name,
          access_token: account.system_user_token
        }.compact
      )
      raise Error, error_from(resp, 'start upload session') unless resp.success?
      parsed = JSON.parse(resp.body || '{}')
      parsed['id'].presence || raise(Error, 'Meta did not return an upload session id')
    end

    def upload_bytes(session_id, bytes)
      url = "#{BASE}/#{version}/#{session_id}"
      resp = HTTParty.post(
        url,
        headers: {
          'Authorization' => "OAuth #{account.system_user_token}",
          'file_offset' => '0',
          'Content-Type' => mime_type
        },
        body: bytes
      )
      raise Error, error_from(resp, 'upload media bytes') unless resp.success?
      parsed = JSON.parse(resp.body || '{}')
      parsed['h'].presence || raise(Error, 'Meta did not return a media handle')
    end

    def error_from(resp, action)
      parsed = JSON.parse(resp.body || '{}') rescue {}
      msg = parsed.dig('error', 'message') || parsed['error'] || "HTTP #{resp.code}"
      "Failed to #{action}: #{msg}"
    end
  end
end

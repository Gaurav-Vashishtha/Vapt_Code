require 'httparty'

module Meta
  class GraphClient
    include HTTParty

    class Error < StandardError
      attr_reader :status, :body, :code, :subcode

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
        # Meta's own numeric error code (e.g. 133010), distinct from the HTTP
        # status — every Cloud API failure is a 400 or 401, so the HTTP code
        # alone can't tell two failure modes apart.
        @code = body.is_a?(Hash) ? body.dig('error', 'code') : nil
        @subcode = body.is_a?(Hash) ? body.dig('error', 'error_subcode') : nil
      end
    end

    BASE_URL = 'https://graph.facebook.com'.freeze

    # +timeout+ is opt-in so existing callers keep HTTParty's default (no limit).
    # Callers on the request path must pass one — see MetaEvents::CapiClient.
    def initialize(token:, version: nil, timeout: nil)
      @token = token
      @version = version.presence || ENV.fetch('META_GRAPH_API_VERSION', 'v22.0')
      @timeout = timeout
    end

    def get(path, query: {})
      request(:get, path, query: query)
    end

    def post(path, body: {})
      request(:post, path, body: body)
    end

    def delete(path, query: {})
      request(:delete, path, query: query)
    end

    private

    attr_reader :token, :version, :timeout

    def request(method, path, query: {}, body: {})
      url = "#{BASE_URL}/#{version}/#{path.sub(%r{\A/}, '')}"
      options = {
        headers: {
          'Authorization' => "Bearer #{token}",
          'Content-Type' => 'application/json'
        }
      }
      if timeout.present?
        options[:timeout] = timeout
        options[:open_timeout] = timeout
      end
      options[:query] = query if query.any?
      options[:body] = body.to_json if body.any? && method != :get

      response = HTTParty.public_send(method, url, options)
      parsed = parse(response)

      unless response.success?
        Rails.logger.warn("[meta/graph] #{method.upcase} #{path} -> #{response.code}: #{response.body}")
        raise Error.new(error_message(parsed), status: response.code, body: parsed)
      end

      parsed
    end

    def parse(response)
      JSON.parse(response.body || '{}')
    rescue JSON::ParserError
      {}
    end

    def error_message(parsed)
      err = parsed['error']
      return parsed['error'] unless err.is_a?(Hash)

      # Prefer the human-friendly title+message Meta returns for user-actionable errors.
      title = err['error_user_title']
      msg   = err['error_user_msg']
      base =
        if title || msg
          [title, msg].compact.join(': ')
        else
          err['message'] || 'Meta Graph API error'
        end

      # error_data.details is where Meta names the SPECIFIC problem — e.g.
      # which component parameter a #131008 is missing. Without it the stored
      # error is just "Required parameter is missing", which is undebuggable.
      details = err.dig('error_data', 'details')
      details.present? ? "#{base} — #{details}" : base
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module CodForm
  module Tracking
    # Small JSON-over-HTTPS helper shared by the pixel clients and the integration clients.
    # Fixed timeouts, no redirects, and nothing about the request (URL, headers, body) or the
    # response body is ever logged: URLs can carry tokens and bodies carry buyer data.
    module Http
      OPEN_TIMEOUT = 3
      READ_TIMEOUT = 8
      NETWORK_ERRORS = [
        Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET,
        Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::EPIPE, SocketError, OpenSSL::SSL::SSLError,
        Timeout::Error, EOFError, IOError
      ].freeze

      # status: Integer HTTP status, or 0 for a network failure.
      Response = Struct.new(:status, :body, :error, keyword_init: true) do
        def ok?
          status.between?(200, 299)
        end

        # Worth another attempt later: network failure, rate limit, vendor-side error.
        def retryable?
          status.zero? || status == 408 || status == 429 || status >= 500
        end

        # Parsed JSON body (Hash / Array), or {} when it is not JSON.
        def json
          @json ||= begin
            parsed = JSON.parse(body.to_s)
            parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : {}
          rescue JSON::ParserError
            {}
          end
        end

        # Short, token-free description for last_error columns and warn logs.
        def summary
          return "network error (#{error})" if status.zero?

          "HTTP #{status}"
        end
      end

      module_function

      # Uniform result of one client call, string keys:
      #   {"ok", "status", "retryable", "skipped" (reason or nil), "response" (small parsed body)}
      def outcome(response)
        {
          "ok" => response.ok?,
          "status" => response.status,
          "retryable" => !response.ok? && response.retryable?,
          "skipped" => nil,
          "error" => response.ok? ? nil : response.summary,
          "response" => response.json
        }
      end

      def skipped(reason)
        { "ok" => true, "status" => nil, "retryable" => false, "skipped" => reason.to_s, "error" => nil, "response" => {} }
      end

      def failed(reason, retryable: false)
        { "ok" => false, "status" => nil, "retryable" => retryable, "skipped" => nil, "error" => reason.to_s, "response" => {} }
      end

      def post_json(url, payload, headers: {}, read_timeout: READ_TIMEOUT)
        request(:post, url, body: JSON.generate(payload),
                            headers: { "Content-Type" => "application/json" }.merge(headers),
                            read_timeout: read_timeout)
      end

      def post_form(url, params, headers: {}, read_timeout: READ_TIMEOUT)
        request(:post, url, body: URI.encode_www_form(params),
                            headers: { "Content-Type" => "application/x-www-form-urlencoded" }.merge(headers),
                            read_timeout: read_timeout)
      end

      def get(url, headers: {}, read_timeout: READ_TIMEOUT)
        request(:get, url, headers: headers, read_timeout: read_timeout)
      end

      def request(verb, url, body: nil, headers: {}, read_timeout: READ_TIMEOUT)
        uri = URI.parse(url)
        raise ArgumentError, "https only" unless uri.is_a?(URI::HTTPS)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = read_timeout
        http.write_timeout = read_timeout if http.respond_to?(:write_timeout=)

        req = verb == :get ? Net::HTTP::Get.new(uri.request_uri) : Net::HTTP::Post.new(uri.request_uri)
        { "Accept" => "application/json" }.merge(headers).each do |key, value|
          req[key] = value.to_s unless value.nil?
        end
        req.body = body unless body.nil?

        res = http.request(req)
        Response.new(status: res.code.to_i, body: res.body.to_s, error: nil)
      rescue *NETWORK_ERRORS => e
        Response.new(status: 0, body: "", error: e.class.name)
      end
    end
  end
end

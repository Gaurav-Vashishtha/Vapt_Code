# frozen_string_literal: true

require 'net/http'
require 'json'

module PartnerApi
  # Minimal Shopify Partner API GraphQL client shared by the churn jobs.
  #
  # Env:
  #   SHOPIFY_PARTNER_ACCESS_TOKEN
  #   SHOPIFY_PARTNER_ORGANIZATION_ID (falls back to SHOPIFY_ORGANIZATION_ID)
  #   SHOPIFY_PARTNER_API_VERSION     (default 2026-04)
  #   SHOPIFY_PARTNER_APP_ID          (default 5284415 — COD King)
  #
  # Retries throttling (HTTP 429 / "Throttled" GraphQL errors) and transient
  # 5xx with backoff; anything else raises PartnerApi::GraphqlClient::Error.
  class GraphqlClient
    class Error < StandardError; end
    class ConfigError < Error; end

    DEFAULT_API_VERSION = '2026-04'
    DEFAULT_APP_ID = '5284415'
    ENDPOINT = 'https://partners.shopify.com/%s/api/%s/graphql.json'
    MAX_ATTEMPTS = 5
    # Partner API allows ~4 requests/second per org; stay under it when paging.
    MIN_INTERVAL = 0.3

    # True when the last fetch_all stopped at max_pages with more pages left.
    attr_reader :last_truncated

    def self.app_gid(app_id = nil)
      id = (app_id.presence || ENV.fetch("SHOPIFY_PARTNER_APP_ID", nil).presence || DEFAULT_APP_ID).to_s.strip
      id.start_with?('gid://') ? id : "gid://partners/App/#{id}"
    end

    def initialize
      @token = ENV.fetch("SHOPIFY_PARTNER_ACCESS_TOKEN", nil).to_s.strip
      @org = (ENV.fetch("SHOPIFY_PARTNER_ORGANIZATION_ID", nil).presence || ENV.fetch("SHOPIFY_ORGANIZATION_ID", nil)).to_s.strip
      @version = ENV.fetch('SHOPIFY_PARTNER_API_VERSION', DEFAULT_API_VERSION).to_s.strip
      raise ConfigError, 'Missing SHOPIFY_PARTNER_ACCESS_TOKEN or SHOPIFY_PARTNER_ORGANIZATION_ID' if @token.blank? || @org.blank?

      @uri = URI(format(ENDPOINT, @org, @version))
      @last_request_at = nil
    end

    # Returns the parsed `data` hash.
    def query(gql, variables = {})
      attempt = 0
      begin
        attempt += 1
        throttle!
        res = post(gql, variables)

        if res.code == '429' || res.code.to_i >= 500
          raise RetryableError, "Partner API HTTP #{res.code}"
        end
        raise Error, "Partner API HTTP #{res.code}: #{res.body.to_s[0, 500]}" unless res.code == '200'

        body = JSON.parse(res.body)
        if body['errors'].present?
          messages = Array(body['errors']).map { |e| e['message'] }.join('; ')
          raise RetryableError, messages if messages =~ /throttl/i
          raise Error, "GraphQL errors: #{messages}"
        end
        body['data'] || {}
      rescue RetryableError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError => e
        raise Error, "Partner API failed after #{attempt} attempts: #{e.message}" if attempt >= MAX_ATTEMPTS

        sleep(2**attempt)
        retry
      end
    end

    # Follows a connection's pageInfo.hasNextPage and returns every node.
    # The block receives the `after` cursor (nil for the first page) and must
    # return the query string; `path` is the key path from `data` to the
    # connection, e.g. %w[transactions] or %w[app events].
    def fetch_all(path:, max_pages: 500)
      nodes = []
      cursor = nil
      pages = 0
      @last_truncated = false
      loop do
        pages += 1
        connection = query(yield(cursor)).dig(*path) || {}
        edges = connection['edges'] || []
        edges.each { |edge| nodes << edge['node'] if edge['node'] }
        break unless connection.dig('pageInfo', 'hasNextPage')

        cursor = edges.last&.dig('cursor')
        if cursor.blank? || pages >= max_pages
          @last_truncated = true
          break
        end
      end
      nodes
    end

    private

    class RetryableError < StandardError; end

    def throttle!
      if @last_request_at
        wait = MIN_INTERVAL - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at)
        sleep(wait) if wait.positive?
      end
      @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def post(gql, variables)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 60
      req = Net::HTTP::Post.new(@uri)
      req['X-Shopify-Access-Token'] = @token
      req['Content-Type'] = 'application/json'
      req.body = { query: gql, variables: variables }.to_json
      http.request(req)
    end
  end
end

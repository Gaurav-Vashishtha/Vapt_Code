# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'

module PricingJobs
  # Pulls AppUsageSale transactions from the Shopify Partner API for the last N days
  # and posts a per-day breakdown (count + total $) to Slack.
  #
  # Org-wide: does NOT filter by myshopifyDomain, so it covers every shop on the partner org.
  #
  # Env vars (same as NetworkServices::ShopifyPartnerRevenueFetcher):
  #   SHOPIFY_PARTNER_ACCESS_TOKEN
  #   SHOPIFY_PARTNER_ORGANIZATION_ID
  #   SHOPIFY_PARTNER_API_VERSION (optional, defaults to 2026-04)
  class PartnerUsageChargesPerDayJob < ApplicationJob
    sidekiq_options queue: "administration"

    DEFAULT_PARTNER_API_VERSION = "2026-04"
    PARTNER_API_BASE = "https://partners.shopify.com/%s/api/%s/graphql.json"
    PAGE_SIZE = 100

    def perform(days = 30)
      access_token = ENV.fetch("SHOPIFY_PARTNER_ACCESS_TOKEN", nil).to_s.strip
      organization_id = (ENV.fetch("SHOPIFY_PARTNER_ORGANIZATION_ID", nil).presence || ENV.fetch("SHOPIFY_ORGANIZATION_ID", nil)).to_s.strip
      api_version = ENV.fetch("SHOPIFY_PARTNER_API_VERSION", DEFAULT_PARTNER_API_VERSION).to_s.strip

      if access_token.blank? || organization_id.blank?
        Rails.logger.error("[PartnerUsageChargesPerDayJob] Missing SHOPIFY_PARTNER_ACCESS_TOKEN or SHOPIFY_PARTNER_ORGANIZATION_ID")
        return
      end

      endpoint = format(PARTNER_API_BASE, organization_id, api_version)
      end_date = Date.current
      start_date = end_date - days.to_i.days
      start_iso = start_date.to_time.utc.iso8601
      end_iso = (end_date + 1).to_time.utc.iso8601

      Rails.logger.info("[PartnerUsageChargesPerDayJob] Fetching AppUsageSale from #{start_iso} to #{end_iso}")

      per_day_amount = Hash.new(0.0)
      per_day_count = Hash.new(0)
      grand_total = 0.0
      grand_count = 0
      currency = nil
      cursor = nil
      pages = 0

      loop do
        pages += 1
        data = execute(endpoint, access_token, build_query(start_iso, end_iso, cursor))
        edges = data.dig("transactions", "edges") || []

        edges.each do |edge|
          node = edge["node"]
          next unless node && node["__typename"] == "AppUsageSale"
          next unless node["netAmount"]

          amount = node["netAmount"]["amount"].to_f
          currency ||= node["netAmount"]["currencyCode"]
          day = (Date.parse(node["createdAt"]) rescue nil)
          next unless day

          per_day_amount[day] += amount
          per_day_count[day] += 1
          grand_total += amount
          grand_count += 1
        end

        page_info = data.dig("transactions", "pageInfo") || {}
        break unless page_info["hasNextPage"] == true
        cursor = edges.last&.dig("cursor")
        break if cursor.blank?
      end

      Rails.logger.info("[PartnerUsageChargesPerDayJob] Done. pages=#{pages} txns=#{grand_count} total=#{grand_total.round(2)} #{currency}")

      ping_slack(start_date, end_date, per_day_amount, per_day_count, grand_total, grand_count, currency)
    rescue => e
      Rails.logger.error("[PartnerUsageChargesPerDayJob] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
      SlackNotifier::CLIENT.ping(text: "PartnerUsageChargesPerDayJob (#{Rails.env}) failed: #{e.class}: #{e.message}") rescue nil
    end

    private

    def build_query(start_iso, end_iso, after)
      after_clause = after.present? ? %(after: "#{after}") : ""
      <<~GQL
        {
          transactions(
            first: #{PAGE_SIZE}
            #{after_clause}
            createdAtMin: "#{start_iso}"
            createdAtMax: "#{end_iso}"
          ) {
            edges {
              cursor
              node {
                __typename
                ... on AppUsageSale {
                  id
                  createdAt
                  chargeId
                  netAmount { amount currencyCode }
                  shop { myshopifyDomain }
                  app { name }
                }
              }
            }
            pageInfo { hasNextPage }
          }
        }
      GQL
    end

    def execute(endpoint, token, query)
      uri = URI(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri)
      req["X-Shopify-Access-Token"] = token
      req["Content-Type"] = "application/json"
      req.body = { query: query }.to_json
      res = http.request(req)
      raise "Partner API HTTP #{res.code}: #{res.body}" unless res.code == "200"
      body = JSON.parse(res.body)
      raise "GraphQL errors: #{body['errors'].map { |e| e['message'] }.join('; ')}" if body["errors"].present?
      body["data"]
    end

    def ping_slack(start_date, end_date, per_day_amount, per_day_count, grand_total, grand_count, currency)
      currency ||= "USD"
      lines = (start_date..end_date).map do |day|
        amount = per_day_amount[day] || 0.0
        count = per_day_count[day] || 0
        "#{day.iso8601}  -  $#{format('%.2f', amount)}  (#{count} txn)"
      end

      msg = ":moneybag: *Partner Usage Charges Per Day (#{Rails.env})*\n" \
            "Period: #{start_date.iso8601} → #{end_date.iso8601}\n" \
            "Total: $#{format('%.2f', grand_total)} #{currency} across #{grand_count} usage transactions\n\n" \
            "```\n#{lines.join("\n")}\n```"

      SlackNotifier::CLIENT.ping(text: msg)
    end
  end
end

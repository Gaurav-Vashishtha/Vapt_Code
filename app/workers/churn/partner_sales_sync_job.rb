module Churn
  # Pulls COD King transactions (subscription, usage, adjustments, credits) for
  # the app in SHOPIFY_PARTNER_APP_ID (default 5284415) from the Shopify Partner
  # API into partner_sales (authoritative revenue) plus a billing_event per
  # subscription sale. Idempotent on external_id.
  #
  # Filtered by appId: the Partner org also holds other apps, whose revenue
  # used to leak into COD King's numbers (those older rows have app_id NULL and
  # are ignored by the churn baseline). A negative subscription amount is a
  # refund/proration, NOT a cancellation — it is recorded as 'refund'. Real
  # cancellations come from Partner app events (Churn::PartnerAppEventsSync).
  #
  # Hourly via schedule.yml (2 days). Churn::ChurnedStoresSyncJob calls
  # `sync!` directly for a longer window and gets errors raised back.
  class PartnerSalesSyncJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 2

    SALE_TYPES = {
      'AppSubscriptionSale' => 'subscription',
      'AppUsageSale' => 'usage',
      'AppSaleAdjustment' => 'adjustment',
      'AppSaleCredit' => 'adjustment'
    }.freeze
    TYPES_FILTER = 'APP_SUBSCRIPTION_SALE, APP_USAGE_SALE, APP_SALE_ADJUSTMENT, APP_SALE_CREDIT'.freeze
    FIELDS = 'id createdAt chargeId netAmount { amount currencyCode } grossAmount { amount currencyCode } shop { myshopifyDomain } app { name }'.freeze
    MAX_PAGES = 1000
    # Earliest date the org-wide sync has fully covered; the churn page uses it
    # to tell whether the revenue baseline for a period is complete.
    COVERAGE_KEY = 'churn:partner_sales:covered_from'.freeze

    def perform(days = 2)
      result = sync!(days)
      Rails.logger.info("[Churn::PartnerSalesSyncJob] #{result.inspect}")
    rescue => e
      Rails.logger.error("[Churn::PartnerSalesSyncJob] #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async("Churn::PartnerSalesSyncJob (#{Rails.env}) failed: #{e.message}") rescue nil
    end

    # Raises on API failure. Returns { imported:, fetched:, truncated: }.
    def sync!(days, client: PartnerApi::GraphqlClient.new)
      start_time = days.to_i.days.ago
      start_iso = start_time.utc.iso8601
      end_iso = (Time.current + 1.day).utc.iso8601
      app_gid = PartnerApi::GraphqlClient.app_gid

      nodes = client.fetch_all(path: %w[transactions], max_pages: MAX_PAGES) do |cursor|
        query(app_gid, start_iso, end_iso, cursor)
      end
      imported = nodes.count { |node| persist(node, app_gid) }
      truncated = client.last_truncated
      record_coverage(start_time) unless truncated
      { imported: imported, fetched: nodes.size, truncated: truncated }
    end

    def self.covered_from
      raw = Sidekiq.redis { |r| r.get(COVERAGE_KEY) }
      raw.present? ? Time.zone.parse(raw) : nil
    rescue
      nil
    end

    private

    def record_coverage(start_time)
      current = self.class.covered_from
      return if current && current <= start_time

      Sidekiq.redis { |r| r.set(COVERAGE_KEY, start_time.utc.iso8601) }
    rescue => e
      Rails.logger.warn("[Churn::PartnerSalesSyncJob] coverage write failed: #{e.message}")
    end

    def persist(node, app_gid)
      return false unless node
      sale_type = SALE_TYPES[node['__typename']]
      return false unless sale_type
      return false if node['id'].blank?

      domain = node.dig('shop', 'myshopifyDomain')
      net = node.dig('netAmount', 'amount').to_f
      gross = node.dig('grossAmount', 'amount')
      currency = node.dig('netAmount', 'currencyCode')
      occurred = (Time.zone.parse(node['createdAt'].to_s) rescue nil) || Time.current

      sale = PartnerSale.find_or_initialize_by(external_id: node['id'])
      sale.assign_attributes(
        shopify_domain: domain, sale_type: sale_type, charge_id: node['chargeId'],
        gross_amount: gross, net_amount: net, currency: currency,
        occurred_at: occurred, app_name: node.dig('app', 'name'), app_id: app_gid
      )
      sale.save!

      record_billing_event(domain, net, currency, occurred, node['id']) if node['__typename'] == 'AppSubscriptionSale'
      true
    rescue ActiveRecord::RecordNotUnique
      false
    rescue => e
      Rails.logger.warn("[Churn::PartnerSalesSyncJob] persist failed: #{e.message}")
      false
    end

    def record_billing_event(domain, amount, currency, occurred, external_id)
      return if BillingEvent.where(external_id: external_id).exists?
      shop = Shop.find_by(shopify_domain: domain)
      BillingEvent.create!(
        shop_id: shop&.id, shopify_domain: domain,
        event_type: amount.negative? ? 'refund' : 'charge_applied',
        amount: amount, currency: currency, occurred_at: occurred,
        source: 'partner_api', external_id: external_id
      )
    rescue => e
      Rails.logger.warn("[Churn::PartnerSalesSyncJob] billing_event failed: #{e.message}")
    end

    def query(app_gid, start_iso, end_iso, after)
      after_clause = after.present? ? %(after: "#{after}") : ''
      <<~GQL
        {
          transactions(
            first: 100
            #{after_clause}
            appId: "#{app_gid}"
            types: [#{TYPES_FILTER}]
            createdAtMin: "#{start_iso}"
            createdAtMax: "#{end_iso}"
          ) {
            edges {
              cursor
              node {
                __typename
                ... on AppSubscriptionSale { #{FIELDS} }
                ... on AppUsageSale { #{FIELDS} }
                ... on AppSaleAdjustment { #{FIELDS} }
                ... on AppSaleCredit { #{FIELDS} }
              }
            }
            pageInfo { hasNextPage }
          }
        }
      GQL
    end
  end
end

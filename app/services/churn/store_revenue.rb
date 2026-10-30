# frozen_string_literal: true

module Churn
  # Full COD King transaction history for ONE store from the Partner API
  # (filtered by appId + myshopifyDomain), mirrored into partner_sales, with
  # helpers to slice it into LTV / subscription vs usage / trailing revenue.
  #
  #   rev = Churn::StoreRevenue.fetch('foo.myshopify.com')
  #   rev.summary(until_time: reinstall_at)            # LTV up to a cutoff
  #   rev.net_between(churned_at - 30.days, churned_at)
  class StoreRevenue
    SALE_TYPES = {
      'AppSubscriptionSale' => 'subscription',
      'AppUsageSale' => 'usage',
      'AppSaleAdjustment' => 'adjustment',
      'AppSaleCredit' => 'adjustment'
    }.freeze
    TYPES_FILTER = 'APP_SUBSCRIPTION_SALE, APP_USAGE_SALE, APP_SALE_ADJUSTMENT, APP_SALE_CREDIT'
    FIELDS = 'id createdAt chargeId netAmount { amount currencyCode } grossAmount { amount currencyCode }'

    Txn = Struct.new(:id, :sale_type, :occurred_at, :net, :gross, :currency, :charge_id, keyword_init: true)

    attr_reader :domain, :transactions

    def self.fetch(domain, client: PartnerApi::GraphqlClient.new, app_id: nil)
      new(domain, client: client, app_id: app_id).tap(&:load!)
    end

    def initialize(domain, client:, app_id: nil)
      @domain = domain.to_s.downcase
      @client = client
      @app_gid = PartnerApi::GraphqlClient.app_gid(app_id)
      @transactions = []
    end

    def load!
      nodes = @client.fetch_all(path: %w[transactions]) { |cursor| query(cursor) }
      @transactions = nodes.filter_map { |node| to_txn(node) }.sort_by(&:occurred_at)
      mirror_to_partner_sales!
      self
    end

    # Totals for transactions in [from, until_time).
    def summary(from: nil, until_time: nil)
      scope = slice(from, until_time)
      {
        ltv_net: sum(scope),
        subscription_net: sum(scope.select { |t| t.sale_type == 'subscription' }),
        usage_net: sum(scope.select { |t| t.sale_type == 'usage' }),
        adjustment_net: sum(scope.select { |t| t.sale_type == 'adjustment' }),
        first_charge_at: scope.find { |t| t.net.positive? }&.occurred_at,
        last_charge_at: scope.reverse.find { |t| t.net.positive? }&.occurred_at,
        currency: scope.first&.currency || 'USD'
      }
    end

    def net_between(from, until_time, sale_type: nil)
      txns = slice(from, until_time)
      txns = txns.select { |t| t.sale_type == sale_type } if sale_type
      sum(txns)
    end

    private

    def slice(from, until_time)
      @transactions.select do |t|
        (from.nil? || t.occurred_at >= from) && (until_time.nil? || t.occurred_at < until_time)
      end
    end

    def sum(txns)
      txns.sum(0.to_d) { |t| t.net }.round(2)
    end

    def to_txn(node)
      sale_type = SALE_TYPES[node['__typename']]
      return nil unless sale_type && node['id'].present?

      Txn.new(
        id: node['id'],
        sale_type: sale_type,
        occurred_at: Time.zone.parse(node['createdAt'].to_s),
        net: node.dig('netAmount', 'amount').to_d,
        gross: node.dig('grossAmount', 'amount')&.to_d,
        currency: node.dig('netAmount', 'currencyCode'),
        charge_id: node['chargeId']
      )
    rescue ArgumentError, TypeError
      nil
    end

    # Keeps partner_sales (the revenue baseline for churn-rate maths) complete
    # for every store we look at, even outside the hourly sync window.
    def mirror_to_partner_sales!
      @transactions.each do |t|
        sale = PartnerSale.find_or_initialize_by(external_id: t.id)
        sale.assign_attributes(
          shopify_domain: @domain, sale_type: t.sale_type, charge_id: t.charge_id,
          gross_amount: t.gross, net_amount: t.net, currency: t.currency,
          occurred_at: t.occurred_at, app_name: sale.app_name.presence || 'COD King',
          app_id: @app_gid
        )
        sale.save! if sale.changed?
      rescue ActiveRecord::RecordNotUnique
        next
      rescue => e
        Rails.logger.warn("[Churn::StoreRevenue] partner_sales mirror failed #{t.id}: #{e.message}")
      end
    end

    def query(after)
      after_clause = after.present? ? %(after: "#{after}") : ''
      <<~GQL
        {
          transactions(
            first: 100
            #{after_clause}
            appId: "#{@app_gid}"
            myshopifyDomain: "#{@domain}"
            types: [#{TYPES_FILTER}]
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

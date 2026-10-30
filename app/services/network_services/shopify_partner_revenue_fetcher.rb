require 'net/http'
require 'json'
require 'date'

module NetworkServices
  class ShopifyPartnerRevenueFetcher
    # Replace YOUR_ORG_ID with your actual organization ID from Partner Dashboard URL
    DEFAULT_PARTNER_API_VERSION = "2026-04"
    PARTNER_API_BASE = "https://partners.shopify.com/%s/api/%s/graphql.json"
    
    def initialize(partner_access_token, organization_id)
      @partner_access_token = partner_access_token
      @organization_id = organization_id
      @api_version = ENV.fetch("SHOPIFY_PARTNER_API_VERSION", DEFAULT_PARTNER_API_VERSION).to_s.strip
      @graphql_endpoint = format(PARTNER_API_BASE, organization_id, @api_version)
    end
    
    # Main method to get your app earnings from a specific shop in last 30 days
    def get_last_30_days_earnings(shop_domain, app_id = nil)
      shop_domain = shop_domain.gsub(/\.myshopify\.com$/, '')
      
      end_date = Date.today
      start_date = end_date - 30
      
      get_earnings_for_period(shop_domain, start_date, end_date, app_id)
    end
    
    # NEW METHOD: Get earnings for a specific period
    def get_earnings_for_period(shop_domain, start_date, end_date, app_id = nil)
      shop_domain = shop_domain.gsub(/\.myshopify\.com$/, '')
      
      begin
        earnings_data = fetch_app_earnings(shop_domain, start_date, end_date, app_id)
        
        {
          shop_domain: shop_domain,
          success: true,
          data: earnings_data,
          fetched_at: Time.now.iso8601
        }
      rescue => e
        {
          shop_domain: shop_domain,
          success: false,
          error: e.message,
          fetched_at: Time.now.iso8601
        }
      end
    end

    # Get all-time earnings (or a large window) for a shop.
    # Uses cursor pagination to avoid the 100-transaction limit.
    def get_lifetime_earnings(shop_domain, start_date: Date.new(2000, 1, 1), end_date: Date.current, app_id: nil)
      shop_domain = shop_domain.gsub(/\.myshopify\.com$/, '')

      begin
        earnings_data = fetch_app_earnings_paginated(shop_domain, start_date, end_date, app_id)
        {
          shop_domain: shop_domain,
          success: true,
          data: earnings_data,
          fetched_at: Time.now.iso8601
        }
      rescue => e
        {
          shop_domain: shop_domain,
          success: false,
          error: e.message,
          fetched_at: Time.now.iso8601
        }
      end
    end
    
    # Get earnings from multiple partner shops
    def get_multiple_shops_earnings(shop_domains, app_id = nil)
      results = []
      
      shop_domains.each do |domain|
        results << get_last_30_days_earnings(domain, app_id)
      end
      
      # Calculate total earnings across all partners
      total_earnings = results
        .select { |r| r[:success] }
        .sum { |r| r[:data][:total_earnings] }
      
      {
        individual_results: results,
        total_earnings_all_partners: total_earnings.round(2),
        successful_fetches: results.count { |r| r[:success] },
        failed_fetches: results.count { |r| !r[:success] },
        period: 'Last 30 days'
      }
    end
    
    # Calculate referral commission based on earnings
    def get_earnings_with_commission(shop_domain, commission_rate = 0.10, app_id = nil)
      result = get_last_30_days_earnings(shop_domain, app_id)
      
      if result[:success]
        earnings = result[:data][:total_earnings]
        commission = (earnings * commission_rate).round(2)
        
        result[:data][:referral_commission] = {
          commission_rate: (commission_rate * 100).to_i,
          commission_amount: commission,
          based_on_earnings: earnings
        }
      end
      
      result
    end
    
    # Get commission for multiple shops
    def get_multiple_shops_commission(shop_domains, commission_rate = 0.10, app_id = nil)
      results = get_multiple_shops_earnings(shop_domains, app_id)
      
      # Add commission calculation to each successful result
      results[:individual_results].each do |result|
        if result[:success]
          earnings = result[:data][:total_earnings]
          commission = (earnings * commission_rate).round(2)
          
          result[:data][:referral_commission] = {
            commission_rate: (commission_rate * 100).to_i,
            commission_amount: commission,
            based_on_earnings: earnings
          }
        end
      end
      
      # Calculate total commission
      total_commission = results[:individual_results]
        .select { |r| r[:success] }
        .sum { |r| r[:data][:referral_commission][:commission_amount] }
      
      results[:total_commission_all_partners] = total_commission.round(2)
      results[:commission_rate] = (commission_rate * 100).to_i
      
      results
    end
    
    private
    
    def fetch_app_earnings(shop_domain, start_date, end_date, app_id)
      # GraphQL query to get transactions (earnings) from Partner API
      query = build_transactions_query(shop_domain, start_date, end_date, app_id)
      
      response_data = execute_graphql_query(query)
      
      # Process the GraphQL response
      process_transactions_response(response_data, shop_domain)
    end

    def fetch_app_earnings_paginated(shop_domain, start_date, end_date, app_id)
      total_earnings = 0.0
      breakdown = {
        subscription_revenue: 0.0,
        usage_revenue: 0.0,
        one_time_revenue: 0.0,
        transactions_detail: []
      }
      currency = nil
      total_transactions = 0

      cursor = nil
      loop do
        query = build_transactions_query(shop_domain, start_date, end_date, app_id, after: cursor)
        response_data = execute_graphql_query(query)

        chunk = process_transactions_response(response_data, shop_domain)
        total_earnings += chunk[:total_earnings].to_f
        breakdown[:subscription_revenue] += chunk[:breakdown][:subscription_revenue].to_f
        breakdown[:usage_revenue] += chunk[:breakdown][:usage_revenue].to_f
        breakdown[:one_time_revenue] += chunk[:breakdown][:one_time_revenue].to_f
        breakdown[:transactions_detail].concat(chunk[:breakdown][:transactions_detail] || [])
        total_transactions += chunk[:total_transactions].to_i
        currency ||= chunk[:currency]

        page_info = response_data.dig('transactions', 'pageInfo') || {}
        has_next = page_info['hasNextPage'] == true
        break unless has_next

        edges = response_data.dig('transactions', 'edges') || []
        cursor = edges.last&.dig('cursor')
        break if cursor.blank?
      end

      {
        shop_domain: shop_domain,
        total_earnings: total_earnings.round(2),
        period: 'Lifetime',
        breakdown: breakdown,
        total_transactions: total_transactions,
        currency: currency || 'USD'
      }
    end
    
    def build_transactions_query(shop_domain, start_date, end_date, app_id, after: nil)
      # Format dates as ISO 8601 with timezone (UTC)
      start_date_str = start_date.to_time.utc.iso8601
      end_date_str = end_date.to_time.utc.iso8601
      after_clause = after.present? ? %(after: "#{after}") : ""
      
      # Build GraphQL query for transactions with correct Partner API schema
      query = <<~GQL
        {
          transactions(
            first: 100
            #{after_clause}
            createdAtMin: "#{start_date_str}"
            createdAtMax: "#{end_date_str}"
            myshopifyDomain: "#{shop_domain}.myshopify.com"
          ) {
            edges {
              cursor
              node {
                __typename
                id
                createdAt
                ... on AppSubscriptionSale {
                  chargeId
                  app {
                    id
                    name
                  }
                  shop {
                    myshopifyDomain
                    id
                  }
                  netAmount {
                    amount
                    currencyCode
                  }
                }
                ... on AppUsageSale {
                  chargeId
                  app {
                    id
                    name
                  }
                  shop {
                    myshopifyDomain
                    id
                  }
                  netAmount {
                    amount
                    currencyCode
                  }
                }
                ... on AppOneTimeSale {
                  chargeId
                  app {
                    id
                    name
                  }
                  shop {
                    myshopifyDomain
                    id
                  }
                  netAmount {
                    amount
                    currencyCode
                  }
                }
              }
            }
            pageInfo {
              hasNextPage
            }
          }
        }
      GQL
      
      query
    end
    
    def execute_graphql_query(query)
      uri = URI(@graphql_endpoint)
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Post.new(uri)
      request['X-Shopify-Access-Token'] = @partner_access_token
      request['Content-Type'] = 'application/json'
      
      # GraphQL queries are sent as JSON in the request body
      request.body = { query: query }.to_json
      
      response = http.request(request)
      
      unless response.code == '200'
        raise "Failed to fetch transactions: #{response.code} - #{response.body}"
      end
      
      data = JSON.parse(response.body)
      
      # Check for GraphQL errors
      if data['errors'] && !data['errors'].empty?
        error_messages = data['errors'].map { |error| error['message'] }.join(', ')
        raise "GraphQL errors: #{error_messages}"
      end
      
      data['data']
    end
    
    def process_transactions_response(data, shop_domain)
      transactions = data['transactions']['edges'] || []
      
      total_earnings = 0.0
      earnings_breakdown = {
        subscription_revenue: 0.0,
        usage_revenue: 0.0,
        one_time_revenue: 0.0,
        transactions_detail: []
      }
      
      currency = nil
      
      transactions.each do |edge|
        transaction = edge['node']
        transaction_type = transaction['__typename']
        
        # Skip if no netAmount (some transactions might not have this)
        next unless transaction['netAmount']
        
        amount = transaction['netAmount']['amount'].to_f
        transaction_currency = transaction['netAmount']['currencyCode']
        currency ||= transaction_currency
        
        total_earnings += amount
        
        # Categorize by transaction type
        case transaction_type
        when 'AppSubscriptionSale'
          earnings_breakdown[:subscription_revenue] += amount
          transaction_name = 'Subscription'
        when 'AppUsageSale'
          earnings_breakdown[:usage_revenue] += amount
          transaction_name = 'Usage Charge'
        when 'AppOneTimeSale'
          earnings_breakdown[:one_time_revenue] += amount
          transaction_name = 'One-time Charge'
        else
          transaction_name = transaction_type
        end
        
        earnings_breakdown[:transactions_detail] << {
          type: transaction_type.gsub('App', '').gsub('Sale', '').downcase,
          name: transaction_name,
          amount: amount,
          currency: transaction_currency,
          created_at: transaction['createdAt'],
          app_name: transaction.dig('app', 'name'),
          charge_id: transaction['chargeId']
        }
      end
      
      {
        shop_domain: shop_domain,
        total_earnings: total_earnings.round(2),
        period: 'Custom period',
        breakdown: earnings_breakdown,
        total_transactions: earnings_breakdown[:transactions_detail].length,
        currency: currency || 'USD'
      }
    end
  end
end
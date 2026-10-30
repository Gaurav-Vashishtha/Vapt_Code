require 'net/http'
require 'json'

module ShopifyJobs
  class PartialPaymentCleanupJob < ApplicationJob

    # ShopifyJobs::PartialPaymentCleanupJob.perform_async
    
    def perform
      puts 'PartialPaymentCleanupJob started'
      
      total_shops = 0
      processed_shops = 0
      failed_shops = 0
      total_deleted_products = 0
      shop_results = []
      
      # Find all shops with partial payment enabled
      shops = Shop.joins(:setting).where(settings: { partial_payment_enabled: true })
      total_shops = shops.count
      
      puts "Found #{total_shops} shops with partial payment enabled"
      
      shops.each do |shop|
        begin
          puts "\nProcessing shop: #{shop.shopify_domain}"
          
          deleted_count = delete_partial_payment_products(shop)
          
          processed_shops += 1
          total_deleted_products += deleted_count
          
          shop_results << {
            domain: shop.shopify_domain,
            deleted_count: deleted_count,
            status: 'success'
          }
          
          puts "Successfully processed #{shop.shopify_domain} - Deleted #{deleted_count} products"
          
        rescue Exception => e
          failed_shops += 1
          shop_results << {
            domain: shop.shopify_domain,
            deleted_count: 0,
            status: 'failed',
            error: e.message
          }
          
          puts "Failed to process #{shop.shopify_domain}: #{e.message}"
          
          SlackNotifier::CLIENT.ping(
            text: ":warning: Partial Payment Cleanup Job Error (#{Rails.env})\nShop: #{shop.shopify_domain}\nError: #{e.message}\nBacktrace: #{e.backtrace.first(3).join('\n')}"
          )
        end
        
        # Rate limiting between shops
        sleep(1) if shops.count > 1
      end
      
      # Prepare detailed report
      success_shops = shop_results.select { |r| r[:status] == 'success' }
      failed_shops_list = shop_results.select { |r| r[:status] == 'failed' }
      
      success_details = success_shops.map { |s| "#{s[:domain]}: #{s[:deleted_count]} products" }.join('\n')
      failed_details = failed_shops_list.map { |s| "#{s[:domain]}: #{s[:error]}" }.join('\n')
      
      # Send comprehensive Slack report
      report_message = ":broom: Partial Payment Cleanup Job Report (#{Rails.env})\n" +
                      "="*50 + "\n" +
                      "Total Shops: #{total_shops}\n" +
                      "Successfully Processed: #{processed_shops}\n" +
                      "Failed: #{failed_shops}\n" +
                      "Total Products Deleted: #{total_deleted_products}\n\n"
      
      if success_shops.any?
        report_message += "SUCCESS DETAILS:\n#{success_details}\n\n"
      end
      
      if failed_shops_list.any?
        report_message += "FAILED SHOPS:\n#{failed_details}\n"
      end
      
      report_message += "="*50
      
      SlackNotifier::CLIENT.ping(text: report_message)
      
      puts "\n" + "="*60
      puts "CLEANUP JOB SUMMARY:"
      puts "Total shops: #{total_shops}"
      puts "Successfully processed: #{processed_shops}"
      puts "Failed: #{failed_shops}"
      puts "Total products deleted: #{total_deleted_products}"
      puts "="*60
      puts 'PartialPaymentCleanupJob completed'
    end
    
    private
    
    def delete_partial_payment_products(shop)
      api_url = "https://#{shop.shopify_domain}/admin/api/2024-10/graphql.json"
      headers = {
        'Content-Type' => 'application/json',
        'X-Shopify-Access-Token' => shop.shopify_token
      }
      
      # Query to find products with "Partial Payment for" in title
      products_query = <<~GRAPHQL
        query($first: Int!, $after: String, $query: String!) {
          products(first: $first, after: $after, query: $query) {
            edges {
              node {
                id
                title
              }
              cursor
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      GRAPHQL
      
      # Mutation to delete a product
      delete_mutation = <<~GRAPHQL
        mutation productDelete($input: ProductDeleteInput!) {
          productDelete(input: $input) {
            deletedProductId
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
      
      products_to_delete = []
      has_next_page = true
      cursor = nil
      
      puts "Searching for products with 'Partial Payment for' in title using GraphQL..."
      
      # Fetch all matching products with pagination
      while has_next_page
        variables = {
          first: 50,
          query: 'title:*"Partial Payment for"*'
        }
        variables[:after] = cursor if cursor
        
        response = make_graphql_request(api_url, headers, products_query, variables)
        
        if response['errors']
          puts "GraphQL Error: #{response['errors']}"
          break
        end
        
        if response['data'] && response['data']['products']
          products = response['data']['products']['edges']
          products_to_delete.concat(products.map { |edge| edge['node'] })
          
          page_info = response['data']['products']['pageInfo']
          has_next_page = page_info['hasNextPage']
          cursor = page_info['endCursor']
          
          puts "Fetched #{products.count} matching products (cursor: #{cursor})"
        else
          puts "No data returned from GraphQL query"
          break
        end
      end
      
      if products_to_delete.empty?
        puts "No products found with 'Partial Payment for' in title"
        return 0
      end
      
      puts "\nFound #{products_to_delete.count} products to delete:"
      products_to_delete.each_with_index do |product, index|
        puts "  #{index + 1}. ID: #{product['id']}, Title: #{product['title']}"
      end
      
      puts "\nStarting deletion process using GraphQL mutations..."
      
      # Delete each product using GraphQL mutation
      deleted_count = 0
      failed_count = 0
      
      products_to_delete.each_with_index do |product, index|
        variables = {
          input: {
            id: product['id']
          }
        }
        
        response = make_graphql_request(api_url, headers, delete_mutation, variables)
        
        if response['errors']
          failed_count += 1
          puts "✗ [#{index + 1}/#{products_to_delete.count}] GraphQL Error deleting '#{product['title']}': #{response['errors']}"
        elsif response['data'] && response['data']['productDelete']
          user_errors = response['data']['productDelete']['userErrors']
          if user_errors.empty?
            deleted_count += 1
            puts "✓ [#{index + 1}/#{products_to_delete.count}] Deleted: #{product['title']}"
          else
            failed_count += 1
            error_messages = user_errors.map { |error| error['message'] }.join(', ')
            puts "✗ [#{index + 1}/#{products_to_delete.count}] Failed to delete '#{product['title']}': #{error_messages}"
          end
        else
          failed_count += 1
          puts "✗ [#{index + 1}/#{products_to_delete.count}] Unexpected response deleting '#{product['title']}'"
        end
        
        # Rate limiting protection
        sleep(0.5)
      end
      
      puts "\n" + "="*60
      puts "GRAPHQL DELETION SUMMARY FOR #{shop.shopify_domain}:"
      puts "Total found: #{products_to_delete.count}"
      puts "Successfully deleted: #{deleted_count}"
      puts "Failed: #{failed_count}"
      puts "="*60
      
      deleted_count
    end
    
    def make_graphql_request(url, headers, query, variables = {})
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }
      request.body = {
        query: query,
        variables: variables
      }.to_json
      
      response = http.request(request)
      JSON.parse(response.body)
    end
  end
end
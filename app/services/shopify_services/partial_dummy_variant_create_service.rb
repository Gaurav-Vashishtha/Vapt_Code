module ShopifyServices
  class PartialDummyVariantCreateService < ShopifyServices::GraphqlService
    API_VERSION = '2024-10'
    
    attr_reader :shop, :client

    def self.call(shop)
      new(shop).call
    end

    def initialize(shop)
      super() # Call parent constructor with no args
      
      # Input validation
      raise ArgumentError, "Shop cannot be nil" if shop.nil?
      raise ArgumentError, "Shop must have shopify_domain" if shop.shopify_domain.blank?
      raise ArgumentError, "Shop must have shopify_token" if shop.shopify_token.blank?
      
      @shop = shop
      @title = "Partial Payment"
      @price = 0.0
      @option_value_name = "PartPayment"
      
      # Create a proper GraphQL client for 2024-10
      @client = create_graphql_client
    end

    def call
      create_metafield_definition_if_needed

      # Step 1: Create product with options (this creates a default variant)
      product_resp = create_product.to_h

      if product_resp["errors"]&.any?
        errors = product_resp["errors"].map { |e| e["message"] }.join(", ")
        raise StandardError, "GraphQL errors in product creation: #{errors}"
      end

      if product_resp["data"]["productCreate"]["userErrors"]&.any?
        errors = product_resp["data"]["productCreate"]["userErrors"].map { |e| e["message"] }.join(", ")
        raise StandardError, "Failed to create product: #{errors}"
      end

      product = product_resp["data"]["productCreate"]["product"]
      unless product
        raise StandardError, "Product creation returned nil product data"
      end

      product_id = product["id"]
      puts "✅ Created dummy product: #{product_id}"

      # Step 2: Attach metafield BEFORE variant update
      metafield_success = set_metafield_for_product_with_validation(product_id)
      unless metafield_success
        cleanup_failed_product(product_id)
        raise StandardError, "Failed to set required metafield for product #{product_id}"
      end

      # Step 3: Update the default variant that was automatically created
      default_variant_id = get_default_variant_id(product_id)
      unless default_variant_id
        cleanup_failed_product(product_id)
        raise StandardError, "No default variant found for product #{product_id}"
      end

      puts "📦 Found default variant: #{default_variant_id}"

      variant_resp = update_default_variant(default_variant_id, product_id)
      
      if variant_resp["errors"]&.any?
        errors = variant_resp["errors"].map { |e| e["message"] }.join(", ")
        cleanup_failed_product(product_id)
        raise StandardError, "GraphQL errors in variant update: #{errors}"
      end

      if variant_resp.dig("data", "productVariantsBulkUpdate", "userErrors")&.any?
        errors = variant_resp.dig("data", "productVariantsBulkUpdate", "userErrors").map { |e| e["message"] }.join(", ")
        cleanup_failed_product(product_id)
        raise StandardError, "Failed to update variant: #{errors}"
      end
      
      # Extract numeric variant ID
      variant_id = default_variant_id.gsub('gid://shopify/ProductVariant/', '')
      puts "✅ Updated dummy variant: #{variant_id}"

      variant_id

    rescue StandardError => e
      puts "❌ Service failed: #{e.message}"
      raise e
    rescue => e
      puts "🔥 Unexpected error: #{e.class} - #{e.message}"
      raise StandardError, "Unexpected error in PartialDummyVariantCreateService: #{e.message}"
    end

    private

    def create_graphql_client
      begin
        GraphQLClient.new(
          shop_domain: @shop.shopify_domain,
          access_token: @shop.shopify_token,
          api_version: API_VERSION
        )
      rescue NameError
        begin
          GraphQLClientFactory.create(
            shop: @shop,
            api_version: API_VERSION
          )
        rescue NameError
          puts "📡 Creating GraphQL client for #{API_VERSION} API"
          SimpleGraphQLClient.new(@shop, API_VERSION)
        end
      end
    rescue => e
      puts "🔥 Failed to create GraphQL client: #{e.message}"
      raise StandardError, "Could not initialize GraphQL client: #{e.message}"
    end

    # Simple GraphQL client for 2024-10 API
    class SimpleGraphQLClient
      def initialize(shop, api_version)
        @shop = shop
        @api_version = api_version
        @endpoint = "https://#{shop.shopify_domain}/admin/api/#{api_version}/graphql.json"
        
        unless shop.shopify_token
          raise StandardError, "Shop access token is missing"
        end
      end

      def parse(query_string)
        GraphQLQuery.new(query_string, @endpoint, @shop.shopify_token)
      end

      def query(query_obj, variables: {})
        query_obj.execute(variables)
      end
    end

    # Simple query executor
    class GraphQLQuery
      def initialize(query_string, endpoint, token)
        @query_string = query_string
        @endpoint = endpoint
        @token = token
      end

      def execute(variables = {})
        require 'net/http'
        require 'json'
        
        uri = URI(@endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-Shopify-Access-Token'] = @token
        request.body = {
          query: @query_string,
          variables: variables
        }.to_json

        response = http.request(request)
        
        unless response.code.start_with?('2')
          raise StandardError, "HTTP #{response.code}: #{response.message}"
        end
        
        JSON.parse(response.body)
        
      rescue Net::TimeoutError => e
        raise StandardError, "Request timeout: #{e.message}"
      rescue JSON::ParserError => e
        raise StandardError, "Invalid JSON response: #{e.message}"
      rescue => e
        raise StandardError, "GraphQL request failed: #{e.message}"
      end

      def to_h
        self
      end
    end

    def create_metafield_definition_if_needed
      mutation = @client.parse <<-'GRAPHQL'
        mutation($definition: MetafieldDefinitionInput!) {
          metafieldDefinitionCreate(definition: $definition) {
            createdDefinition {
              id
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
    
      variables = {
        definition: {
          name: "CODK Hide Product",
          namespace: "seo",
          key: "hidden",
          type: "number_integer",
          ownerType: "PRODUCT"
        }
      }
    
      response = @client.query(mutation, variables: variables).to_h
      errors = response.dig("data", "metafieldDefinitionCreate", "userErrors")
    
      if errors&.any?
        messages = errors.map { |e| e["message"] }
        if messages.include?("Key has already been taken")
          puts "ℹ️ Metafield definition already exists"
        else
          puts "❌ Metafield definition creation failed: #{messages.join(', ')}"
        end
      else
        puts "✅ Metafield definition created successfully"
      end
    end

    def set_metafield_for_product_with_validation(product_id)
      mutation = @client.parse <<-'GRAPHQL'
        mutation($metafields: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $metafields) {
            metafields {
              id
              namespace
              key
              value
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
    
      variables = {
        metafields: [
          {
            ownerId: product_id,
            namespace: "seo",
            key: "hidden",
            type: "number_integer",
            value: "1"
          }
        ]
      }
    
      response = @client.query(mutation, variables: variables).to_h
      errors = response.dig("data", "metafieldsSet", "userErrors")
    
      if errors&.any?
        messages = errors.map { |e| e["message"] }.join(", ")
        puts "❌ Failed to set metafield: #{messages}"
        return false
      else
        puts "✅ Metafield seo.hidden = 1 successfully set for product #{product_id}"
        return true
      end
    end

    def cleanup_failed_product(product_id)
      return if product_id.blank?
      
      puts "🧹 Cleaning up failed product: #{product_id}"
      
      mutation = @client.parse <<-'GRAPHQL'
        mutation($input: ProductDeleteInput!) {
          productDelete(input: $input) {
            deletedProductId
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        input: {
          id: product_id
        }
      }

      response = @client.query(mutation, variables: variables).to_h
      
      if response.dig("data", "productDelete", "userErrors")&.any?
        errors = response.dig("data", "productDelete", "userErrors").map { |e| e["message"] }.join(", ")
        puts "⚠️ Failed to cleanup product #{product_id}: #{errors}"
      else
        puts "✅ Successfully cleaned up failed product: #{product_id}"
      end
      
    rescue => e
      puts "⚠️ Error during cleanup of product #{product_id}: #{e.message}"
    end

    def create_product
      query = @client.parse <<-'GRAPHQL'
        mutation ($input: ProductInput!) {
          productCreate(input: $input) {
            product {
              id
              options {
                id
                name
                values
                optionValues {
                  id
                }
              }
              metafields(first: 3) {
                edges {
                  node {
                    id
                    namespace
                    key
                    value
                  }
                }
              }
            }
            userErrors {
              message
              field
            }
          }
        }
      GRAPHQL

      # Create product with options - this will create a default variant
      variables = {
        input: {
          title: @title,
          published: true,
          productOptions: [
            {
              name: "Payment Type",
              values: [
                { name: @option_value_name }
              ]
            }
          ]
        }
      }

      @client.query(query, variables: variables)
    end

    def get_default_variant_id(product_id)
      query = @client.parse <<-'GRAPHQL'
        query($id: ID!) {
          product(id: $id) {
            variants(first: 1) {
              nodes {
                id
                title
                selectedOptions {
                  name
                  value
                }
              }
            }
          }
        }
      GRAPHQL

      variables = { id: product_id }
      response = @client.query(query, variables: variables).to_h
      
      if response["errors"]&.any?
        puts "❌ GraphQL errors while fetching variant: #{response["errors"].map { |e| e["message"] }.join(", ")}"
        return nil
      end
      
      variant_id = response.dig("data", "product", "variants", "nodes")&.first&.dig("id")
      
      unless variant_id
        puts "❌ No variants found for product #{product_id}"
      end
      
      variant_id
    rescue => e
      puts "🔥 Error fetching default variant: #{e.message}"
      nil
    end

    def update_default_variant(variant_id, product_id)
      query = @client.parse <<-'GRAPHQL'
        mutation($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkUpdate(productId: $productId, variants: $variants) {
            productVariants {
              id
              price
              title
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      # Price is 0.00 for dummy variant
      price_decimal = "0.00"

      variables = {
        productId: product_id,
        variants: [
          {
            id: variant_id,
            price: price_decimal
          }
        ]
      }

      puts "🔄 Updating dummy variant #{variant_id} with price: #{price_decimal}"
      
      @client.query(query, variables: variables).to_h

    rescue => e
      puts "🔥 Error updating variant: #{e.message}"
      { "errors" => [{ "message" => e.message }] }
    end
  end
end


module ShopifyServices
  class PartialProductCreateService < ShopifyServices::GraphqlService
    API_VERSION = '2024-10'
    
    attr_reader :shop, :client

    def self.call(shop, title, price, variant_ids, image_url, original_price, session_id: nil, cart_hash: nil, cart_rule_id: nil, create_inventory: false)
      new(shop, title, price, variant_ids, image_url, original_price, session_id, cart_hash, cart_rule_id, create_inventory).call
    end

    def initialize(shop, title, price, variant_ids, imageUrl, original_price, session_id = nil, cart_hash = nil, cart_rule_id = nil, create_inventory = false)
      super() # Call parent constructor with no args
      
      # ✅ Input validation
      validate_inputs!(shop, title, price, variant_ids, original_price, cart_rule_id)
      
      @shop = shop
      @title = title
      @price = sanitize_price(price)
      @existing_variant_ids = variant_ids
      @imageUrl = imageUrl
      @originalPrice = sanitize_price(original_price)
      @session_id = session_id
      @cart_hash = cart_hash
      @cart_rule_id = cart_rule_id || 0
      @option_value_name = "Partial Payment"
      
      # ✅ Inventory settings - simplified to boolean
    
      auto_inventory_domains = get_auto_inventory_domains
      if auto_inventory_domains.include?(@shop.shopify_domain)
        create_inventory = true
        @create_inventory = true
        puts "🏪 Auto-enabling inventory for domain: #{@shop.shopify_domain}"
      end

      @track_inventory = create_inventory # Only track if we're creating inventory
      
      puts "📦 Inventory settings - Create inventory: #{@create_inventory}"
      
      # ✅ Get rule information for validation context
      @rule_set = fetch_rule_set(cart_rule_id)
      
      # Create a proper GraphQL client for 2024-10
      @client = create_graphql_client
    end


    def get_auto_inventory_domains
      domains_env = ENV.fetch("AUTO_INVENTORY_DOMAINS", nil) || ''
      
      # Split by comma and clean up whitespace
      domains = domains_env.split(',').map(&:strip).reject(&:empty?)
      
      # Log the domains for debugging (but don't log if empty)
      if domains.any?
        puts "🔧 Auto-inventory domains configured: #{domains.join(', ')}"
      end
      
      domains
    rescue => e
      puts "⚠️ Error reading AUTO_INVENTORY_DOMAINS: #{e.message}"
      []
    end


    def call
      # ✅ Enhanced validation that considers rule context
      validate_price_with_rule_context!
      
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
      puts "✅ Created product: #{product_id}"
      
      # Log media creation if image was provided
      if product["media"] && product["media"]["nodes"]&.any?
        media_count = product["media"]["nodes"].length
        puts "🖼️ Successfully added #{media_count} media item(s) to product"
      elsif @imageUrl && !@imageUrl.empty?
        puts "⚠️ Image was provided but no media found in product response"
      end

      # Step 2: ✅ CRITICAL - Attach metafield BEFORE variant update with error handling
      metafield_success = set_metafield_for_product_with_validation(product_id)
      unless metafield_success
        # Clean up the created product and fail
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
      
      # ✅ Validate the variant was actually updated with correct price (allowing 0 for valid rules)
      variant_id = default_variant_id.gsub('gid://shopify/ProductVariant/', '')
      validate_variant_price_with_rule_context(variant_id, product_id)
      
      puts "✅ Updated variant: #{variant_id}"

      save_partial_product_mapping(product_id, variant_id) unless variant_id.blank?
      variant_id

    rescue StandardError => e
      puts "❌ Service failed: #{e.message}"
      raise e
    rescue => e
      puts "🔥 Unexpected error: #{e.class} - #{e.message}"
      raise StandardError, "Unexpected error in PartialProductCreateService: #{e.message}"
    end

    private

    # ✅ Input validation methods
    def validate_inputs!(shop, title, price, variant_ids, original_price, cart_rule_id)
      raise ArgumentError, "Shop cannot be nil" if shop.nil?
      raise ArgumentError, "Shop must have shopify_domain" if shop.shopify_domain.blank?
      raise ArgumentError, "Shop must have shopify_token" if shop.shopify_token.blank?
      raise ArgumentError, "Title cannot be blank" if title.blank?
      raise ArgumentError, "Price cannot be nil" if price.nil?
      raise ArgumentError, "Original price cannot be nil" if original_price.nil?
      raise ArgumentError, "Variant IDs cannot be blank" if variant_ids.blank?
      
      puts "✅ Basic input validation passed"
    end

    def fetch_rule_set(cart_rule_id)
      return nil if cart_rule_id.nil? || cart_rule_id == 0
      
      begin
        rule_set = PartialRuleSet.find_by(id: cart_rule_id)
        if rule_set
          puts "📋 Found rule set: #{rule_set.rule_name} (amount: #{rule_set.amount}, type: #{rule_set.amount_type})"
        else
          puts "⚠️ Rule set not found for ID: #{cart_rule_id}"
        end
        rule_set
      rescue => e
        puts "⚠️ Error fetching rule set: #{e.message}"
        nil
      end
    end

    def sanitize_price(price)
      return 0 if price.nil?
      
      # Handle string prices
      if price.is_a?(String)
        # Remove currency symbols and clean
        cleaned_price = price.gsub(/[^\d.]/, '')
        return 0 if cleaned_price.blank?
        price = cleaned_price.to_f
      end
      
      # Convert to float and ensure non-negative
      price = price.to_f
      price < 0 ? 0 : price
    end

    # ✅ Enhanced price validation that considers rule context
    def validate_price_with_rule_context!
      # ✅ Case 1: Rule specifically allows $0 (amount = 0 in rule)
      if @rule_set && @rule_set.amount.to_f == 0
        puts "💰 Rule allows $0 payment - Price validation: Partial: #{@price}, Original: #{@originalPrice}, Rule: #{@rule_set.rule_name}"
        
        # For $0 rules, we still need a valid original price
        if @originalPrice <= 0
          raise StandardError, "Invalid original price for $0 rule: #{@originalPrice}. Original price must be greater than 0"
        end
        
        # Set price to exact 0 for $0 rules
        @price = 0.0
        puts "✅ $0 rule validation passed - Setting price to exactly $0.00"
        return
      end

      # ✅ Case 2: Rule with percentage = 0% (free partial payment)
      if @rule_set && @rule_set.amount_type == 'percentage' && @rule_set.amount.to_f == 0
        puts "💰 Rule allows 0% payment - Price validation: Partial: #{@price}, Original: #{@originalPrice}, Rule: #{@rule_set.rule_name}"
        
        if @originalPrice <= 0
          raise StandardError, "Invalid original price for 0% rule: #{@originalPrice}. Original price must be greater than 0"
        end
        
        # Set price to exact 0 for 0% rules
        @price = 0.0
        puts "✅ 0% rule validation passed - Setting price to exactly $0.00"
        return
      end

      # ✅ Case 3: Rule with fixed amount = 0 (free partial payment)
      if @rule_set && @rule_set.amount_type == 'fixed' && @rule_set.amount.to_f == 0
        puts "💰 Rule allows fixed $0 payment - Price validation: Partial: #{@price}, Original: #{@originalPrice}, Rule: #{@rule_set.rule_name}"
        
        if @originalPrice <= 0
          raise StandardError, "Invalid original price for fixed $0 rule: #{@originalPrice}. Original price must be greater than 0"
        end
        
        # Set price to exact 0 for fixed $0 rules
        @price = 0.0
        puts "✅ Fixed $0 rule validation passed - Setting price to exactly $0.00"
        return
      end

      # ✅ Case 4: Regular rules - price must be > 0
      if @price <= 0
        raise StandardError, "Invalid price for partial product: #{@price}. Must be greater than 0 for non-zero rules"
      end
      
      if @originalPrice <= 0
        raise StandardError, "Invalid original price for partial product: #{@originalPrice}. Must be greater than 0"
      end
      
      puts "💰 Regular rule validation passed - Partial: #{@price}, Original: #{@originalPrice}"
    end

    # ✅ Enhanced metafield setting with validation
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
        
        # ✅ Send alert for metafield failures
        SlackNotifyJob.perform_async(
          ":warning: Metafield Setting Failed (#{Rails.env})\n" \
          "🛍️ Shop: #{@shop.shopify_domain}\n" \
          "📦 Product: #{product_id}\n" \
          "💥 Error: #{messages}\n" \
          "🧾 Session: #{@session_id}\n" \
          "📋 Rule: #{@rule_set&.rule_name || 'N/A'}"
        )
        
        return false
      else
        puts "✅ Metafield seo.hidden = 1 successfully set for product #{product_id}"
        return true
      end
    end

    # ✅ Enhanced variant price validation that considers rule context
    def validate_variant_price_with_rule_context(variant_id, product_id)
      query = @client.parse <<-'GRAPHQL'
        query($id: ID!) {
          productVariant(id: $id) {
            id
            price
            product {
              id
            }
          }
        }
      GRAPHQL

      gql_variant_id = "gid://shopify/ProductVariant/#{variant_id}"
      variables = { id: gql_variant_id }
      response = @client.query(query, variables: variables).to_h
      
      if response["errors"]&.any?
        puts "⚠️ Could not validate variant price: #{response["errors"].map { |e| e["message"] }.join(", ")}"
        return
      end
      
      variant = response.dig("data", "productVariant")
      unless variant
        puts "⚠️ Variant not found for validation: #{variant_id}"
        return
      end
      
      actual_price = variant["price"].to_f
      expected_price = @price.to_f
      
      # ✅ For $0 rules, allow exact $0.00 price
      if @rule_set && (@rule_set.amount.to_f == 0 || (@rule_set.amount_type == 'percentage' && @rule_set.amount.to_f == 0))
        if expected_price == 0.0 && actual_price == 0.0
          puts "✅ $0 rule price validation passed: $0.00 (Rule: #{@rule_set.rule_name})"
          return
        elsif expected_price == 0.0 && actual_price != 0.0
          error_msg = "$0 rule price mismatch - Expected: $0.00, Actual: $#{actual_price}"
          puts "❌ #{error_msg}"
          
          SlackNotifyJob.perform_async(
            ":zero: $0 Rule Price Validation Failed (#{Rails.env})\n" \
            "🛍️ Shop: #{@shop.shopify_domain}\n" \
            "📦 Product: #{product_id}\n" \
            "🔖 Variant: #{variant_id}\n" \
            "💰 Expected: $0.00, Actual: $#{actual_price}\n" \
            "📋 Rule: #{@rule_set.rule_name} (amount: #{@rule_set.amount})\n" \
            "🧾 Session: #{@session_id}"
          )
          
          raise StandardError, error_msg
        end
      end
      
      # ✅ For regular rules, ensure prices match and are > 0
      if actual_price != expected_price
        error_msg = "Price mismatch - Expected: $#{expected_price}, Actual: $#{actual_price}"
        puts "❌ #{error_msg}"
        
        SlackNotifyJob.perform_async(
          ":moneybag: Price Validation Failed (#{Rails.env})\n" \
          "🛍️ Shop: #{@shop.shopify_domain}\n" \
          "📦 Product: #{product_id}\n" \
          "🔖 Variant: #{variant_id}\n" \
          "💰 Expected: $#{expected_price}, Actual: $#{actual_price}\n" \
          "📋 Rule: #{@rule_set&.rule_name || 'N/A'}\n" \
          "🧾 Session: #{@session_id}"
        )
        
        raise StandardError, error_msg
      else
        puts "✅ Price validation passed: $#{actual_price}"
      end
    end

    # ✅ Cleanup method for failed products
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

    def create_graphql_client
      begin
        # Try different client creation approaches based on your setup
        GraphQLClient.new(
          shop_domain: @shop.shopify_domain,
          access_token: @shop.shopify_token,
          api_version: API_VERSION
        )
      rescue NameError
        begin
          # Approach 2: If you have a GraphQL client factory
          GraphQLClientFactory.create(
            shop: @shop,
            api_version: API_VERSION
          )
        rescue NameError
          # Approach 3: Create a simple client wrapper
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
    
    def create_product
      query = @client.parse <<-'GRAPHQL'
        mutation ($input: ProductInput!, $media: [CreateMediaInput!]) {
          productCreate(input: $input, media: $media) {
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
              media(first: 5) {
                nodes {
                  id
                  mediaContentType
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
          title: @title, # Use the original title as passed
          published: true,
          productOptions: [
            {
              name: "Payment Type",
              values: [
                { name: @option_value_name } # Clean "Partial Payment"
              ]
            }
          ]
        }
      }

      # Add media if image URL is provided
      if @imageUrl && !@imageUrl.empty?
        variables[:media] = [
          {
            originalSource: @imageUrl,
            mediaContentType: "IMAGE"
          }
        ]
        puts "🖼️ Adding image to product: #{@imageUrl}"
      end

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
        puts "Response: #{response.inspect}"
      end
      
      variant_id
    rescue => e
      puts "🔥 Error fetching default variant: #{e.message}"
      nil
    end

    # Enhanced variant update with inventory support
    def update_default_variant(variant_id, product_id)
      query = @client.parse <<-'GRAPHQL'
        mutation($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkUpdate(productId: $productId, variants: $variants) {
            productVariants {
              id
              price
              title
              inventoryItem {
                id
                tracked
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      # ✅ Enhanced price formatting that properly handles $0
      price_decimal = format_price_for_shopify(@price)

      variables = {
        productId: product_id,
        variants: [
          {
            id: variant_id,
            price: price_decimal,
            inventoryItem: {
              tracked: @track_inventory # Only track if create_inventory is true
            }
          }
        ]
      }

      rule_info = @rule_set ? " (Rule: #{@rule_set.rule_name})" : ""
      puts "🔄 Updating variant #{variant_id} with price: #{price_decimal} (from #{@price})#{rule_info}"
      puts "📦 Product ID: #{product_id}, Inventory tracking: #{@track_inventory}"
      
      response = @client.query(query, variables: variables).to_h
      
      # Set inventory quantity if create_inventory is enabled and quantity is provided
      if @create_inventory && response.dig("data", "productVariantsBulkUpdate", "productVariants")&.any?
        updated_variant = response.dig("data", "productVariantsBulkUpdate", "productVariants").first
        inventory_item_id = updated_variant.dig("inventoryItem", "id")
        
        # Store variant ID for potential REST fallback
        @last_created_variant_id = variant_id
        
        if inventory_item_id
          # Default to 10000 inventory when tracking is enabled
          set_inventory_quantity(inventory_item_id, 10000)
        else
          puts "⚠️ No inventory item ID found for variant #{variant_id}"
          puts "🔄 Trying REST API fallback for inventory..."
          set_inventory_quantity_rest(variant_id, 10000)
        end
      elsif @create_inventory
        puts "⚠️ Inventory creation requested but variant update failed"
      else
        puts "📦 Inventory creation skipped - create_inventory: #{@create_inventory}"
      end
      
      # Log the response to debug price setting
      if response.dig("data", "productVariantsBulkUpdate", "productVariants")&.any?
        updated_variant = response.dig("data", "productVariantsBulkUpdate", "productVariants").first
        puts "✅ Variant updated - Price: #{updated_variant["price"]}, Title: #{updated_variant["title"]}"
      end
      
      # Handle image separately if provided and not already added during product creation
      if @imageUrl && !@imageUrl.empty? && !product_has_media(product_id)
        handle_variant_image(variant_id, product_id)
      end
      
      response

    rescue => e
      puts "🔥 Error updating variant: #{e.message}"
      { "errors" => [{ "message" => e.message }] }
    end

    # ✅ Enhanced price formatting that handles $0 correctly
    def format_price_for_shopify(price)
      # Ensure we have a valid number
      numeric_price = price.to_f
      
      # ✅ Allow $0.00 for valid $0 rules
      if @rule_set && (@rule_set.amount.to_f == 0 || (@rule_set.amount_type == 'percentage' && @rule_set.amount.to_f == 0))
        if numeric_price == 0.0
          puts "💰 Formatting $0.00 price for rule: #{@rule_set.rule_name}"
          return "0.00"
        end
      end
      
      # ✅ For regular rules, validate minimum price
      if numeric_price < 0.01
        raise StandardError, "Price too low: #{numeric_price}. Minimum is $0.01 for non-zero rules"
      end
      
      # Format to 2 decimal places for Shopify
      sprintf("%.2f", numeric_price)
    end

    # New method to set inventory quantity using correct 2024-10 API mutations
    def set_inventory_quantity(inventory_item_id, quantity)
      # First, get the location ID (usually the primary location)
      location_id = get_primary_location_id
      return unless location_id

      # Use inventorySetOnHandQuantities for 2024-10 API (most reliable for setting absolute quantities)
      mutation = @client.parse <<-'GRAPHQL'
        mutation($input: InventorySetOnHandQuantitiesInput!) {
          inventorySetOnHandQuantities(input: $input) {
            inventoryAdjustmentGroup {
              id
              reason
              createdAt
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        input: {
          reason: "correction",
          setQuantities: [
            {
              inventoryItemId: inventory_item_id,
              locationId: location_id,
              quantity: quantity
            }
          ]
        }
      }

      puts "📦 Setting inventory quantity: #{quantity} for item #{inventory_item_id} at location #{location_id}"
      puts "🔍 Using inventorySetOnHandQuantities mutation (2024-10 API)"
      
      response = @client.query(mutation, variables: variables).to_h
      
      if response["errors"]&.any?
        puts "❌ GraphQL errors setting inventory: #{response["errors"].map { |e| e["message"] }.join(", ")}"
        # Try the alternative inventorySetQuantities mutation
        puts "🔄 Trying inventorySetQuantities mutation..."
        set_inventory_quantity_alternative(inventory_item_id, quantity, location_id)
      elsif response.dig("data", "inventorySetOnHandQuantities", "userErrors")&.any?
        errors = response.dig("data", "inventorySetOnHandQuantities", "userErrors").map { |e| e["message"] }.join(", ")
        puts "❌ Failed to set inventory: #{errors}"
        
        # Try the alternative inventorySetQuantities mutation
        puts "🔄 Trying inventorySetQuantities mutation..."
        set_inventory_quantity_alternative(inventory_item_id, quantity, location_id)
      else
        adjustment_group = response.dig("data", "inventorySetOnHandQuantities", "inventoryAdjustmentGroup")
        if adjustment_group
          puts "✅ Inventory set successfully - Adjustment ID: #{adjustment_group["id"]}"
          
          # Verify the inventory was actually set
          verify_inventory_set(inventory_item_id, quantity, location_id)
        end
      end

    rescue => e
      puts "🔥 Error setting inventory quantity: #{e.message}"
      puts "🔄 Trying inventorySetQuantities mutation..."
      set_inventory_quantity_alternative(inventory_item_id, quantity, location_id)
    end

    # Alternative method using inventorySetQuantities
    def set_inventory_quantity_alternative(inventory_item_id, quantity, location_id)
      mutation = @client.parse <<-'GRAPHQL'
        mutation($input: InventorySetQuantitiesInput!) {
          inventorySetQuantities(input: $input) {
            inventoryAdjustmentGroup {
              id
              reason
              createdAt
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        input: {
          name: "available",
          reason: "correction",
          ignoreCompareQuantity: true,
          quantities: [
            {
              inventoryItemId: inventory_item_id,
              locationId: location_id,
              quantity: quantity
            }
          ]
        }
      }

      puts "📦 Alternative: Setting inventory using inventorySetQuantities"
      
      response = @client.query(mutation, variables: variables).to_h
      
      if response["errors"]&.any?
        puts "❌ Alternative GraphQL errors: #{response["errors"].map { |e| e["message"] }.join(", ")}"
        
        # Final fallback - try REST API
        puts "🔄 Final fallback: Trying REST API..."
        set_inventory_quantity_rest(inventory_item_id, quantity, location_id)
      elsif response.dig("data", "inventorySetQuantities", "userErrors")&.any?
        errors = response.dig("data", "inventorySetQuantities", "userErrors").map { |e| e["message"] }.join(", ")
        puts "❌ Alternative failed: #{errors}"
        
        # Final fallback - try REST API
        puts "🔄 Final fallback: Trying REST API..."
        set_inventory_quantity_rest(inventory_item_id, quantity, location_id)
      else
        adjustment_group = response.dig("data", "inventorySetQuantities", "inventoryAdjustmentGroup")
        if adjustment_group
          puts "✅ Alternative inventory set successfully - Adjustment ID: #{adjustment_group["id"]}"
          
          # Verify the inventory was actually set
          verify_inventory_set(inventory_item_id, quantity, location_id)
        end
      end
    rescue => e
      puts "🔥 Alternative method error: #{e.message}"
      puts "🔄 Final fallback: Trying REST API..."
      set_inventory_quantity_rest(inventory_item_id, quantity, location_id)
    end

    # Verify inventory was actually set
    def verify_inventory_set(inventory_item_id, expected_quantity, location_id)
      query = @client.parse <<-'GRAPHQL'
        query($id: ID!) {
          inventoryItem(id: $id) {
            id
            inventoryLevels(first: 5) {
              nodes {
                id
                available
                location {
                  id
                  name
                }
              }
            }
          }
        }
      GRAPHQL

      response = @client.query(query, variables: { id: inventory_item_id }).to_h
      
      if response.dig("data", "inventoryItem", "inventoryLevels", "nodes")
        levels = response.dig("data", "inventoryItem", "inventoryLevels", "nodes")
        target_level = levels.find { |level| level.dig("location", "id") == location_id }
        
        if target_level
          actual_quantity = target_level["available"]
          location_name = target_level.dig("location", "name")
          
          puts "🔍 Verification - Expected: #{expected_quantity}, Actual: #{actual_quantity} at #{location_name}"
          
          if actual_quantity == expected_quantity
            puts "✅ Inventory verification successful!"
          else
            puts "⚠️ Inventory mismatch detected!"
          end
        else
          puts "⚠️ Could not find inventory level for location #{location_id}"
        end
      end
    rescue => e
      puts "⚠️ Could not verify inventory: #{e.message}"
    end

    # Method to get the primary location ID with REST fallback
    def get_primary_location_id
      # Try GraphQL first
      begin
        query = @client.parse <<-'GRAPHQL'
          query {
            locations(first: 1) {
              nodes {
                id
                name
                isPrimary
              }
            }
          }
        GRAPHQL

        response = @client.query(query).to_h
        
        if response["errors"]&.any?
          error_msg = response["errors"].map { |e| e["message"] }.join(", ")
          puts "❌ GraphQL errors fetching locations: #{error_msg}"
          
          # Check if it's a permission error
          if error_msg.include?("Access denied") || error_msg.include?("locations field")
            puts "🔄 Permission issue detected, falling back to REST API..."
            return get_primary_location_id_rest
          end
          return nil
        end
        
        locations = response.dig("data", "locations", "nodes")
        if locations&.any?
          primary_location = locations.first
          puts "📍 Using location (GraphQL): #{primary_location["name"]} (#{primary_location["id"]})"
          return primary_location["id"]
        else
          puts "❌ No locations found for shop"
          return nil
        end

      rescue => e
        puts "🔥 Error fetching location via GraphQL: #{e.message}"
        puts "🔄 Falling back to REST API..."
        return get_primary_location_id_rest
      end
    end

    # REST API fallback for getting location
    def get_primary_location_id_rest
      require 'net/http'
      require 'json'
      
      begin
        url = "https://#{@shop.shopify_domain}/admin/api/#{API_VERSION}/locations.json"
        uri = URI(url)
        
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        request = Net::HTTP::Get.new(uri)
        request['X-Shopify-Access-Token'] = @shop.shopify_token
        
        response = http.request(request)
        
        if response.code == '200'
          data = JSON.parse(response.body)
          locations = data['locations']
          
          if locations&.any?
            # Find primary location or use first one
            primary_location = locations.find { |loc| loc['primary'] } || locations.first
            location_id = "gid://shopify/Location/#{primary_location['id']}"
            
            puts "📍 Using location (REST): #{primary_location['name']} (#{location_id})"
            return location_id
          else
            puts "❌ No locations found via REST API"
            return nil
          end
        else
          puts "❌ REST API error: #{response.code} - #{response.message}"
          return nil
        end
        
      rescue => e
        puts "🔥 Error with REST API fallback: #{e.message}"
        return nil
      end
    end

    # REST API fallback method
    def set_inventory_quantity_rest(inventory_item_id, quantity, location_id)
      require 'net/http'
      require 'json'
      
      begin
        # Extract numeric IDs from GraphQL IDs
        numeric_inventory_item_id = inventory_item_id.gsub('gid://shopify/InventoryItem/', '')
        numeric_location_id = location_id.gsub('gid://shopify/Location/', '')
        
        # Use REST API to set inventory level
        url = "https://#{@shop.shopify_domain}/admin/api/#{API_VERSION}/inventory_levels/set.json"
        uri = URI(url)
        
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-Shopify-Access-Token'] = @shop.shopify_token
        
        request.body = {
          location_id: numeric_location_id.to_i,
          inventory_item_id: numeric_inventory_item_id.to_i,
          available: quantity
        }.to_json
        
        puts "📦 REST API: Setting inventory #{quantity} for item #{numeric_inventory_item_id} at location #{numeric_location_id}"
        
        response = http.request(request)
        
        if response.code == '200'
          result = JSON.parse(response.body)
          available = result.dig('inventory_level', 'available')
          puts "✅ REST API inventory set successfully - Available: #{available}"
        else
          puts "❌ REST API failed: #{response.code} - #{response.body}"
        end
        
      rescue => e
        puts "🔥 REST API error: #{e.message}"
      end
    end

    # Alternative method using inventorySetQuantities (bulk operation)
    def set_inventory_quantity_bulk(inventory_item_id, quantity)
      location_id = get_primary_location_id
      return unless location_id

      mutation = @client.parse <<-'GRAPHQL'
        mutation($input: InventorySetQuantitiesInput!) {
          inventorySetQuantities(input: $input) {
            inventoryAdjustmentGroup {
              id
              reason
              createdAt
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        input: {
          reason: "correction", # or "received_items", "sold", etc.
          setQuantities: [
            {
              inventoryItemId: inventory_item_id,
              locationId: location_id,
              quantity: quantity
            }
          ]
        }
      }

      puts "📦 Setting inventory quantity (bulk): #{quantity} for item #{inventory_item_id}"
      
      response = @client.query(mutation, variables: variables).to_h
      
      if response["errors"]&.any?
        puts "❌ GraphQL errors setting inventory (bulk): #{response["errors"].map { |e| e["message"] }.join(", ")}"
      elsif response.dig("data", "inventorySetQuantities", "userErrors")&.any?
        errors = response.dig("data", "inventorySetQuantities", "userErrors").map { |e| e["message"] }.join(", ")
        puts "❌ Failed to set inventory (bulk): #{errors}"
      else
        adjustment_group = response.dig("data", "inventorySetQuantities", "inventoryAdjustmentGroup")
        if adjustment_group
          puts "✅ Inventory set successfully (bulk) - Adjustment ID: #{adjustment_group["id"]}"
        end
      end

    rescue => e
      puts "🔥 Error setting inventory quantity (bulk): #{e.message}"
    end

    def product_has_media(product_id)
      # Check if product already has media (to avoid duplicate image handling)
      query = @client.parse <<-'GRAPHQL'
        query($id: ID!) {
          product(id: $id) {
            media(first: 1) {
              nodes {
                id
              }
            }
          }
        }
      GRAPHQL

      variables = { id: product_id }
      response = @client.query(query, variables: variables).to_h
      
      media_count = response.dig("data", "product", "media", "nodes")&.length || 0
      media_count > 0
    rescue => e
      puts "⚠️ Error checking product media: #{e.message}"
      false
    end

    def handle_variant_image(variant_id, product_id)
      # Add image to product using productCreateMedia mutation
      query = @client.parse <<-'GRAPHQL'
        mutation($productId: ID!, $media: [CreateMediaInput!]!) {
          productCreateMedia(productId: $productId, media: $media) {
            media {
              id
              mediaContentType
              status
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        productId: product_id,
        media: [
          {
            originalSource: @imageUrl,
            mediaContentType: "IMAGE"
          }
        ]
      }

      puts "🖼️ Adding image to product via productCreateMedia: #{@imageUrl}"
      response = @client.query(query, variables: variables).to_h

      if response["errors"]&.any?
        puts "❌ GraphQL errors adding image: #{response["errors"].map { |e| e["message"] }.join(", ")}"
      elsif response.dig("data", "productCreateMedia", "userErrors")&.any?
        errors = response.dig("data", "productCreateMedia", "userErrors").map { |e| e["message"] }.join(", ")
        puts "❌ Failed to add image: #{errors}"
      elsif response.dig("data", "productCreateMedia", "media")&.any?
        media = response.dig("data", "productCreateMedia", "media").first
        puts "✅ Image added successfully - Media ID: #{media["id"]}, Status: #{media["status"]}"
      else
        puts "⚠️ Unexpected response when adding image: #{response.inspect}"
      end

    rescue => e
      puts "🔥 Error adding image: #{e.message}"
    end

    def save_partial_product_mapping(product_id, variant_id)
      puts "save_partial_product_mapping #{product_id} #{variant_id} session:#{@session_id} cart_hash:#{@cart_hash&.first(8)}..."
      attempts = 0

      begin
        attempts += 1

        # ✅ FIXED: Look for existing mapping that matches cart_hash, session_id, and cart_rule_id
        # This ensures we don't update mappings from different cart states
        existing_mapping = nil
        
        if @cart_hash.present? && @session_id.present?
          # Try to find exact match: same cart_hash, session_id, cart_rule_id, and original_variant_ids
          # Normalize variant_ids to array format
          variant_ids_array = @existing_variant_ids.is_a?(Array) ? @existing_variant_ids : [@existing_variant_ids].compact
          
          # For exact array match, check if all variant_ids are present (more reliable than direct array comparison)
          # Since cart_hash + session_id + cart_rule_id should be unique, we can rely on those primarily
          # and just verify the variant_ids match using text comparison
          query = PartialProductMapping.where(
            shopify_domain: @shop.shopify_domain,
            cart_hash: @cart_hash,
            session_id: @session_id,
            cart_rule_id: @cart_rule_id,
            is_deleted: false
          )
          
          # Check that all variant_ids in the array are present in original_variant_ids
          variant_ids_array.each do |variant_id|
            query = query.where("original_variant_ids::text LIKE ?", "%#{variant_id}%")
          end
          
          # Also check that the array lengths match (to ensure exact match, not just subset)
          query = query.where("array_length(original_variant_ids, 1) = ?", variant_ids_array.length)
          
          existing_mapping = query.first
        end

        if existing_mapping
          # Update existing mapping from the same cart state
          mapping = existing_mapping
          mapping.assign_attributes(
            partial_product_id: product_id,
            partial_variant_id: variant_id.to_s,
            original_variant_ids: @existing_variant_ids,
            is_deleted: false,
            original_cost: @originalPrice,
            partial_price: @price
          )
          puts "✅ Updating existing mapping for cart_hash: #{@cart_hash&.first(8)}..."
        else
          # Create new mapping - this is a different cart state
          mapping = PartialProductMapping.new(
            shopify_domain: @shop.shopify_domain,
            partial_variant_id: variant_id.to_s,
            partial_product_id: product_id,
            original_variant_ids: @existing_variant_ids,
            is_deleted: false,
            original_cost: @originalPrice,
            partial_price: @price,
            session_id: @session_id,
            cart_hash: @cart_hash,
            cart_rule_id: @cart_rule_id
          )
          puts "✅ Creating new mapping for cart_hash: #{@cart_hash&.first(8)}..."
        end

        mapping.save!
        puts "✅ PartialProductMapping saved successfully: #{variant_id} with session: #{@session_id}, cart_hash: #{@cart_hash&.first(8)}..."
        true

      rescue => e
        if attempts < 2
          puts "Retrying save_partial_product_mapping for #{variant_id} (Attempt #{attempts})"
          retry
        end

        error_message = if e.is_a?(ActiveRecord::RecordInvalid)
                          "❌ Failed to save PartialProductMapping\n⚠️ Validation Errors: #{e.record.errors.full_messages.join(', ')}"
                        else
                          "🔥 Unexpected error while saving PartialProductMapping\n💥 Error: #{e.message}"
                        end

        puts "save_partial_product_mapping #{error_message}"

        SlackNotifyJob.perform_async(
          ":rage: (#{Rails.env})\n#{error_message}\n🛍️ #{@shop.shopify_domain}\n📦 #{@title}\n🧾 Product ID: #{product_id}\n🔖 Variant ID: #{variant_id}"
        )

        false
      end
    end
  end
end
module ShopifyServices
  class PartialOrderMappingService < ShopifyServices::GraphqlService
    attr_reader :shop, :client, :order_id

    # ShopifyServices::PartialOrderMappingService.call(shop, '7068553740572')
    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
        query($id:ID!) {
          order(id:$id){
            id
            lineItems(first:50){
              edges{
                node{
                  id
                  quantity
                  title
                  name
                  variant{
                    id
                    title
                    product{
                      id
                      title
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
      variables = {
        id: "gid://shopify/Order/#{@order_id}"
      }
      resp = @client.query(query, variables: variables)
      Rails.logger.info "Order response: #{resp.inspect}"
      return resp
    end

    def parse_partial_payment_title(title)
      # Format 1: "Partial Payment for {product_title} - {variant_title} {id}"
      # Example: "Partial Payment for Lattafa Mayar EDP for women Decant - 10ml Decant 1767000116-368"
      # Format 2: "Partial Payment for {product_title} {id}" (default variant)
      # Example: "Partial Payment for 1199 shirt 1767002290-441"
      
      return nil unless title.present? && title.include?("Partial Payment for")
      
      # Remove "Partial Payment for" prefix
      cleaned_title = title.sub(/^Partial Payment for\s+/i, "").strip
      
      # Check if there's a " - " separator (format with variant title)
      if cleaned_title.include?(" - ")
        # Format 1: Has variant title
        parts = cleaned_title.split(/\s+-\s+/, 2)
        return nil unless parts.length == 2
        
        product_title = parts[0].strip
        variant_part = parts[1].strip
        
        # Extract variant title (everything before the last space-separated part which is the ID)
        # The ID format appears to be like "1767000116-368" (numbers and dashes)
        variant_parts = variant_part.split(/\s+/)
        
        # The last part should be the ID (contains numbers and possibly dashes)
        # Everything before that is the variant title
        if variant_parts.length >= 2 && variant_parts.last.match?(/\d/)
          variant_title = variant_parts[0..-2].join(" ")
          id_part = variant_parts.last
        else
          # If last part doesn't look like ID, assume entire variant_part is variant title
          variant_title = variant_part
          id_part = nil
        end
      else
        # Format 2: No variant title (default variant)
        # Extract product title by removing the ID suffix
        # ID format: numbers and dashes at the end (e.g., "1767002290-441")
        # Match pattern: ends with space(s) followed by digits and dashes
        if cleaned_title.match?(/\s+\d+[\d-]+\s*$/)
          # Extract ID (last part matching the pattern)
          id_match = cleaned_title.match(/\s+(\d+[\d-]+)\s*$/)
          id_part = id_match[1] if id_match
          
          # Product title is everything before the ID
          product_title = cleaned_title.sub(/\s+\d+[\d-]+\s*$/, "").strip
        else
          # No ID found, entire cleaned title is product title
          product_title = cleaned_title
          id_part = nil
        end
        
        variant_title = nil # Default variant - will use first/default variant
      end
      
      {
        product_title: product_title,
        variant_title: variant_title,
        id: id_part
      }
    end

    def find_variant_by_product_and_variant_title(product_title, variant_title)
      # Search for product by title
      query = @client.parse <<-'GRAPHQL'
        query($query: String!) {
          products(first: 1, query: $query) {
            edges {
              node {
                id
                title
                variants(first: 50) {
                  edges {
                    node {
                      id
                      title
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      variables = { query: "title:#{product_title}" }
      response = @client.query(query, variables: variables)
      
      if response&.data&.products&.edges&.any?
        product_node = response.data.products.edges.first.node
        Rails.logger.info "Found product: #{product_node.title}"
        
        # If variant_title is nil, use default variant (first variant or "Default Title")
        if variant_title.nil?
          # Try to find "Default Title" first, otherwise use first variant
          variant_node = product_node.variants.edges.find do |edge|
            edge.node.title == "Default Title"
          end
          
          # If no "Default Title", use first variant
          variant_node ||= product_node.variants.edges.first
          
          if variant_node
            variant_id = variant_node.node.id.gsub("gid://shopify/ProductVariant/", "")
            Rails.logger.info "Using default variant: #{variant_node.node.title} (ID: #{variant_id})"
            return variant_id
          else
            Rails.logger.error "No variants found for product '#{product_title}'"
            return nil
          end
        else
          # Find variant that matches the variant title exactly
          variant_node = product_node.variants.edges.find do |edge|
            edge.node.title == variant_title
          end
          
          if variant_node
            variant_id = variant_node.node.id.gsub("gid://shopify/ProductVariant/", "")
            Rails.logger.info "Found variant: #{variant_node.node.title} (ID: #{variant_id})"
            return variant_id
          else
            Rails.logger.error "Variant '#{variant_title}' not found in product '#{product_title}' - exact match required"
            return nil
          end
        end
      else
        Rails.logger.warn "Product '#{product_title}' not found"
        return nil
      end
      
      nil
    rescue => e
      Rails.logger.error "Error finding variant: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end

    def create_partial_product_mapping(original_variant_id, quantity)
      # Generate random UUID for partial_variant_id (remove hyphens for cleaner format)
      partial_variant_id = SecureRandom.uuid.gsub('-', '')
      
      # Format original_variant_ids as array: ["variant_id:quantity"]
      original_variant_ids = ["#{original_variant_id}:#{quantity}"]
      
      mapping = PartialProductMapping.new(
        shopify_domain: @shop.shopify_domain,
        partial_variant_id: partial_variant_id,
        original_variant_ids: original_variant_ids,
        is_deleted: true
      )
      
      if mapping.save
        Rails.logger.info "Created PartialProductMapping: partial_variant_id=#{partial_variant_id}, original_variant_ids=#{original_variant_ids.inspect}"
        return partial_variant_id
      else
        Rails.logger.error "Failed to create PartialProductMapping: #{mapping.errors.full_messages.join(', ')}"
        return nil
      end
    rescue => e
      Rails.logger.error "Error creating PartialProductMapping: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end

    def call
      begin
        # Step 1: Read the complete order and get line items
        order_response = get_order
        
        unless order_response&.data&.order&.line_items&.edges.present?
          Rails.logger.error "Could not fetch order or no line items found"
          return { error: "Could not fetch order or no line items found" }
        end

        line_items_edges = order_response.data.order.line_items.edges
        Rails.logger.info "Found #{line_items_edges.count} line item(s) in order"

        # Step 2: Parse line items with "Partial Payment for" format
        partial_variant_ids = []
        mappings_created = []

        line_items_edges.each do |edge|
          node = edge.node
          title = node.title || node.name
          quantity = node.quantity
          
          next unless title.present?
          
          # Parse the title to extract product title and variant title
          parsed = parse_partial_payment_title(title)
          
          if parsed.nil?
            Rails.logger.info "Skipping line item '#{title}' - doesn't match Partial Payment format"
            next
          end

          variant_info = parsed[:variant_title] ? "variant_title='#{parsed[:variant_title]}'" : "variant_title=nil (default variant)"
          Rails.logger.info "Parsed line item: product_title='#{parsed[:product_title]}', #{variant_info}, quantity=#{quantity}"

          # Step 3: Find variant ID by product title and variant title
          original_variant_id = find_variant_by_product_and_variant_title(
            parsed[:product_title],
            parsed[:variant_title]
          )

          unless original_variant_id.present?
            error_message = "Could not find variant for product '#{parsed[:product_title]}' with variant '#{parsed[:variant_title]}' - exact match required"
            Rails.logger.error error_message
            return { error: error_message, processed: false }
          end

          # Step 4: Create PartialProductMapping
          partial_variant_id = create_partial_product_mapping(original_variant_id, quantity)
          
          if partial_variant_id.present?
            partial_variant_ids << partial_variant_id
            mappings_created << {
              partial_variant_id: partial_variant_id,
              original_variant_id: original_variant_id,
              quantity: quantity,
              product_title: parsed[:product_title],
              variant_title: parsed[:variant_title]
            }
          else
            Rails.logger.error "Failed to create mapping for variant #{original_variant_id}"
          end
        end

        if partial_variant_ids.empty?
          Rails.logger.warn "No partial payment line items found or mappings created"
          return {
            message: "No partial payment line items found or mappings created",
            processed: false,
            mappings_created: []
          }
        end

        # Step 5: Call PartialOrderEditJob with the partial_variant_ids
        Rails.logger.info "Calling PartialOrderEditJob with #{partial_variant_ids.count} partial variant ID(s) (retry: true)"
        ShopifyJobs::PartialOrderEditJob.perform_async(
          @shop.id,
          @order_id,
          partial_variant_ids.to_json,
          true  # retry_flag = true
        )

        {
          message: "Successfully processed #{mappings_created.count} partial payment line item(s)",
          processed: true,
          mappings_created: mappings_created,
          partial_variant_ids: partial_variant_ids
        }

      rescue => e
        Rails.logger.error "Error in PartialOrderMappingService: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        { error: "Error processing order", message: e.message }
      end
    end
  end
end


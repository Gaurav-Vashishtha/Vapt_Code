module ShopifyServices
  class PartialOrderEditTwoCommitService < ShopifyServices::GraphqlService
    attr_reader :shop, :client
    
    # partialVariantIds = ['51305278636350','51305278538046']
    # ShopifyServices::PartialOrderEditTwoCommitService.call(shop,'6255577170238',partialVariantIds)
    def initialize(client, shop, order_id,partial_variant_ids)
      @client = client
      @shop = shop
      @order_id = order_id
      @partial_variant_ids=partial_variant_ids
    end

    def get_calculated_order
      
      query = @client.parse <<-'GRAPHQL'
      mutation($id:ID!) {
        orderEditBegin(id:$id){
           calculatedOrder{
             id
             lineItems(first:20){
              edges{
                node{
                  id
                  variant{
                    id
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
      puts "Resp from get Calculated Order #{resp.inspect}"
      return resp
    end


    def resolve_original_variant_id(shopify_domain, starting_variant_id)
      current_variant_id = starting_variant_id
      last_resolved_id = starting_variant_id
      visited = Set.new
    
      loop do
        break if visited.include?(current_variant_id)
        visited << current_variant_id
    
        record = PartialProductMapping.find_by(
          shopify_domain: shopify_domain,
          partial_variant_id: current_variant_id
        )
    
        break if record.nil? || record.original_variant_ids.blank?
    
        # Get the first original_variant_id and strip the ":quantity"
        resolved_id = record.original_variant_ids.first.split(":").first
    
        # Save and continue
        last_resolved_id = resolved_id
        current_variant_id = resolved_id
      end
    
      last_resolved_id
    end

    def add_variant(calculated_order_id,variant_id,quantity)
      query = @client.parse <<-'GRAPHQL'
      mutation ($id:ID!,$variantId:ID!, $quantity:Int!) {
        orderEditAddVariant(id: $id, variantId: $variantId , quantity: $quantity){
          calculatedOrder {
            id
            addedLineItems(first:5) {
              edges {
                node {
                  id
                }
              }
            }
          }
          userErrors {
            field
            message
          }
        }
      }
      GRAPHQL

      variant_id = resolve_original_variant_id(@shop.shopify_domain,variant_id)

      variables = {
        id: calculated_order_id,
        variantId: "gid://shopify/ProductVariant/#{variant_id}",
        quantity: quantity.to_i
      }
      @client.query(query, variables: variables)
    end

    def remove_partial_product(calculated_order_id,calculated_line_item_id)
      query = @client.parse <<-'GRAPHQL'
      mutation ($id: ID!, $lineItemId: ID!, $q: Int!) {
          orderEditSetQuantity(id: $id, lineItemId: $lineItemId, quantity: $q) {
              calculatedOrder {
                  id
                  lineItems (first:10){
                      nodes {
                          id
                          quantity
                          editableQuantity
                          editableQuantityBeforeChanges
                      }
                  }
              }
          }
      }
      GRAPHQL

      variables = {
        id: calculated_order_id,
        lineItemId:calculated_line_item_id,
        q: 0
      }
      @client.query(query, variables: variables)
    end

    def commit_order(calculated_order_id)
      query = @client.parse <<-'GRAPHQL'
      mutation ($id:ID!)  {
        orderEditCommit(id: $id, notifyCustomer: false, staffNote: "COD-Fees") {
          order {
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
        id: calculated_order_id,
        notifyCustomer: false
      }
      resp = @client.query(query, variables: variables)
      resp
    end

    def call
      # First commit: Add all original variants
      calculated_order = get_calculated_order
      calculated_order_id = calculated_order&.data&.order_edit_begin&.calculated_order&.id
      
      # Check if the order ID is present.
      if calculated_order_id.present?
        # First commit: Add all original variants for all partial_variant_ids
        @partial_variant_ids.each do |partial_variant_id|
          partial_product_mapping = PartialProductMapping.find_by(partial_variant_id: partial_variant_id.gsub('gid://shopify/ProductVariant/',''))
          puts "partial_product_mapping : #{partial_product_mapping}"
          
          # Proceed only if a mapping is found.
          if partial_product_mapping.present?
            begin
              # Add all original variants from the mapping
              partial_product_mapping.original_variant_ids.each do |original_variant_id|
                puts "original_variant_id: #{original_variant_id}"
                vid_qty_array = original_variant_id.split(":") #DB stores value like "variantid:qty"
                add_variant_resp = add_variant(calculated_order_id, vid_qty_array[0],vid_qty_array[1])  
                puts "add_variant_resp: #{add_variant_resp.inspect}"
              end
            rescue Exception => e
              puts "Failed to add variants: #{e.message}"
            end
          else
            puts "No partial product mapping found for variant ID: #{partial_variant_id}"
          end
        end
        
        # First commit: Commit the additions
        first_commit_resp = commit_order(calculated_order_id)
        puts "First commit response: #{first_commit_resp.inspect}"
        
        # Check if first commit was successful
        first_commit_errors = first_commit_resp&.data&.order_edit_commit&.user_errors
        first_commit_order_id = first_commit_resp&.data&.order_edit_commit&.order&.id
        
        if first_commit_errors&.any? || first_commit_order_id.blank?
          error_messages = first_commit_errors&.map { |e| e.message }&.join(", ") || "Unknown error"
          Rails.logger.error "First order edit commit failed: #{error_messages}"
          return { error: "First order edit commit failed", errors: first_commit_errors, response: first_commit_resp }
        end
        
        # Second commit: Remove partial variants
        # Get calculated order again after first commit
        calculated_order_after_first = get_calculated_order
        calculated_order_id_after_first = calculated_order_after_first&.data&.order_edit_begin&.calculated_order&.id
        
        if calculated_order_id_after_first.present?
          # Retrieve the partial product mapping based on the variant ID.
          @partial_variant_ids.each do |partial_variant_id|
            partial_product_mapping = PartialProductMapping.find_by(partial_variant_id: partial_variant_id.gsub('gid://shopify/ProductVariant/',''))
            puts "partial_product_mapping for removal: #{partial_product_mapping}"
            
            # Proceed only if a mapping is found.
            if partial_product_mapping.present?
              # Safely navigate through objects and retrieve line items.
              line_items = calculated_order_after_first&.data&.order_edit_begin&.calculated_order&.line_items&.edges
              puts "line_items for removal: #{line_items.inspect}"
              
              # Check if line items are present and an array.
              if line_items.is_a?(Array)
                line_items.each do |line_item|
                  variant_id = line_item&.node&.variant&.id
                  if variant_id.blank?
                    variant_id = partial_product_mapping.partial_variant_id
                  end
                  variant_id = variant_id.gsub("gid://shopify/ProductVariant/","")
                  node_id = line_item&.node&.id
                  puts "Variant ID found from line Item from Shopify for removal: #{variant_id}"
                  
                  # Check if the current line item's variant ID matches the mapping.
                  if variant_id && variant_id == partial_product_mapping.partial_variant_id
                    begin
                      puts "Variant ID matched from Shopify and Mapping for removal: #{variant_id}"
                      partial_remove_product_response = remove_partial_product(calculated_order_id_after_first, node_id)
                      puts "partial_remove_product_response: #{partial_remove_product_response.inspect}"
                    rescue Exception => e
                      puts "Failed to remove partial product: #{e.message}"
                    end
                  end
                end
              else
                puts "No valid line items found for removal."
              end
            else
              puts "No partial product mapping found for variant ID: #{partial_variant_id}"
            end
          end
          
          # Second commit: Commit the removals
          resp = commit_order(calculated_order_id_after_first)
          puts "Second commit response: #{resp.inspect}"
          
          # Check if second commit was successful
          commit_errors = resp&.data&.order_edit_commit&.user_errors
          commit_order_id = resp&.data&.order_edit_commit&.order&.id
          
          if commit_errors&.any? || commit_order_id.blank?
            # Commit failed - don't update status (let job handle it)
            error_messages = commit_errors&.map { |e| e.message }&.join(", ") || "Unknown error"
            Rails.logger.error "Second order edit commit failed: #{error_messages}"
            return { error: "Second order edit commit failed", errors: commit_errors, response: resp }
          end
          
          # Both commits successful - update order confirmation
          @shop.init_session 
          shopify_order = ShopifyAPI::Order.find(@order_id)
          if !shopify_order.blank?
            order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
            order_confirmation.update(order_amount: shopify_order.current_total_price)
            order_confirmation.update(status: 'COD-Partial-Payment-Received')
            if @shop.setting.confirmation_whatsapp
              NetworkServices::WhatsappConfirmationService.call(@shop,order_confirmation,true)
            end
          end
          return resp
        else
          puts "Calculated order ID after first commit is blank"
          return { error: "Failed to get calculated order after first commit" }
        end
      else
        puts "Calculated order ID is blank"
        return { error: "Failed to get calculated order" }
      end
    end
  end
end


module ShopifyServices
  class PartialOrderEditService
    class BundleTwoCommit < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :order_id

      # Custom attribute marker to indicate bundle flattening has been completed
      BUNDLE_FLATTENED_ATTRIBUTE_KEY = "codk_partially_paid"
      BUNDLE_FLATTENED_ATTRIBUTE_VALUE = "true"

      # ShopifyServices::PartialOrderEditService::BundleTwoCommit.call(shop, order_id)
      # delegated: true when handed over from the other bundle service, so it never hands back (no ping-pong)
      def initialize(client, shop, order_id, delegated = false)
        @client = client
        @shop = shop
        @order_id = order_id
        @delegated = delegated
      end

      def get_original_order
        query = @client.parse <<-'GRAPHQL'
        query($id:ID!) {
          order(id:$id){
            id
            customAttributes {
              key
              value
            }
            lineItems(first:50){
              edges{
                node{
                  id
                  quantity
                  title
                  name
                  customAttributes {
                    key
                    value
                  }
                  variant{
                    id
                    title
                    product{
                      id
                      hasVariantsThatRequiresComponents
                      title
                    }
                  }
                  discountAllocations{
                    allocatedAmount{
                      amount
                      currencyCode
                    }
                    discountApplication{
                      ... on DiscountCodeApplication{
                        code
                      }
                      ... on ScriptDiscountApplication{
                        title
                      }
                      ... on AutomaticDiscountApplication{
                        title
                      }
                    }
                  }
                  originalUnitPriceSet{
                    shopMoney{
                      amount
                      currencyCode
                    }
                  }
                  discountedTotalSet{
                    shopMoney{
                      amount
                      currencyCode
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
        Rails.logger.info "Original order response: #{resp.inspect}"
        return resp
      end

      def get_calculated_order
        query = @client.parse <<-'GRAPHQL'
        mutation($id:ID!) {
          orderEditBegin(id:$id){
             calculatedOrder{
               id
               lineItems(first:50){
                edges{
                  node{
                    id
                    quantity
                    variant{
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
        Rails.logger.info "Calculated order response: #{resp.inspect}"
        return resp
      end

      def remove_bundle_line_item(calculated_order_id, line_item_id)
        query = @client.parse <<-'GRAPHQL'
        mutation ($id: ID!, $lineItemId: ID!, $q: Int!, $restock: Boolean!) {
          orderEditSetQuantity(id: $id, lineItemId: $lineItemId, quantity: $q, restock: $restock) {
            calculatedOrder {
              id
              lineItems(first:50){
                nodes {
                  id
                  quantity
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

        variables = {
          id: calculated_order_id,
          lineItemId: line_item_id,
          q: 0,
          restock: true
        }
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Remove bundle response: #{resp.inspect}"
        return resp
      end

      def add_variant(calculated_order_id, variant_id, quantity)
        query = @client.parse <<-'GRAPHQL'
        mutation ($id:ID!,$variantId:ID!, $quantity:Int!, $allowDuplicates:Boolean) {
          orderEditAddVariant(id: $id, variantId: $variantId , quantity: $quantity, allowDuplicates: $allowDuplicates){
            calculatedLineItem {
              id
              quantity
              variant {
                id
                title
              }
            }
            calculatedOrder {
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
          variantId: "gid://shopify/ProductVariant/#{variant_id}",
          quantity: quantity.to_i,
          allowDuplicates: true
        }
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Add variant response: #{resp.inspect}"
        return resp
      end

      def add_line_item_discount(calculated_order_id, line_item_id, discount_input)
        query = @client.parse <<-'GRAPHQL'
        mutation ($id: ID!, $lineItemId: ID!, $discountInput: OrderEditAppliedDiscountInput!) {
          orderEditAddLineItemDiscount(
            id: $id
            lineItemId: $lineItemId
            discount: $discountInput
          ) {
            addedDiscountStagedChange {
              id
            }
            calculatedLineItem {
              id
              discountAllocations {
                allocatedAmount {
                  amount
                  currencyCode
                }
              }
            }
            calculatedOrder {
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
          lineItemId: line_item_id,
          discountInput: discount_input
        }
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Add line item discount response: #{resp.inspect}"
        return resp
      end

      def build_discount_info(node, free_variant:)
        discount_allocation = node.discount_allocations&.first
        discount_application = discount_allocation&.discount_application
        discount_description = extract_discount_label(discount_application)

        if free_variant
          discount_description ||= "Free variant discount"
          payload = {
            percentValue: 100.0
          }
          payload[:description] = discount_description if discount_description.present?
          return payload
        end

        allocated_amount = discount_allocation&.allocated_amount&.amount
        discount_amount = allocated_amount.to_f if allocated_amount.present?

        return nil unless discount_amount.present? && discount_amount.positive?

        currency_code = extract_currency_code(node, discount_allocation)
        payload = {
          fixedValue: {
            amount: discount_amount,
            currencyCode: currency_code
          }
        }
        payload[:description] = discount_description if discount_description.present?
        payload
      end

      def extract_discount_label(discount_application)
        return nil if discount_application.blank?

        if discount_application.respond_to?(:title) && discount_application.title.present?
          discount_application.title
        elsif discount_application.respond_to?(:code) && discount_application.code.present?
          discount_application.code
        end
      end

      def extract_currency_code(node, discount_allocation)
        discount_allocation&.allocated_amount&.currency_code ||
          node.try(:original_unit_price_set)&.shop_money&.currency_code ||
          node.try(:originalUnitPriceSet)&.shopMoney&.currencyCode ||
          node.try(:discounted_total_set)&.shop_money&.currency_code ||
          node.try(:discountedTotalSet)&.shopMoney&.currencyCode ||
          "USD"
      end

      def zero_priced_line_item?(node)
        amount =
          node.try(:discounted_total_set)&.shop_money&.amount ||
          node.try(:discountedTotalSet)&.shopMoney&.amount ||
          node.try(:original_total_price_set)&.shop_money&.amount ||
          node.try(:originalTotalPriceSet)&.shopMoney&.amount ||
          node.try(:original_unit_price_set)&.shop_money&.amount ||
          node.try(:originalUnitPriceSet)&.shopMoney&.amount

        amount.present? && amount.to_f.zero?
      end

      def extract_order_custom_attributes(order_response)
        return {} unless order_response&.data&.order&.custom_attributes.present?

        custom_attributes = {}
        order_response.data.order.custom_attributes.each do |attr|
          key = attr.key
          value = attr.value
          custom_attributes[key] = value if key.present? && value.present?
        end
        custom_attributes
      end

      def parse_codk_free_variants(codk_free_variants_string)
        return [] unless codk_free_variants_string.present?
        
        # Format: "variantID1:qty, variantID2:qty"
        free_variant_ids = []
        codk_free_variants_string.split(',').each do |item|
          item = item.strip
          next if item.blank?
          
          # Split by colon to get variant ID and quantity
          parts = item.split(':')
          variant_id = parts.first&.strip
          free_variant_ids << variant_id if variant_id.present?
        end
        free_variant_ids
      end

      def free_gift_line?(node)
        attrs = node.try(:custom_attributes) || node.try(:customAttributes)
        Array(attrs).any? { |attr| attr.try(:key) == FreeGifts::LINE_PROPERTY && attr.try(:value).present? }
      end

      def is_free_gift_variant?(variant_id_numeric, order_custom_attributes)
        # Check if variant is listed in _codkFreeVariants
        codk_free_variants = order_custom_attributes['_codkFreeVariants']
        return false unless codk_free_variants.present?
        
        free_variant_ids = parse_codk_free_variants(codk_free_variants)
        free_variant_ids.include?(variant_id_numeric)
      end

      def commit_order(calculated_order_id, staff_note: nil)
        staff_note ||= "Bundle flattened"
        query = @client.parse <<-'GRAPHQL'
        mutation ($id:ID!, $staffNote:String)  {
          orderEditCommit(id: $id, notifyCustomer: false, staffNote: $staffNote) {
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
          staffNote: staff_note
        }
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Commit order response: #{resp.inspect}"
        return resp
      end

      def current_step_status
        OrderConfirmation.find_by(order_id: @order_id, shop_id: @shop.id)&.status.to_s.delete_suffix(Bundle::RETRY_FAILED_SUFFIX)
      end

      def set_step_status(step_status)
        OrderConfirmation.where(order_id: @order_id, shop_id: @shop.id).update_all(status: step_status, updated_at: Time.current)
        Rails.logger.info "Order #{@order_id} step marker set to #{step_status}"
      end

      def update_order_confirmation_status
        order_confirmation = OrderConfirmation.find_by(order_id: @order_id, shop_id: @shop.id)
        if order_confirmation.present?
          @shop.init_session
          shopify_order = ShopifyAPI::Order.find(@order_id)
          if shopify_order.present?
            order_confirmation.update!(
              order_amount: shopify_order.current_total_price,
              status: 'COD-Partial-Payment-Received'
            )
            if @shop.setting.confirmation_whatsapp
              NetworkServices::WhatsappConfirmationService.call(@shop, order_confirmation, true)
            end
            Rails.logger.info "Updated order confirmation status to COD-Partial-Payment-Received for order #{@order_id}"
          else
            Rails.logger.warn "Could not find Shopify order #{@order_id} to update order confirmation"
          end
        else
          Rails.logger.info "No order confirmation found for order #{@order_id}, skipping status update"
        end
      rescue => e
        Rails.logger.error "Error updating order confirmation status: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Don't fail the operation if order confirmation update fails
      end

      def add_bundle_flattened_attribute
        # Get existing custom attributes
        order_response = get_original_order
        return unless order_response&.data&.order.present?

        existing_attributes = extract_order_custom_attributes(order_response)
        
        # Skip if attribute already exists
        return if existing_attributes[BUNDLE_FLATTENED_ATTRIBUTE_KEY] == BUNDLE_FLATTENED_ATTRIBUTE_VALUE

        # Build custom attributes array for mutation
        custom_attributes = []
        
        # Add existing attributes
        existing_attributes.each do |key, value|
          custom_attributes << { key: key, value: value }
        end
        
        # Add the new attribute
        custom_attributes << { key: BUNDLE_FLATTENED_ATTRIBUTE_KEY, value: BUNDLE_FLATTENED_ATTRIBUTE_VALUE }

        query = @client.parse <<-'GRAPHQL'
        mutation ($input: OrderInput!) {
          orderUpdate(input: $input) {
            order {
              id
              customAttributes {
                key
                value
              }
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
            id: "gid://shopify/Order/#{@order_id}",
            customAttributes: custom_attributes
          }
        }
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Add bundle-flattened custom attribute response: #{resp.inspect}"
        return resp
      end

      def call
        # Reversed approach: Add all variants first, then remove original line items
        # This breaks bundle relationships by adding duplicates and then removing originals
        # Free gift variants are determined from _codkFreeVariants custom attribute (format: "variantID1:qty, variantID2:qty")
        # Only variants listed in _codkFreeVariants will receive 100% discount

        step_status = current_step_status
        if step_status == Bundle::PARTIAL_PAID_STATUS
          Rails.logger.info "Order #{@order_id} is already #{Bundle::PARTIAL_PAID_STATUS}. Skipping bundle flattening."
          return { message: "Order already partially paid (skip)", processed: false, already_flattened: true }
        end

        # Bundle got halfway (originals removed, nothing re-added) - only it can finish that safely
        if step_status == Bundle::REMOVED_STEP_STATUS
          return { error: "Step marker #{step_status} changed during handover - stopping" } if @delegated
          return Bundle.call(@shop, @order_id, true)
        end

        # A previous run's first commit (additions) landed - the order now holds originals + copies
        additions_committed = step_status == Bundle::ADDED_STEP_STATUS

        # IDEMPOTENCY CHECK: Skip if bundle flattening was already completed
        # We check the codk_partially_paid custom attribute OR the Flattened step marker
        begin
          # Get original order from GraphQL to check if already flattened
          original_order_response = get_original_order
          
          unless original_order_response&.data&.order.present?
            Rails.logger.error "Could not fetch order from GraphQL"
            return { error: "Could not fetch order from GraphQL" }
          end
          
          order_custom_attributes = extract_order_custom_attributes(original_order_response)
          if order_custom_attributes[BUNDLE_FLATTENED_ATTRIBUTE_KEY] == BUNDLE_FLATTENED_ATTRIBUTE_VALUE || step_status == Bundle::FLATTENED_STEP_STATUS
            Rails.logger.info "Order #{@order_id} already flattened (#{BUNDLE_FLATTENED_ATTRIBUTE_KEY} attribute or #{Bundle::FLATTENED_STEP_STATUS}). Skipping operation for idempotency."

            # Both commits landed but the run died before tagging the order - tag it now (no-op if already tagged)
            begin
              add_bundle_flattened_attribute
            rescue => e
              Rails.logger.error "Error adding bundle-flattened custom attribute: #{e.message}"
            end

            # Still update order confirmation status even if already flattened
            update_order_confirmation_status
            
            return {
              message: "Bundle flattening already completed (idempotent skip)",
              processed: false,
              already_flattened: true
            }
          end
        rescue => e
          Rails.logger.error "Error checking order idempotency: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          # Continue with operation if check fails
        end
        
        begin
          # Get original order from GraphQL to collect all line items (if not already fetched)
          original_order_response ||= get_original_order
          
          unless original_order_response&.data&.order&.line_items&.edges.present?
            Rails.logger.error "Could not fetch order from GraphQL or no line items"
            return { error: "Could not fetch order from GraphQL" }
          end

          # Extract order custom attributes
          order_custom_attributes = extract_order_custom_attributes(original_order_response)
          codk_free_variants = order_custom_attributes['_codkFreeVariants']
          free_variant_ids_list = parse_codk_free_variants(codk_free_variants)
          Rails.logger.info "Order custom attributes - _codkFreeVariants: #{codk_free_variants}, Free variant IDs: #{free_variant_ids_list.inspect}"

          line_items_edges = original_order_response.data.order.line_items.edges
          Rails.logger.info "Fetched order with #{line_items_edges.count} line items from GraphQL"
          
          # Collect all variants with their quantities and discount metadata
          variants_to_restore = []  # Array of {variant_id, quantity, discount_info, free_variant, original_line_item_id}
          
            line_items_edges.each do |edge|
              node = edge.node
              variant = node.variant
              next unless variant.present?

              variant_id = variant.id
              variant_id_numeric = variant_id.gsub("gid://shopify/ProductVariant/", "")
              quantity = node.quantity
              
              # Check if variant is a free gift (listed in _codkFreeVariants)
              free_variant = is_free_gift_variant?(variant_id_numeric, order_custom_attributes) || free_gift_line?(node)

              discount_info = build_discount_info(node, free_variant: free_variant)

              log_message = "Collecting variant: #{variant_id_numeric} with quantity #{quantity}"
              if free_variant
                log_message += " (free gift variant from _codkFreeVariants - applying 100% discount)"
              elsif discount_info.present?
                if discount_info[:fixedValue].present?
                  log_message += " and #{discount_info[:fixedValue][:amount]} #{discount_info[:fixedValue][:currencyCode]} discount"
                elsif discount_info[:percentValue].present?
                  log_message += " and #{discount_info[:percentValue]}% discount"
                end
              end
              Rails.logger.info log_message

              variants_to_restore << {
                variant_id: variant_id_numeric,
                quantity: quantity,
                discount_info: discount_info,
                free_variant: free_variant,
                original_line_item_id: node.id
              }
            end
          
          if variants_to_restore.empty?
            Rails.logger.info "No line items found in order #{@order_id}"
            return { message: "No line items found in order", processed: false }
          end
          
          free_variants_count = variants_to_restore.count { |variant| variant[:free_variant] }
          Rails.logger.info "Found #{variants_to_restore.count} variant(s) to flatten (#{free_variants_count} free variant(s) will receive 100% discount)"

        rescue => e
          Rails.logger.error "Error fetching order from GraphQL: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          return { error: "Error fetching order from GraphQL", message: e.message }
        end

        # Additions already committed on a previous run - re-adding would duplicate every item,
        # so jump straight to removing the originals saved in the marker
        if additions_committed
          Rails.logger.info "Order #{@order_id} has #{Bundle::ADDED_STEP_STATUS} marker - skipping STEP 1-3 (add + first commit)"
        else
          # STEP 1: Start order edit session and add all variants as duplicates
          Rails.logger.info "Starting order edit session to add all variants as independent items"
          calculated_order = get_calculated_order
          calculated_order_id = calculated_order&.data&.order_edit_begin&.calculated_order&.id

          unless calculated_order_id.present?
            Rails.logger.error "Calculated order ID is blank"
            return { error: "Could not begin order edit" }
          end

          # STEP 2: Add each variant as an independent line item and apply discounts if needed
          variants_to_restore.each do |variant_info|
            Rails.logger.info "Adding variant #{variant_info[:variant_id]} with quantity #{variant_info[:quantity]} as independent item"
            add_response = add_variant(calculated_order_id, variant_info[:variant_id], variant_info[:quantity])
            
            if add_response&.data&.order_edit_add_variant&.user_errors&.any?
              errors = add_response.data.order_edit_add_variant.user_errors
              error_messages = errors.map { |e| e.message }.join(", ")
              Rails.logger.error "Error adding variant #{variant_info[:variant_id]}: #{error_messages}"
            else
              Rails.logger.info "Successfully added variant #{variant_info[:variant_id]} with quantity #{variant_info[:quantity]} as independent item"
              
              # Apply discount if it existed on the original line item
              discount_input = variant_info[:discount_info]
              if discount_input.present?
                calculated_line_item = add_response&.data&.order_edit_add_variant&.calculated_line_item

                if calculated_line_item.present?
                  added_line_item_id = calculated_line_item.id
                  log_discount =
                    if discount_input[:percentValue].present?
                      "#{discount_input[:percentValue]}% discount"
                    elsif discount_input[:fixedValue].present?
                      fixed_value = discount_input[:fixedValue]
                      "#{fixed_value[:amount]} #{fixed_value[:currencyCode]} discount"
                    else
                      "manual discount"
                    end
                  Rails.logger.info "Applying #{log_discount} to line item #{added_line_item_id} (variant: #{variant_info[:variant_id]})"
                  discount_response = add_line_item_discount(calculated_order_id, added_line_item_id, discount_input)
                  
                  if discount_response&.data&.order_edit_add_line_item_discount&.user_errors&.any?
                    errors = discount_response.data.order_edit_add_line_item_discount.user_errors
                    error_messages = errors.map { |e| e.message }.join(", ")
                    Rails.logger.error "Error applying discount to variant #{variant_info[:variant_id]}: #{error_messages}"
                  else
                    Rails.logger.info "Successfully applied #{log_discount} to variant #{variant_info[:variant_id]}"
                  end
                else
                  Rails.logger.warn "Could not find calculated line item for variant #{variant_info[:variant_id]} to apply discount"
                end
              end
            end
          end
          
          # STEP 3: Commit the additions (first commit)
          Rails.logger.info "Committing first change: adding #{variants_to_restore.count} variant(s) as independent items"
          first_commit_response = commit_order(calculated_order_id, staff_note: "Adding bundle items")
          
          if first_commit_response&.data&.order_edit_commit&.user_errors&.any?
            errors = first_commit_response.data.order_edit_commit.user_errors
            error_messages = errors.map { |e| e.message }.join(", ")
            Rails.logger.error "Error in first commit (addition): #{error_messages}"
            return { error: "Error committing order addition", errors: first_commit_response.data.order_edit_commit.user_errors }
          end
          
          Rails.logger.info "First commit successful - variants added as independent items"
          set_step_status(Bundle::ADDED_STEP_STATUS)
        end

        # STEP 4: Start a new order edit session to remove original line items
        Rails.logger.info "Starting new order edit session to remove original line items"
        calculated_order_after_first = get_calculated_order
        new_calculated_order_id = calculated_order_after_first&.data&.order_edit_begin&.calculated_order&.id
        
        unless new_calculated_order_id.present?
          Rails.logger.error "Could not start new order edit session after first commit"
          return { error: "Could not start new order edit session" }
        end

        calculated_line_items = calculated_order_after_first&.data&.order_edit_begin&.calculated_order&.line_items&.edges
        unless calculated_line_items.present? && calculated_line_items.is_a?(Array)
          Rails.logger.error "No valid line items found in calculated order after first commit"
          return { error: "No line items found in calculated order after first commit" }
        end

        Rails.logger.info "Found #{calculated_line_items.count} line item(s) in calculated order after first commit"

        # Map original line item IDs to remove
        original_line_item_ids =
          if additions_committed
            # Re-read order lists originals + copies. Copies were added after the originals so they
            # have higher ids - per variant, the older half are the originals. A variant whose add
            # failed has no copy, so nothing is removed for it.
            variants_to_restore.group_by { |v| v[:variant_id] }.flat_map do |_, lines|
              lines.sort_by { |v| v[:original_line_item_id].to_s.split('/').last.to_i }
                   .first(lines.size / 2)
                   .map { |v| v[:original_line_item_id] }
            end
          else
            variants_to_restore.map { |v| v[:original_line_item_id] }.compact
          end
        
        original_line_item_numeric_ids = original_line_item_ids.map { |id| id.to_s.split('/').last }
        removed_count = 0

        # Remove original line items (set quantity to 0) so bundles are flattened
        calculated_line_items.each do |edge|
          node = edge.node
          line_item_id = node.id
          Rails.logger.info "Line item match check: calculated=#{line_item_id} originals=#{original_line_item_ids.inspect} " \
                            "full_id_match=#{original_line_item_ids.include?(line_item_id)} " \
                            "numeric_match=#{original_line_item_numeric_ids.include?(line_item_id.to_s.split('/').last)}"
          # Only remove if this is one of the original line items
          next unless original_line_item_numeric_ids.include?(line_item_id.to_s.split('/').last)
          
          variant_id = node.variant&.id
          variant_id_numeric = variant_id&.gsub("gid://shopify/ProductVariant/", "") || ""
          Rails.logger.info "Removing original line item: #{line_item_id} (variant: #{variant_id_numeric})"
          remove_response = remove_bundle_line_item(new_calculated_order_id, line_item_id)
          
          if remove_response&.data&.order_edit_set_quantity&.user_errors&.any?
            Rails.logger.error "Error removing line item: #{remove_response.data.order_edit_set_quantity.user_errors}"
          else
            removed_count += 1
            Rails.logger.info "Successfully removed original line item: #{line_item_id}"
          end
        end

        if removed_count.zero?
          Rails.logger.error "No original line items matched for removal (expected #{original_line_item_ids.inspect})"
          return { error: "No original line items matched for removal", expected: original_line_item_ids }
        end
        
        # STEP 5: Commit the removals (second commit)
        Rails.logger.info "Committing second change: removing original line items"
        second_commit_response = commit_order(new_calculated_order_id, staff_note: "Bundle flattened")
        
        if second_commit_response&.data&.order_edit_commit&.user_errors&.any?
          errors = second_commit_response.data.order_edit_commit.user_errors
          error_messages = errors.map { |e| e.message }.join(", ")
          Rails.logger.error "Error in second commit (removal): #{error_messages}"
          return { error: "Error committing order removal", errors: second_commit_response.data.order_edit_commit.user_errors }
        else
          Rails.logger.info "Second commit successful - original line items removed"
          set_step_status(Bundle::FLATTENED_STEP_STATUS)
          
          # Add custom attribute to mark bundle flattening as completed (for idempotency)
          begin
            add_bundle_flattened_attribute
          rescue => e
            Rails.logger.error "Error adding bundle-flattened custom attribute: #{e.message}"
            # Don't fail the operation if custom attribute addition fails
          end
        end

        # Update order confirmation status after successful flattening
        update_order_confirmation_status
        { 
          message: "Successfully flattened #{variants_to_restore.count} variant(s)",
          processed: true,
          variants_count: variants_to_restore.count
        }
      end
    end
  end
end


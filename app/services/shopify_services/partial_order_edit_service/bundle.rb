module ShopifyServices
  class PartialOrderEditService
    class Bundle < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :order_id

      # Custom attribute marker to indicate bundle flattening has been completed
      BUNDLE_FLATTENED_ATTRIBUTE_KEY = "codk_partially_paid"
      BUNDLE_FLATTENED_ATTRIBUTE_VALUE = "true"

      # Step markers kept in order_confirmation.status so a crashed/retried run
      # resumes after the last committed step instead of editing the order twice.
      PARTIAL_PAID_STATUS = 'COD-Partial-Payment-Received'
      REMOVED_STEP_STATUS = "#{PARTIAL_PAID_STATUS}-Removed"        # Bundle: originals removed, not re-added yet
      ADDED_STEP_STATUS = "#{PARTIAL_PAID_STATUS}-Added"            # BundleTwoCommit: copies added, originals not removed yet
      FLATTENED_STEP_STATUS = "#{PARTIAL_PAID_STATUS}-Flattened"    # both commits done
      RETRY_FAILED_SUFFIX = "|Retry-Failed"                          # appended when the retry also failed - stops auto re-queue

      def self.step_status?(status)
        status.to_s.start_with?("#{PARTIAL_PAID_STATUS}-")
      end

      # ShopifyServices::PartialOrderEditService::Bundle.call(shop, order_id)
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
            discountApplications(first:10){
              nodes {
                targetSelection
                targetType
                allocationMethod
                value {
                  ... on MoneyV2 {
                    amount
                    currencyCode
                  }
                  ... on PricingPercentageValue {
                    percentage
                  }
                }
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
                      targetType
                      targetSelection
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
            userErrors {
              field
              message
            }
          }
        }
        GRAPHQL
        variables = {
          id: "gid://shopify/Order/#{@order_id}"
        }
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Calculated order response: #{resp.inspect}"
        if resp&.data&.order_edit_begin&.user_errors&.any?
          errors = resp.data.order_edit_begin.user_errors
          error_messages = errors.map { |e| "#{e.message} (code: #{e.try(:code)}, field: #{e.field.inspect})" }.join("; ")
          Rails.logger.error "orderEditBegin userErrors: #{error_messages}"
        end
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

      def apply_order_level_discount_as_line_discounts(calculated_order_id, order_discount, line_items_with_prices)
        # Apply order-level discount proportionally to all line items
        # line_items_with_prices is an array of { id, quantity, unit_price, currency_code }
        return if line_items_with_prices.empty?
        
        # Calculate total value of all line items
        total_value = line_items_with_prices.sum { |item| item[:unit_price] * item[:quantity] }
        return if total_value <= 0
        
        currency_code = order_discount[:fixedValue]&.dig(:currencyCode) || line_items_with_prices.first[:currency_code] || "USD"
        
        if order_discount[:fixedValue].present?
          # Fixed amount discount - distribute proportionally
          discount_amount = order_discount[:fixedValue][:amount].to_f
          
          line_items_with_prices.each do |line_item|
            line_item_value = line_item[:unit_price] * line_item[:quantity]
            # Share of the order discount this whole line should carry.
            line_item_discount_amount = (line_item_value / total_value) * discount_amount
            # orderEditAddLineItemDiscount's fixedValue is a PER-UNIT amount —
            # Shopify multiplies it by the line's quantity — so the line's
            # share has to be divided back down, the same as the per-variant
            # discount path above. Without this a quantity-N line absorbed N
            # times its intended share (a qty-7 line ate the whole order
            # discount seven times over).
            quantity = line_item[:quantity].to_i
            next if quantity <= 0
            per_unit_discount_amount = line_item_discount_amount / quantity
            
            # orderEditAddLineItemDiscount's fixedValue is a PER-UNIT amount —
            # Shopify multiplies it by the line's quantity — so the line's
            # share has to be divided back down, the same as the per-variant
            # discount path above. Without this a quantity-N line absorbed N
            # times its intended share (a qty-7 line ate the whole order
            # discount seven times over).
            quantity = line_item[:quantity].to_i
            next if quantity <= 0
            per_unit_discount_amount = line_item_discount_amount / quantity

            if line_item_discount_amount > 0
              discount_input = {
                fixedValue: {
                  amount: per_unit_discount_amount.round(2),
                  currencyCode: currency_code
                },
                description: order_discount[:description]
              }
              
              Rails.logger.info "Applying order-level discount proportionally: #{line_item_discount_amount.round(2)} #{currency_code} total (#{per_unit_discount_amount.round(2)} per unit x #{quantity}) to line item #{line_item[:id]}"
              discount_response = add_line_item_discount(calculated_order_id, line_item[:id], discount_input)
              
              if discount_response&.data&.order_edit_add_line_item_discount&.user_errors&.any?
                errors = discount_response.data.order_edit_add_line_item_discount.user_errors
                error_messages = errors.map { |e| e.message }.join(", ")
                Rails.logger.error "Error applying order-level discount to line item #{line_item[:id]}: #{error_messages}"
              end
            end
          end
        elsif order_discount[:percentValue].present?
          # Percentage discount - apply same percentage to all line items
          percentage = order_discount[:percentValue].to_f
          
          line_items_with_prices.each do |line_item|
            discount_input = {
              percentValue: percentage,
              description: order_discount[:description]
            }
            
            Rails.logger.info "Applying order-level discount as percentage: #{percentage}% to line item #{line_item[:id]}"
            discount_response = add_line_item_discount(calculated_order_id, line_item[:id], discount_input)
            
            if discount_response&.data&.order_edit_add_line_item_discount&.user_errors&.any?
              errors = discount_response.data.order_edit_add_line_item_discount.user_errors
              error_messages = errors.map { |e| e.message }.join(", ")
              Rails.logger.error "Error applying order-level discount to line item #{line_item[:id]}: #{error_messages}"
            end
          end
        end
      end

      def extract_order_level_discounts(order_response)
        # Extract order-level discounts from the order's discountApplications
        # Order-level discounts have targetType: 'ORDER' or targetType: 'LINE_ITEM' with targetSelection: 'ALL'
        return [] unless order_response&.data&.order.present?

        order = order_response.data.order
        discount_applications_connection = order.try(:discount_applications) || order.try(:discountApplications)
        discount_application_nodes = []

        # Extract nodes from the connection
        if discount_applications_connection.respond_to?(:nodes)
          discount_application_nodes = discount_applications_connection.nodes
        elsif discount_applications_connection.respond_to?(:edges)
          discount_application_nodes = discount_applications_connection.edges.map(&:node)
        elsif discount_applications_connection.present?
          discount_application_nodes = Array(discount_applications_connection)
        end

        return [] unless discount_application_nodes.any?

        order_level_discounts = []
        discount_application_nodes.each do |discount_app|
          target_type = discount_app.try(:target_type) || discount_app.try(:targetType)
          target_selection = discount_app.try(:target_selection) || discount_app.try(:targetSelection)

          # Only include order-level discounts
          is_order_level = target_type == 'ORDER' || (target_type == 'LINE_ITEM' && target_selection == 'ALL')
          
          next unless is_order_level

          # Extract discount value
          value_obj = discount_app.try(:value)
          next unless value_obj.present?

          discount_info = {
            description: discount_app.try(:title) || discount_app.try(:code) || "Order discount"
          }

          # Handle fixed amount discount
          if value_obj.respond_to?(:amount)
            discount_info[:fixedValue] = {
              amount: value_obj.amount.to_f,
              currencyCode: value_obj.currency_code || value_obj.currencyCode || "USD"
            }
          # Handle percentage discount
          elsif value_obj.respond_to?(:percentage)
            discount_info[:percentValue] = value_obj.percentage.to_f
          else
            next
          end

          order_level_discounts << discount_info
          Rails.logger.info "Found order-level discount: #{discount_info.inspect}"
        end

        order_level_discounts
      end

      def build_discount_info(node, free_variant:)
        # Only process line-item specific discounts, not order-level discounts allocated to line items
        # Filter discount allocations to only include line-item specific discounts
        line_item_discount_allocation = find_line_item_specific_discount(node.discount_allocations)
        
        # If no line-item specific discount found, check for free variant discount
        if free_variant
          # Try to extract discount description from existing discount allocations first
          discount_description = nil
          if line_item_discount_allocation.present?
            discount_application = line_item_discount_allocation.discount_application
            discount_description = extract_discount_label(discount_application)
          end
          # Fallback to hardcoded description if no discount found
          discount_description ||= "Free variant discount"
          payload = {
            percentValue: 100.0
          }
          payload[:description] = discount_description if discount_description.present?
          return payload
        end

        # If no line-item specific discount allocation found, return nil
        return nil unless line_item_discount_allocation.present?

        discount_application = line_item_discount_allocation.discount_application
        discount_description = extract_discount_label(discount_application)

        allocated_amount = line_item_discount_allocation.allocated_amount&.amount
        discount_amount = allocated_amount.to_f if allocated_amount.present?

        return nil unless discount_amount.present? && discount_amount.positive?

        currency_code = extract_currency_code(node, line_item_discount_allocation)
        payload = {
          fixedValue: {
            amount: discount_amount,
            currencyCode: currency_code
          }
        }
        payload[:description] = discount_description if discount_description.present?
        payload
      end

      def find_line_item_specific_discount(discount_allocations)
        # Filter to only return line-item specific discounts
        # Order-level discounts have targetType: 'ORDER' or targetSelection: 'ALL' with targetType: 'LINE_ITEM'
        # Line-item specific discounts have targetType: 'LINE_ITEM' with targetSelection: 'ENTITLED' or specific line items
        return nil unless discount_allocations.present? && discount_allocations.is_a?(Array)

        discount_allocations.each do |allocation|
          discount_application = allocation.discount_application
          next unless discount_application.present?

          # Check target type and selection to determine if this is a line-item specific discount
          target_type = discount_application.try(:target_type) || 
                       discount_application.try(:targetType) ||
                       discount_application.try(:target_type)
          
          target_selection = discount_application.try(:target_selection) ||
                            discount_application.try(:targetSelection) ||
                            discount_application.try(:target_selection)

          # Line-item specific discounts have:
          # - targetType: 'LINE_ITEM' AND targetSelection: 'ENTITLED' (or specific line items)
          # Order-level discounts have:
          # - targetType: 'ORDER' OR
          # - targetType: 'LINE_ITEM' with targetSelection: 'ALL' (applied to all line items)
          
          # Skip order-level discounts
          if target_type == 'ORDER'
            Rails.logger.debug "Skipping order-level discount (targetType: ORDER)"
            next
          end
          
          if target_type == 'LINE_ITEM' && target_selection == 'ALL'
            Rails.logger.debug "Skipping order-level discount (targetType: LINE_ITEM, targetSelection: ALL)"
            next
          end

          # This is a line-item specific discount
          Rails.logger.debug "Found line-item specific discount (targetType: #{target_type}, targetSelection: #{target_selection})"
          return allocation
        end

        # No line-item specific discount found
        nil
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

      def extract_line_item_custom_attributes(node)
        return [] unless node.present?
        attrs = node.try(:custom_attributes) || node.try(:customAttributes)
        return [] unless attrs.present? && attrs.is_a?(Array)
        attrs.each_with_object([]) do |attr, arr|
          key = attr.try(:key)
          next unless key.present?
          value = (attr.try(:value) || "").to_s
          arr << { key: key, value: value }
        end
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

      def parse_codk_discounts(codk_discounts_string)
        # Format: "variantId1:discount|code,variantId2:discount|code,orderLevel:discount|code"
        # Also supports legacy: "variantId|code:discount,orderLevel|code:discount"
        # Returns: { variant_id => { discount: amount, code: code }, orderLevel: { discount: amount, code: code } }
        line_discount_map = {}
        order_level_discount = nil
        
        return { line_discounts: line_discount_map, order_level: order_level_discount } unless codk_discounts_string.present?
        
        codk_discounts_string.split(',').each do |entry|
          entry = entry.strip
          next if entry.blank?
          
          if entry.include?(':')
            parts = entry.split(':', 2)
            key_and_code = parts[0].strip
            raw_value_and_code = parts[1].strip
            
            # Check if key has discount code (format: "variantId|code" or "orderLevel|code")
            key = key_and_code
            discount_code = ""
            
            if key_and_code.include?('|')
              key_parts = key_and_code.split('|', 2)
              key = key_parts[0].strip
              discount_code = key_parts[1].strip if key_parts.length > 1
            end

            # Also support value containing code (format: "discount|code")
            value_str = raw_value_and_code
            if raw_value_and_code.include?('|')
              value_parts = raw_value_and_code.split('|', 2)
              value_str = value_parts[0].strip
              # Prefer code from value if key didn't specify it
              if discount_code.blank? && value_parts.length > 1
                discount_code = value_parts[1].strip
              end
            end

            value = value_str.to_f
            next if value.nan? || value <= 0
            
            if key.downcase == 'orderlevel'
              order_level_discount = { discount: value, code: discount_code }
            else
              # Normalize variant ID (handle both GID and numeric formats)
              variant_id = key.gsub('gid://shopify/ProductVariant/', '')
              line_discount_map[variant_id] = { discount: value, code: discount_code }
            end
          end
        end
        
        { line_discounts: line_discount_map, order_level: order_level_discount }
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
        OrderConfirmation.find_by(order_id: @order_id, shop_id: @shop.id)&.status.to_s.delete_suffix(RETRY_FAILED_SUFFIX)
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
        # Simple approach: Remove all line items and add them back to flatten any bundles
        # This breaks bundle relationships by removing and re-adding all items
        # Free gift variants are determined from _codkFreeVariants custom attribute (format: "variantID1:qty, variantID2:qty")
        # Only variants listed in _codkFreeVariants will receive 100% discount

        step_status = current_step_status
        if step_status == PARTIAL_PAID_STATUS
          Rails.logger.info "Order #{@order_id} is already #{PARTIAL_PAID_STATUS}. Skipping bundle flattening."
          return { message: "Order already partially paid (skip)", processed: false, already_flattened: true }
        end

        # BundleTwoCommit got halfway (copies added, originals still present) - only it can finish that safely
        if step_status == ADDED_STEP_STATUS
          return { error: "Step marker #{step_status} changed during handover - stopping" } if @delegated
          return BundleTwoCommit.call(@shop, @order_id, true)
        end

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
          if order_custom_attributes[BUNDLE_FLATTENED_ATTRIBUTE_KEY] == BUNDLE_FLATTENED_ATTRIBUTE_VALUE || step_status == FLATTENED_STEP_STATUS
            Rails.logger.info "Order #{@order_id} already flattened (#{BUNDLE_FLATTENED_ATTRIBUTE_KEY} attribute or #{FLATTENED_STEP_STATUS}). Skipping operation for idempotency."

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
        
        # Initialize variables outside begin block for scope accessibility
        order_level_discounts = []
        variants_to_restore = []
        
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

          # Parse _codkDiscounts to get exact discount amounts per variant
          codk_discounts_string = order_custom_attributes['_codkDiscounts']
          codk_discounts_parsed = parse_codk_discounts(codk_discounts_string)
          line_discount_map = codk_discounts_parsed[:line_discounts] || {}
          Rails.logger.info "Parsed _codkDiscounts - Line discounts: #{line_discount_map.inspect}, Order level: #{codk_discounts_parsed[:order_level].inspect}"

          # _codkDiscounts carries ONE total per variant, but a variant can span
          # several line items (a BOGO free unit, or lines split by properties).
          # Each variant's total is drawn from this quota so the second line can
          # never claim a second copy of the same discount.
          remaining_line_discounts = line_discount_map.transform_values { |data| data[:discount].to_f }

          # Extract order-level discounts (these will be re-applied at order level, not line item level)
          # If _codkDiscounts has order-level discount, use that; otherwise extract from discountApplications
          order_level_discounts = extract_order_level_discounts(original_order_response)
          if codk_discounts_parsed[:order_level].present?
            # Use order-level discount from _codkDiscounts
            order_level_discount = codk_discounts_parsed[:order_level]
            order_level_discounts = [{
              fixedValue: {
                amount: order_level_discount[:discount]
                # No currencyCode here: apply_order_level_discount_as_line_discounts
                # falls back to the real line item currency when this is absent.
                # A hardcoded "USD" here previously overrode that fallback and
                # mislabeled the discount currency on every non-USD store.
              },
              description: order_level_discount[:code].present? ? order_level_discount[:code] : "Order discount"
            }]
            Rails.logger.info "Using order-level discount from _codkDiscounts: #{order_level_discount.inspect}"
          end
          Rails.logger.info "Found #{order_level_discounts.count} order-level discount(s) to preserve"

          line_items_edges = original_order_response.data.order.line_items.edges
          Rails.logger.info "Fetched order with #{line_items_edges.count} line items from GraphQL"
          
          # Collect all variants with their quantities and discount metadata
          variants_to_restore = []  # Array of {variant_id, quantity, discount_info, free_variant}
          
            line_items_edges.each do |edge|
              node = edge.node
              variant = node.variant
              next unless variant.present?

              variant_id = variant.id
              variant_id_numeric = variant_id.gsub("gid://shopify/ProductVariant/", "")
              quantity = node.quantity
              
              # Check if variant is a free gift (listed in _codkFreeVariants)
              free_variant = is_free_gift_variant?(variant_id_numeric, order_custom_attributes)

              # Use discount from _codkDiscounts if available, otherwise fall back to build_discount_info
              discount_info = nil
              if line_discount_map[variant_id_numeric].present?
                # Use exact discount amount from _codkDiscounts
                discount_data = line_discount_map[variant_id_numeric]
                discount_code = discount_data[:code]
                remaining_discount = remaining_line_discounts[variant_id_numeric].to_f
                total_discount_amount = [discount_data[:discount].to_f, remaining_discount].min

                if total_discount_amount <= 0
                  Rails.logger.info "Skipping _codkDiscounts for variant #{variant_id_numeric}: quota of #{discount_data[:discount]} already applied to an earlier line item"
                else
                  remaining_line_discounts[variant_id_numeric] = remaining_discount - total_discount_amount

                  # Get currency code from the line item
                  currency_code = extract_currency_code(node, nil)

                  # Shopify applies fixedValue discounts per unit, so we need to divide by quantity
                  # to get the per-unit discount amount
                  per_unit_discount = total_discount_amount / quantity.to_f

                  discount_info = {
                    fixedValue: {
                      amount: per_unit_discount.round(2),
                      currencyCode: currency_code
                    }
                  }
                  discount_info[:description] = discount_code if discount_code.present?
                  Rails.logger.info "Using discount from _codkDiscounts for variant #{variant_id_numeric}: total=#{total_discount_amount}, quantity=#{quantity}, per_unit=#{per_unit_discount.round(2)} #{currency_code}, remaining=#{remaining_line_discounts[variant_id_numeric]}"
                end
              else
                # Fall back to extracting from discountAllocations
                discount_info = build_discount_info(node, free_variant: free_variant)
              end

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

              # Extract unit price and currency from original line item
              unit_price = 0
              currency_code = "USD"
              if node.original_unit_price_set&.shop_money
                unit_price = node.original_unit_price_set.shop_money.amount.to_f
                currency_code = node.original_unit_price_set.shop_money.currency_code || "USD"
              end

              custom_attributes = extract_line_item_custom_attributes(node)

              variants_to_restore << {
                variant_id: variant_id_numeric,
                quantity: quantity,
                discount_info: discount_info,
                free_variant: free_variant,
                calculated_line_item_id: nil,
                unit_price: unit_price,
                currency_code: currency_code,
                custom_attributes: custom_attributes
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

        # Removal already committed on a previous run - re-read order still has the original
        # quantities, so jump straight to adding the variants back
        if step_status == REMOVED_STEP_STATUS
          Rails.logger.info "Order #{@order_id} has #{REMOVED_STEP_STATUS} marker - skipping STEP 1-2 (remove + first commit)"
        else
          # STEP 1: Start order edit session and remove all line items
          Rails.logger.info "Starting order edit session to remove all line items"
          calculated_order = get_calculated_order
          calculated_order_id = calculated_order&.data&.order_edit_begin&.calculated_order&.id

          unless calculated_order_id.present?
            Rails.logger.error "Calculated order ID is blank"
            return { error: "Could not begin order edit" }
          end

          calculated_line_items = calculated_order&.data&.order_edit_begin&.calculated_order&.line_items&.edges
          unless calculated_line_items.present? && calculated_line_items.is_a?(Array)
            Rails.logger.error "No valid line items found in calculated order"
            return { error: "No line items found in calculated order" }
          end

          Rails.logger.info "Found #{calculated_line_items.count} line item(s) in calculated order"

          # Map calculated line item IDs back to the variants we plan to restore
          calculated_line_items.each do |edge|
            node = edge.node
            variant_id = node.variant&.id
            variant_id_numeric = variant_id&.gsub("gid://shopify/ProductVariant/", "") || ""

            variant_info = variants_to_restore.find do |variant|
              variant[:variant_id] == variant_id_numeric && variant[:calculated_line_item_id].blank?
            end

            next unless variant_info
            variant_info[:calculated_line_item_id] = node.id
          end
          
          # Remove line items (set quantity to 0) so bundles are flattened (including free variants)
          variants_to_restore.each do |variant_info|
            line_item_id = variant_info[:calculated_line_item_id]
            next unless line_item_id.present?

            variant_id_numeric = variant_info[:variant_id]
            Rails.logger.info "Removing line item: #{line_item_id} (variant: #{variant_id_numeric})"
            remove_response = remove_bundle_line_item(calculated_order_id, line_item_id)
            
            if remove_response&.data&.order_edit_set_quantity&.user_errors&.any?
              Rails.logger.error "Error removing line item: #{remove_response.data.order_edit_set_quantity.user_errors}"
            else
              Rails.logger.info "Successfully removed line item: #{line_item_id}"
            end
          end
          
          # STEP 2: Commit the removals (first commit)
          Rails.logger.info "Committing first change: removing all line items"
          first_commit_response = commit_order(calculated_order_id, staff_note: "Removing bundle items")
          
          if first_commit_response&.data&.order_edit_commit&.user_errors&.any?
            errors = first_commit_response.data.order_edit_commit.user_errors
            error_messages = errors.map { |e| e.message }.join(", ")
            Rails.logger.error "Error in first commit (removal): #{error_messages}"
            return { error: "Error committing order removal", errors: first_commit_response.data.order_edit_commit.user_errors }
          end
          
          Rails.logger.info "First commit successful - all line items removed"
          set_step_status(REMOVED_STEP_STATUS)
        end

        # STEP 3: Start a new order edit session to add variants back
        Rails.logger.info "Starting new order edit session to add variants back as independent items"
        calculated_order = get_calculated_order
        new_calculated_order_id = calculated_order&.data&.order_edit_begin&.calculated_order&.id
        
        unless new_calculated_order_id.present?
          Rails.logger.error "Could not start new order edit session after first commit"
          return { error: "Could not start new order edit session" }
        end
        
        # STEP 4: Add each variant back as an independent line item and apply discounts if needed
        # Track line items for order-level discount application
        added_line_items = []
        
        variants_to_restore.each do |variant_info|
          Rails.logger.info "Adding variant #{variant_info[:variant_id]} back with quantity #{variant_info[:quantity]} as independent item"
          add_response = add_variant(new_calculated_order_id, variant_info[:variant_id], variant_info[:quantity])
          
          if add_response&.data&.order_edit_add_variant&.user_errors&.any?
            errors = add_response.data.order_edit_add_variant.user_errors
            error_messages = errors.map { |e| e.message }.join(", ")
            Rails.logger.error "Error adding variant #{variant_info[:variant_id]}: #{error_messages}"
          else
            Rails.logger.info "Successfully added variant #{variant_info[:variant_id]} with quantity #{variant_info[:quantity]} as independent item"
            
            calculated_line_item = add_response&.data&.order_edit_add_variant&.calculated_line_item
            
            if calculated_line_item.present?
              added_line_item_id = calculated_line_item.id
              
              # Track line item for order-level discount application
              unit_price = variant_info[:unit_price] || 0
              currency_code = variant_info[:currency_code] || "USD"
              added_line_items << {
                id: added_line_item_id,
                quantity: variant_info[:quantity],
                unit_price: unit_price,
                currency_code: currency_code
              }
              
              # Apply discount if it existed on the original line item
              discount_input = variant_info[:discount_info]
              if discount_input.present?
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
                discount_response = add_line_item_discount(new_calculated_order_id, added_line_item_id, discount_input)
                
                if discount_response&.data&.order_edit_add_line_item_discount&.user_errors&.any?
                  errors = discount_response.data.order_edit_add_line_item_discount.user_errors
                  error_messages = errors.map { |e| e.message }.join(", ")
                  Rails.logger.error "Error applying discount to variant #{variant_info[:variant_id]}: #{error_messages}"
                else
                  Rails.logger.info "Successfully applied #{log_discount} to variant #{variant_info[:variant_id]}"
                end
              end
            else
              Rails.logger.warn "Could not find calculated line item for variant #{variant_info[:variant_id]}"
            end
          end
        end
        
        # STEP 5: Re-apply order-level discounts as line-item discounts
        # Shopify's Order Edit API does not support adding order-level discounts directly.
        # We need to apply them as line-item discounts proportionally to all line items.
        if order_level_discounts.present? && order_level_discounts.any?
          Rails.logger.info "Re-applying #{order_level_discounts.count} order-level discount(s) as line-item discounts"
          
          if added_line_items.empty?
            Rails.logger.warn "No line items found - cannot apply order-level discounts"
          else
            Rails.logger.info "Found #{added_line_items.count} line item(s) to apply order-level discounts to"
            
            order_level_discounts.each do |order_discount|
              log_discount =
                if order_discount[:percentValue].present?
                  "#{order_discount[:percentValue]}% order discount"
                elsif order_discount[:fixedValue].present?
                  fixed_value = order_discount[:fixedValue]
                  "#{fixed_value[:amount]} #{fixed_value[:currencyCode]} order discount"
                else
                  "order discount"
                end
              Rails.logger.info "Applying order-level discount as line-item discounts: #{log_discount} (#{order_discount[:description]})"
              
              apply_order_level_discount_as_line_discounts(new_calculated_order_id, order_discount, added_line_items)
            end
          end
        else
          Rails.logger.info "No order-level discounts found"
        end
        
        # STEP 6: Commit the additions (second commit)
        Rails.logger.info "Committing second change: adding #{variants_to_restore.count} variant(s) back as independent items"
        second_commit_response = commit_order(new_calculated_order_id, staff_note: "Bundle flattened")
        
        if second_commit_response&.data&.order_edit_commit&.user_errors&.any?
          errors = second_commit_response.data.order_edit_commit.user_errors
          error_messages = errors.map { |e| e.message }.join(", ")
          Rails.logger.error "Error in second commit (addition): #{error_messages}"
          return { error: "Error committing order addition", errors: second_commit_response.data.order_edit_commit.user_errors }
        else
          Rails.logger.info "Second commit successful - variants added back as independent items"
          set_step_status(FLATTENED_STEP_STATUS)

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



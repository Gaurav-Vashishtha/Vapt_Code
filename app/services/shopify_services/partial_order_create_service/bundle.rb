module ShopifyServices
  class PartialOrderCreateService
    class Bundle < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :order_id

      # ShopifyServices::PartialOrderCreateService::Bundle.call(shop, order_id)
      def initialize(client, shop, order_id)
        @client = client
        @shop = shop
        @order_id = order_id
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
            currentTotalDiscountsSet{
              shopMoney{
                amount
                currencyCode
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

      def parse_codk_discounts(codk_discounts_string)
        # Format: "variantId1:discount|code,variantId2:discount|code,orderLevel:discount|code"
        # Also supports legacy: "variantId|code:discount,orderLevel|code:discount"
        #
        # Returns:
        #  {
        #    line_discounts: { "536..." => { discount: 1199.0, code: "buy1get2..." }, ... },
        #    order_level: { discount: 350.0, code: "350_Order" } | nil
        #  }
        line_discount_map = {}
        order_level_discount = nil

        return { line_discounts: line_discount_map, order_level: order_level_discount } unless codk_discounts_string.present?

        codk_discounts_string.split(',').each do |entry|
          entry = entry.strip
          next if entry.blank?

          next unless entry.include?(':')

          parts = entry.split(':', 2)
          key_and_code = parts[0].strip
          raw_value_and_code = parts[1].strip

          # Code can be in key (variantId|code:amount)
          key = key_and_code
          discount_code = ""
          if key_and_code.include?('|')
            key_parts = key_and_code.split('|', 2)
            key = key_parts[0].strip
            discount_code = key_parts[1].strip if key_parts.length > 1
          end

          # Or code can be in value (variantId:amount|code)
          value_str = raw_value_and_code
          if raw_value_and_code.include?('|')
            value_parts = raw_value_and_code.split('|', 2)
            value_str = value_parts[0].strip
            if discount_code.blank? && value_parts.length > 1
              discount_code = value_parts[1].strip
            end
          end

          value = value_str.to_f
          next if value.nan? || value <= 0

          if key.downcase == 'orderlevel'
            order_level_discount = { discount: value, code: discount_code }
          else
            variant_id = key.gsub('gid://shopify/ProductVariant/', '')
            line_discount_map[variant_id] = { discount: value, code: discount_code }
          end
        end

        { line_discounts: line_discount_map, order_level: order_level_discount }
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
          return {
            percentValue: 100.0,
            description: discount_description
          }
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

      def is_free_gift_variant?(variant_id_numeric, order_custom_attributes)
        # Check if variant is listed in _codkFreeVariants
        codk_free_variants = order_custom_attributes['_codkFreeVariants']
        return false unless codk_free_variants.present?
        
        free_variant_ids = parse_codk_free_variants(codk_free_variants)
        free_variant_ids.include?(variant_id_numeric)
      end

      def extract_order_level_discounts(order_response)
        return {} unless order_response&.data&.order.present?
        
        order = order_response.data.order
        discounts = {}
        
        # Extract currency code from order
        total_discount_set = order.try(:current_total_discounts_set) || order.try(:currentTotalDiscountsSet)
        currency_code = "USD"
        if total_discount_set.present?
          shop_money = total_discount_set.try(:shop_money) || total_discount_set.try(:shopMoney)
          if shop_money&.currency_code.present? || shop_money&.currencyCode.present?
            currency_code = shop_money.currency_code || shop_money.currencyCode || "USD"
          end
        end
        discounts[:currency_code] = currency_code
        
        # Extract discount applications (order-level discounts only)
        discount_applications_connection = order.try(:discount_applications) || order.try(:discountApplications)
        discount_application_nodes = []

        if discount_applications_connection.respond_to?(:nodes)
          discount_application_nodes = discount_applications_connection.nodes
        elsif discount_applications_connection.respond_to?(:edges)
          discount_application_nodes = discount_applications_connection.edges.map(&:node)
        elsif discount_applications_connection.present?
          discount_application_nodes = Array(discount_applications_connection)
        end

        if discount_application_nodes.any?
          order_level_discounts = []
          discount_application_nodes.each do |discount_app|
            # Only include order-level discounts (not line-item specific)
            target_type = discount_app.try(:target_type) || discount_app.try(:targetType)
            target_selection = discount_app.try(:target_selection) || discount_app.try(:targetSelection)
            
            # Order-level discounts have:
            # - targetType: 'ORDER' OR
            # - targetType: 'LINE_ITEM' with targetSelection: 'ALL' (applied to all line items)
            # Line-item specific discounts have:
            # - targetType: 'LINE_ITEM' with targetSelection: 'ENTITLED' (applied to specific line items)
            is_order_level = target_type == 'ORDER' || (target_type == 'LINE_ITEM' && target_selection == 'ALL')
            
            if is_order_level
              value_payload = extract_discount_application_value(discount_app)
              discount_info = {
                value_type: value_payload[:value_type], # Inferred from value structure
                value: value_payload[:value],
                currency_code: value_payload[:currency_code] || currency_code,
                percentage: value_payload[:percentage],
                title: discount_app.try(:title),
                code: discount_app.respond_to?(:code) ? discount_app.code : nil
              }
              order_level_discounts << discount_info
              Rails.logger.info "Found order-level discount: #{discount_info.inspect}"
            else
              Rails.logger.debug "Skipping line-item specific discount (targetType: #{target_type}, targetSelection: #{target_selection})"
            end
          end
          if order_level_discounts.any?
            discounts[:applications] = order_level_discounts
            
            # Calculate total order-level discount amount from applications only
            total_order_level_discount = 0
            order_level_discounts.each do |discount_app|
              if discount_app[:value_type] == 'FIXED_AMOUNT' && discount_app[:value].present?
                total_order_level_discount += discount_app[:value].to_f
              elsif discount_app[:value_type] == 'PERCENTAGE' && discount_app[:percentage].present?
                # For percentage discounts, we can't calculate here without subtotal
                # These will need to be handled separately
                Rails.logger.warn "Percentage order-level discount found - cannot calculate exact amount without subtotal"
              end
            end
            discounts[:total_discount_amount] = total_order_level_discount if total_order_level_discount > 0
          else
            Rails.logger.info "No order-level discounts found - all discounts are line-item specific"
            discounts[:total_discount_amount] = 0
          end
        else
          Rails.logger.info "No discount applications found"
          discounts[:total_discount_amount] = 0
        end
        
        Rails.logger.info "Extracted order-level discounts: #{discounts.inspect}"
        discounts
      end

      def extract_discount_application_value(discount_application)
        value_obj = discount_application.try(:value)
        return { value: nil, value_type: nil } unless value_obj.present?

        if value_obj.respond_to?(:amount)
          {
            value: value_obj.amount.to_f,
            currency_code: value_obj.currency_code || value_obj.currencyCode,
            value_type: 'FIXED_AMOUNT'
          }
        elsif value_obj.respond_to?(:percentage)
          {
            value: value_obj.percentage.to_f,
            percentage: value_obj.percentage.to_f,
            value_type: 'PERCENTAGE'
          }
        else
          { value: nil, value_type: nil }
        end
      end

      def flatten_line_items
        # Get original order from GraphQL to collect all line items
        original_order_response = get_original_order
        
        unless original_order_response&.data&.order&.line_items&.edges.present?
          Rails.logger.error "Could not fetch order from GraphQL or no line items"
          return { error: "Could not fetch order from GraphQL", flattened_items: [], order_discounts: {} }
        end

        # Extract order custom attributes
        order_custom_attributes = extract_order_custom_attributes(original_order_response)
        codk_free_variants = order_custom_attributes['_codkFreeVariants']
        free_variant_ids_list = parse_codk_free_variants(codk_free_variants)
        Rails.logger.info "Order custom attributes - _codkFreeVariants: #{codk_free_variants}, Free variant IDs: #{free_variant_ids_list.inspect}"

        # Parse _codkDiscounts (exact per-variant discount totals + codes)
        codk_discounts_string = order_custom_attributes['_codkDiscounts']
        codk_discounts_parsed = parse_codk_discounts(codk_discounts_string)
        line_discount_map = codk_discounts_parsed[:line_discounts] || {}
        Rails.logger.info "Parsed _codkDiscounts - Line discounts: #{line_discount_map.inspect}, Order level: #{codk_discounts_parsed[:order_level].inspect}"

        # _codkDiscounts carries ONE total per variant, but a variant can span
        # several line items (a BOGO free unit, or lines split by properties).
        # Each variant's total is drawn from this quota so the second line can
        # never claim a second copy of the same discount.
        remaining_line_discounts = line_discount_map.transform_values { |data| data[:discount].to_f }

        # Extract order-level discounts
        order_discounts = extract_order_level_discounts(original_order_response)

        line_items_edges = original_order_response.data.order.line_items.edges
        Rails.logger.info "Fetched order with #{line_items_edges.count} line items from GraphQL"
        
        # Collect all variants with their quantities and discount metadata
        flattened_items = []  # Array of {variant_id, quantity, discount_info, free_variant}
        
        line_items_edges.each do |edge|
          node = edge.node
          variant = node.variant
          next unless variant.present?

          variant_id = variant.id
          variant_id_numeric = variant_id.gsub("gid://shopify/ProductVariant/", "")
          quantity = node.quantity
          
          # Check if variant is a free gift (listed in _codkFreeVariants)
          free_variant = is_free_gift_variant?(variant_id_numeric, order_custom_attributes)

          # Prefer exact discount totals from _codkDiscounts when available.
          # Note: the _codkDiscounts values are TOTAL discount for the line (not per-unit).
          discount_info = nil
          if line_discount_map[variant_id_numeric].present?
            discount_data = line_discount_map[variant_id_numeric]
            discount_code = discount_data[:code].to_s
            remaining_discount = remaining_line_discounts[variant_id_numeric].to_f
            discount_amount_total = [discount_data[:discount].to_f, remaining_discount].min

            if discount_amount_total <= 0
              Rails.logger.info "Skipping _codkDiscounts for variant #{variant_id_numeric}: quota of #{discount_data[:discount]} already applied to an earlier line item"
            else
              remaining_line_discounts[variant_id_numeric] = remaining_discount - discount_amount_total

              currency_code = extract_currency_code(node, nil)
              discount_info = {
                fixedValue: {
                  amount: discount_amount_total,
                  currencyCode: currency_code
                }
              }
              # Use title/description from _codkDiscounts so Shopify UI shows the right discount name
              discount_info[:description] = discount_code if discount_code.present?
              Rails.logger.info "Using discount from _codkDiscounts for variant #{variant_id_numeric}: total=#{discount_amount_total} #{currency_code}, qty=#{quantity}, code=#{discount_code}, remaining=#{remaining_line_discounts[variant_id_numeric]}"
            end
          else
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

          custom_attributes = extract_line_item_custom_attributes(node)

          flattened_items << {
            variant_id: variant_id_numeric,
            quantity: quantity,
            discount_info: discount_info,
            free_variant: free_variant,
            custom_attributes: custom_attributes
          }
        end
        
        if flattened_items.empty?
          Rails.logger.info "No line items found in order #{@order_id}"
          return { error: "No line items found in order", flattened_items: [], order_discounts: order_discounts }
        end
        
        free_variants_count = flattened_items.count { |variant| variant[:free_variant] }
        Rails.logger.info "Found #{flattened_items.count} variant(s) to flatten (#{free_variants_count} free variant(s) will receive 100% discount)"

        { flattened_items: flattened_items, order_custom_attributes: order_custom_attributes, order_discounts: order_discounts }
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

      def build_draft_order_line_items(flattened_items)
        line_items = []
        
        flattened_items.each do |item|
          variant_id_numeric = item[:variant_id]
          quantity = item[:quantity]
          discount_info = item[:discount_info]
          custom_attributes = item[:custom_attributes]
          
          # Build line item for draft order
          line_item = {
            variantId: "gid://shopify/ProductVariant/#{variant_id_numeric}",
            quantity: quantity
          }
          line_item[:customAttributes] = custom_attributes if custom_attributes.present?

          # Apply discount if present
          if discount_info.present?
            if discount_info[:percentValue].present?
              # Draft order line-item discounts use DraftOrderAppliedDiscountInput (same shape as order-level).
              line_item[:appliedDiscount] = {
                valueType: 'PERCENTAGE',
                value: discount_info[:percentValue],
                title: discount_info[:description].presence || "Discount",
                description: discount_info[:description].presence || "Discount"
              }
            elsif discount_info[:fixedValue].present?
              # Draft order line-item FIXED_AMOUNT is applied per-unit in Shopify (same as Order Edit).
              # Our stored amount is the TOTAL discount for the whole line item, so divide by quantity.
              fixed_amount_total = discount_info[:fixedValue][:amount].to_f
              per_unit_value = quantity.to_i > 0 ? (fixed_amount_total / quantity.to_f) : fixed_amount_total

              line_item[:appliedDiscount] = {
                valueType: 'FIXED_AMOUNT',
                value: per_unit_value.round(2),
                title: discount_info[:description].presence || "Discount",
                description: discount_info[:description].presence || "Discount"
              }
            end
          end
          
          line_items << line_item
        end
        
        line_items
      end

      def get_discount_amount
        @order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
        @order_confirmation.order_amount.to_f
      end

      def get_total_amount
        @order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
        @order_confirmation.order_amount.to_f + @order_confirmation.cod_fee - get_discount_amount
      end

      def get_address(params, key)
        return unless params[key]
        country_code = params[key]['countryCodeV2']
        %w[countryCodeV2 formattedArea latitude longitude name formatted].each do |field|
          params[key].delete(field)
        end
        normalize_address_phone(params[key], country_code)
        params[key]
      end

      # Shopify's draftOrderCreate validates the address phone against the
      # country (stricter than order import). Normalize to E.164 so valid
      # numbers pass; drop the phone only if it's genuinely invalid so the
      # draft order can still be created instead of failing entirely.
      def normalize_address_phone(address, country_code)
        phone = address['phone']
        return if phone.blank?

        parsed = Phonelib.parse(phone, country_code)
        if parsed.valid?
          address['phone'] = parsed.e164
        else
          Rails.logger.warn "Invalid address phone '#{phone}' (country: #{country_code}); dropping phone for draft order #{@order_id}"
          address.delete('phone')
        end
      rescue => e
        Rails.logger.error "Phonelib parse error for '#{phone}' (country: #{country_code}): #{e.message}; dropping phone"
        address.delete('phone')
      end

      def get_applied_discount(params, order_confirmation, order_discounts = {}, line_item_discounts_total = 0)
        total_tax = 0

        # Prefer the shop's live Shopify tax setting (fetched alongside the
        # order) over the manual app setting, which defaults to false and is
        # easy to leave unset — that mismatch is what caused this discount to
        # be short by the original order's tax amount for tax-inclusive shops.
        taxes_included = params['taxesIncluded']
        taxes_included = order_confirmation.shop.setting.is_tax_included_with_product if taxes_included.nil?

        unless taxes_included
          total_tax = params['currentTaxLines'].to_a.sum do |tax_line|
            tax_line.dig('priceSet', 'shopMoney', 'amount').to_f
          end
        end

        # Calculate order-level discount from extracted order-level discounts
        # Only use order-level discounts, not line-item discounts
        # Use the total_order_level_discount from extracted discounts (calculated from applications only)
        order_level_discount_amount = 0
        order_level_discount_code = nil
        currency_code = order_discounts[:currency_code] || params.dig('currentTotalDiscountsSet', 'shopMoney', 'currencyCode') || params['currencyCode'] || 'USD'
        
        if order_discounts[:total_discount_amount].present?
          # Use the pre-calculated total from extract_order_level_discounts
          order_level_discount_amount = order_discounts[:total_discount_amount].to_f
          # Extract discount code/title from applications if available
          if order_discounts[:applications].present? && order_discounts[:applications].is_a?(Array) && order_discounts[:applications].any?
            # Use the first order-level discount's title or code
            first_discount = order_discounts[:applications].first
            order_level_discount_code = first_discount[:title] || first_discount[:code]
          end
          Rails.logger.info "Using extracted order-level discount amount: #{order_level_discount_amount}, code: #{order_level_discount_code}"
        elsif order_discounts[:applications].present? && order_discounts[:applications].is_a?(Array)
          # Calculate from individual applications if total not provided
          order_discounts[:applications].each do |discount_app|
            if discount_app[:value_type] == 'FIXED_AMOUNT' && discount_app[:value].present?
              order_level_discount_amount += discount_app[:value].to_f
              # Use the first discount's title or code
              order_level_discount_code ||= discount_app[:title] || discount_app[:code]
            elsif discount_app[:value_type] == 'PERCENTAGE' && discount_app[:percentage].present?
              # For percentage discounts, we need the subtotal to calculate
              # For now, we'll skip percentage order-level discounts or calculate from subtotal
              Rails.logger.warn "Percentage order-level discount found - cannot calculate exact amount without subtotal"
              # Still extract the code for the title
              order_level_discount_code ||= discount_app[:title] || discount_app[:code]
            end
          end
          Rails.logger.info "Calculated order-level discount from applications: #{order_level_discount_amount}, code: #{order_level_discount_code}"
        else
          # No order-level discounts found
          Rails.logger.info "No order-level discounts found - all discounts are line-item specific"
        end

        # Calculate upfront payment discount
        upfront_received = get_discount_amount.to_f
        upfront_base = [upfront_received - total_tax, 0].max

        # Combine order-level discount with upfront payment discount
        # Note: Line-item discounts are already applied via appliedDiscount on line items
        total_discount = order_level_discount_amount + upfront_base

        Rails.logger.info "Discount calculation - Order-level discount: #{order_level_discount_amount}, Upfront: #{upfront_base}, Final total: #{total_discount}"

        # Build title with order-level discount code if available
        title = if order_level_discount_amount > 0
          if order_level_discount_code.present?
            "#{order_level_discount_code} + Payment Received Upfront (Online)"
          else
            "Order Discount + Payment Received Upfront (Online)"
          end
        else
          'Payment Received Upfront (Online)'
        end

        {
          amount: total_discount.round(2).to_s,
          valueType: 'FIXED_AMOUNT',
          value: total_discount.round(2),
          title: title
        }
      end

      def calculate_line_item_discounts_total(flattened_items)
        flattened_items.sum do |item|
          discount_info = item[:discount_info]
          next 0 unless discount_info.present?
          
          if discount_info[:fixedValue].present?
            discount_info[:fixedValue][:amount].to_f
          elsif discount_info[:percentValue].present?
            # For percentage discounts, we can't calculate the exact amount here
            # as we don't have the line item price. These should be handled separately
            # or the percentage discount should be converted to fixed amount earlier
            # For now, return 0 and log a warning
            Rails.logger.warn "Percentage discount found on line item - cannot calculate exact amount for discount subtraction"
            0
          else
            0
          end
        end
      end

      def create_draft_order(order_confirmation, flattened_line_items, order_discounts = {}, line_item_discounts_total = 0)
        params = ShopifyServices::OrderFullGetService.call(@shop, order_confirmation.order_id)
        return unless params

        tags = params['tags'] || []
        tags.push('Partial-Payment-Received')

        shippingLine = {}
        if params.dig('totalShippingPriceSet', 'shopMoney', 'amount')
          shippingLine = {
            priceWithCurrency: {
              amount: params.dig('totalShippingPriceSet', 'shopMoney', 'amount'),
              currencyCode: params.dig('totalShippingPriceSet', 'shopMoney', 'currencyCode')
            },
            title: 'Partial-Payment-Shipping'
          }
        end

        query = @client.parse <<-'GRAPHQL'
          mutation ($input: DraftOrderInput!) {
            draftOrderCreate(input: $input) {
              draftOrder {
                id
                invoiceUrl
                totalPrice
                status
                note2
                name
                currencyCode
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
            appliedDiscount: get_applied_discount(params, order_confirmation, order_discounts, line_item_discounts_total),
            billingAddress: get_address(params, 'billingAddress'),
            customerId: order_confirmation.customer_id.present? ? "gid://shopify/Customer/#{order_confirmation.customer_id.gsub("gid://shopify/Customer/", "")}" : "",
            note: "Partial Order created from Original Order #{order_confirmation.order_id} (Bundle Flattened).",
            email: order_confirmation.customer_email,
            lineItems: flattened_line_items,
            shippingAddress: get_address(params, 'shippingAddress'),
            tags: tags.join(","),
            taxExempt: false,
            shippingLine: shippingLine
          }
        }

        copied_attrs = PartialOrderAttributionCopy.draft_custom_attributes_from_original_order(@shop, order_confirmation.order_id)
        variables[:input][:customAttributes] = copied_attrs if copied_attrs.present?

        Rails.logger.info "Draft order variables: #{variables.inspect}"
        resp = @client.query(query, variables: variables)
        Rails.logger.info "Draft order response: #{resp.inspect}"
        resp
      end

      def create_order_from_draft_order(resp, order_confirmation)
        if resp&.data&.draft_order_create&.draft_order
          @shop.init_session
          draft_order = ShopifyAPI::DraftOrder.find(resp.data.draft_order_create.draft_order.id.gsub('gid://shopify/DraftOrder/', ''))

          if draft_order.complete(payment_pending: true)
            order_confirmation.update(draft_order_id: draft_order.order_id, status: 'COD-Partial-Payment-Received')
            order_confirmation.update(prepaid_status: "Order Created #{draft_order.order_id}")
            return draft_order.order_id
          else
            raise "Unable to complete draft order for shop for order #{order_confirmation.id}"
          end
        end
        nil
      end

      def cancel_original_order(order_confirmation)
        begin
          @shop.init_session
          order = ShopifyAPI::Order.find(order_confirmation.order_id)
          original_order_total = order.current_total_price.to_f
          
          order.cancel(reason: 'declined', email: false)

          if order_confirmation.shop.setting.auto_delete
            ShopifyAPI::Order.delete(order_confirmation.order_id)
          end
          
          # Return original order total for updating order_confirmation
          original_order_total
        rescue ActiveResource::ResourceNotFound => e
          Rails.logger.warn("Order not found for cancellation: #{order_confirmation.order_id} - #{e.message}")
          nil
        rescue ActiveResource::ConnectionError => e
          Rails.logger.error("HTTP error while cancelling order #{order_confirmation.order_id}: #{e.message}")
          nil
        rescue => e
          Rails.logger.error("Unexpected error in cancel_original_order: #{e.message}")
          nil
        end
      end

      def call
        begin
          order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
          unless order_confirmation
            Rails.logger.error "OrderConfirmation not found for order #{@order_id}"
            return { error: "OrderConfirmation not found" }
          end

          # Step 1: Flatten line items from the original order
          flatten_result = flatten_line_items
          if flatten_result[:error]
            Rails.logger.error "Error flattening line items: #{flatten_result[:error]}"
            return flatten_result
          end

          flattened_items = flatten_result[:flattened_items]
          if flattened_items.empty?
            Rails.logger.error "No flattened items to process"
            return { error: "No line items to process" }
          end

          # Extract order-level discounts from flatten result
          order_discounts = flatten_result[:order_discounts] || {}

          # Step 2: Build draft order line items with discounts
          draft_line_items = build_draft_order_line_items(flattened_items)
          Rails.logger.info "Built #{draft_line_items.count} line items for draft order"

          # Calculate total line item discounts that are already applied via appliedDiscount
          line_item_discounts_total = calculate_line_item_discounts_total(flattened_items)
          Rails.logger.info "Total line item discounts applied: #{line_item_discounts_total}"

          # Step 3: Create draft order with order-level discounts
          draft_order_resp = create_draft_order(order_confirmation, draft_line_items, order_discounts, line_item_discounts_total)

          if draft_order_resp.to_h.dig('data', 'draftOrderCreate', 'draftOrder', 'id')
            order_confirmation.update(prepaid_status: "Draft Order Created #{draft_order_resp.to_h.dig('data', 'draftOrderCreate', 'draftOrder', 'id')}")
          end

          if draft_order_resp&.data&.draft_order_create&.user_errors&.any?
            errors = draft_order_resp.data.draft_order_create.user_errors
            error_messages = errors.map { |e| e.message }.join(", ")
            Rails.logger.error "Error creating draft order: #{error_messages}"
            return { error: "Error creating draft order", errors: errors }
          end

          # Step 4: Create order from draft order
          new_order_id = create_order_from_draft_order(draft_order_resp, order_confirmation)

          unless new_order_id
            Rails.logger.error "Failed to create order from draft order"
            return { error: "Failed to create order from draft order" }
          end

          # Step 5: Cancel original order
          if order_confirmation.draft_order_id
            # Get original order total before cancelling
            original_order_total = cancel_original_order(order_confirmation)
            
            # Get new order total
            @shop.init_session
            new_order = ShopifyAPI::Order.find(order_confirmation.draft_order_id)
            
            if new_order.present?
              new_order_total = new_order.total_price.to_f
              
              # Update order confirmation with new order total + original order current total
              if original_order_total.present?
                updated_total = new_order_total + original_order_total
                order_confirmation.update(order_amount: updated_total)
                Rails.logger.info "Updated order_confirmation order_amount: #{updated_total} (new_order: #{new_order_total} + original_order: #{original_order_total})"
              else
                # Fallback: just use new order total if original order total couldn't be retrieved
                order_confirmation.update(order_amount: new_order_total)
                Rails.logger.warn "Could not get original order total, using only new order total: #{new_order_total}"
              end
              
              order_confirmation.update(prepaid_status: "Original Order Cancelled")
              ShopifyJobs::OrderTagPostJob.perform_async(@shop.id, order_confirmation.draft_order_id, 'Partial_Payment_Order')
              return new_order.order_status_url
            end
          end

          { error: "Order created but could not retrieve order status URL" }
        rescue => e
          Rails.logger.error "Error in PartialOrderCreateService::Bundle: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          SlackNotifyJob.perform_async(":rage:  (#{Rails.env})\n *Error* in Bundle Partial order creation for order #{@order_id} -> #{@shop.shopify_domain} error: #{e.message} #{e.backtrace.first(5).join("\n")}")
          { error: e.message }
        end
      end
    end
  end
end



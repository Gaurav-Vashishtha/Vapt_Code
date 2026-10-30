require 'securerandom'

module ShopifyServices
  class PartialOrderCreateService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id, partial_variant_ids)
      @client = client
      @shop = shop
      @order_id = order_id
      @partial_variant_ids = partial_variant_ids
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
      %w[countryCodeV2 formattedArea latitude longitude name formatted].each do |field|
        params[key].delete(field)
      end
      params[key]
    end

    def get_applied_discount(params, order_confirmation)
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

      upfront_received = get_discount_amount.to_f
      upfront_base = [upfront_received - total_tax, 0].max

      {
        amount: upfront_base.round(2).to_s,
        valueType: 'FIXED_AMOUNT',
        value: upfront_base.round(2),
        title: 'Payment Received Upfront (Online)'
      }
    end

    def shopify_variant_quantity_hash(params)
      variant_quantity = {}
      params['lineItems']['edges'].each do |line_item|
        node = line_item['node']
        full_variant_id = node.dig('variant', 'id')
        next if full_variant_id.blank?

        variant_id = full_variant_id.gsub('gid://shopify/ProductVariant/', '')
        quantity = node['quantity']
        variant_quantity[variant_id] = quantity
      end
      variant_quantity
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

        resolved_id = record.original_variant_ids.first.split(":").first
        last_resolved_id = resolved_id
        current_variant_id = resolved_id
      end

      last_resolved_id
    end

    def get_line_items(_params)
      line_items = []

      @partial_variant_ids.each do |partial_id|
        variant_numeric_id = partial_id.to_s

        mapping = PartialProductMapping.find_by(
          partial_variant_id: variant_numeric_id,
          shopify_domain: @shop.shopify_domain
        )

        puts "#{variant_numeric_id} - #{mapping.inspect}"

        li = nil

        if mapping&.original_variant_ids&.present?
          original_id_with_qty = mapping.original_variant_ids.first
          original_variant_id, quantity = original_id_with_qty.split(':')

          if original_variant_id.present? && quantity.present?
            original_variant_id = resolve_original_variant_id(@shop.shopify_domain, original_variant_id)
            li = {
              variantId: "gid://shopify/ProductVariant/#{original_variant_id}",
              quantity: quantity.to_i
            }
          else
            Rails.logger.warn("Mapping for partial_id #{variant_numeric_id} has blank original_variant_id or quantity")
          end
        else
          Rails.logger.warn("No mapping found or empty original_variant_ids for partial_id #{variant_numeric_id}")
        end

        if li.nil?
          Rails.logger.warn("Skipping unresolved partial variant #{variant_numeric_id} for shop #{@shop.shopify_domain}")
          next
        end

        line_items << li
      end

      line_items
    end

    def create_draft_order(order_confirmation)
      params = ShopifyServices::OrderFullGetService.call(@shop, order_confirmation.order_id)
      return unless params

      @shopify_variant_hash = shopify_variant_quantity_hash(params)

      # ❗ Filter only valid partial variants
      @partial_variant_ids = @partial_variant_ids.select do |vid|
        PartialProductMapping.exists?(partial_variant_id: vid.to_s, shopify_domain: @shop.shopify_domain)
      end

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
          appliedDiscount: get_applied_discount(params, order_confirmation),
          billingAddress: get_address(params, 'billingAddress'),
          customerId: order_confirmation.customer_id.present? ? "gid://shopify/Customer/#{order_confirmation.customer_id.gsub("gid://shopify/Customer/", "")}" : "",
          note: "Partial Order created from Original Order #{order_confirmation.order_id}.",
          email: order_confirmation.customer_email,
          lineItems: get_line_items(params),
          shippingAddress: get_address(params, 'shippingAddress'),
          tags: tags.join(","),
          taxExempt: false,
          shippingLine: shippingLine
        }
      }

      copied_attrs = PartialOrderAttributionCopy.draft_custom_attributes_from_original_order(@shop, order_confirmation.order_id)
      variables[:input][:customAttributes] = copied_attrs if copied_attrs.present?

      puts "variables to draft order #{variables.inspect}"
      resp = @client.query(query, variables: variables)
      puts "response from draft order #{resp.inspect}"
      resp
    end

    def create_order_from_draft_order(resp, order_confirmation)
      if resp&.data&.draft_order_create&.draft_order
        @shop.init_session
        draft_order = ShopifyAPI::DraftOrder.find(resp.data.draft_order_create.draft_order.id.gsub('gid://shopify/DraftOrder/', ''))

        if draft_order.complete(payment_pending: true)
          order_confirmation.update(draft_order_id: draft_order.order_id, status: 'COD-Partial-Payment-Received')
          order_confirmation.update(prepaid_status: "Order Created #{draft_order.order_id}")
        else
          raise "Unable to complete draft order for shop for order #{order_confirmation.id}"
        end
      end
      order_confirmation
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
        draft_order_resp = create_draft_order(order_confirmation)

        if draft_order_resp.to_h.dig('data', 'draftOrderCreate', 'draftOrder', 'id')
          order_confirmation.update(prepaid_status: "Draft Order Created #{draft_order_resp.to_h.dig('data', 'draftOrderCreate', 'draftOrder', 'id')}")
        end

        order_confirmation = create_order_from_draft_order(draft_order_resp, order_confirmation)

        if order_confirmation.draft_order_id
          # Get original order total before cancelling
          original_order_total = cancel_original_order(order_confirmation)
          
          # Get new order total
          @shop.init_session
          new_order = ShopifyAPI::Order.find(order_confirmation.draft_order_id)
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
          ShopifyJobs::OrderTagPostJob.perform_async(@shop.id, order_confirmation.order_id, 'Partial_Payment_Order')
          return new_order.order_status_url
        end
      rescue => e
        SlackNotifyJob.perform_async(":rage:  (#{Rails.env})\n *Error* in Partial order conversion for order #{@order_id} -> #{@shop.shopify_domain} error: #{e.message} #{e.backtrace}")
      end
    end
  end
end

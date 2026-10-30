require 'securerandom'
# ShopifyServices::PrepaidOrderService.call(Shop.last, OrderConfirmation.last.id)
# ShopifyServices::PrepaidOrderService.call(order_confirmation.shop,order_confirmation.id )
module ShopifyServices
  class PrepaidOrderService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    #ShopifyServices::PrepaidOrderService.new(nil,order_confirmation.shop, order_confirmation.id).get_discount_amount
    # Optional overrides let the caller (e.g. a per-reminder prepaid send) supply
    # a discount that differs from shop.setting.prepaid_discount. Pass nil to
    # use the shop default — preserves legacy behavior for all existing callers.
    def get_discount_amount(discount: nil, discount_type: nil, add_shipping: false)
      @order_confirmation = OrderConfirmation.find(@order_id)
      discount_value = discount.nil? ? @shop.setting.prepaid_discount : discount
      discount_kind  = discount_type.nil? ? @shop.setting.prepaid_discount_type : discount_type

      order_discount = discount_value
      if discount_kind == 'PERCENTAGE'
        if @shop.setting.cod_fee_enabled #old flow, then take from order value
          order_discount = (discount_value.to_f * 0.01 * @order_confirmation.order_amount.to_f) + @order_confirmation.cod_fee
        else #cod fees is not enabled
          order_discount = discount_value.to_f * 0.01 * @order_confirmation.order_amount.to_f
        end
      end

      # When the prepaid reminder rule opts in, also waive the order's shipping by
      # rolling it into the discount (e.g. ₹100 discount + ₹50 shipping → ₹150 off).
      order_discount = order_discount.to_f + order_shipping_amount if add_shipping

      return order_discount.to_f
    end

    #ShopifyServices::PrepaidOrderService.new(nil,order_confirmation.shop, order_confirmation.id).get_total_amount
    def get_total_amount(discount: nil, discount_type: nil, add_shipping: false)
      @order_confirmation = OrderConfirmation.find(@order_id)
      #Make a call to Shopify and always reduce COD fees.
      return @order_confirmation.order_amount.to_f + @order_confirmation.cod_fee - get_discount_amount(discount: discount, discount_type: discount_type, add_shipping: add_shipping)
    end

    # The order's Shopify shipping charge (totalShippingPriceSet.shopMoney.amount),
    # fetched once from the live order and memoized. Returns 0.0 when the order
    # has no shipping or the fetch fails (so it never breaks a send).
    def order_shipping_amount
      return @order_shipping_amount if defined?(@order_shipping_amount)

      @order_shipping_amount = begin
        oc = @order_confirmation || OrderConfirmation.find(@order_id)
        params = ShopifyServices::OrderFullGetService.call(@shop, oc.order_id) || {}
        params.dig('totalShippingPriceSet', 'shopMoney', 'amount').to_f
      rescue => e
        Rails.logger.warn("[PrepaidOrderService] shipping fetch failed order=#{@order_id}: #{e.class}: #{e.message}")
        0.0
      end
    end


    def get_address(params,key)
      if !params.blank? && !params[key].blank?
        params[key].delete('countryCodeV2')
        params[key].delete('formattedArea')
        params[key].delete('latitude')
        params[key].delete('longitude')
        params[key].delete('name')
        params[key].delete('formatted')
      end
      params[key]
    end

    # def get_shipping_lines(params)
    #   if !params['shippingLine'].blank?
    #     shippingLines = {
    #       price: params['shippingLine']['discountedPriceSet']['shopMoney']['amount'],
    #       shippingRateHandle: params['shippingLine']['shippingRateHandle'],
    #       title: params['shippingLine']['title']
    #     }
    #   end
    #   shippingLines
    # end

    def create_order_from_draft_order(resp,order_confirmation)
      if resp && resp.data &&
        resp.data.draft_order_create &&
        resp.data.draft_order_create.draft_order 
        @shop.init_session
        draft_order = ShopifyAPI::DraftOrder.find(resp.data.draft_order_create.draft_order.id.gsub('gid://shopify/DraftOrder/',''))
        puts "create_order_from_draft_order Get draft order response #{draft_order.to_json}"
          if draft_order.complete
            order_confirmation.update(draft_order_id: draft_order.order_id, status: 'COD-Prepaid')
            order_confirmation.update(prepaid_status: "Order Created #{draft_order.order_id}")
          else
            SlackNotifyJob.perform_async(
              ":rage:  (#{Rails.env})\n  *Unable to complete draft order for shop for order #{draft_oprder} #{order_confirmation.id}"
            )
            raise "(#{Rails.env})\n  *Unable to complete draft order for shop for order #{draft_oprder} #{order_confirmation.id}" 
          end
      end
      order_confirmation
    end

    def cancel_original_order(order_confirmation)
      @shop.init_session
      order = ShopifyAPI::Order.find(order_confirmation.order_id)
      cancel_resp = order.cancel(reason:'declined',restock:true)
      puts "cancel_original_order response #{cancel_resp.to_json}"
      return cancel_resp
    end

    def get_line_items(params)
      lineItems = []
      params['lineItems']['edges'].each do |line_item|        
        line_item = line_item['node']
        if !line_item.dig('variant','id').blank? 
          li = {
            quantity: line_item['quantity'],
            variantId: line_item.dig('variant','id'),
          }
          lineItems.push(li)
        else
          raise "(#{Rails.env})\n  *Unable to get variant ID from actual order  #{params}" 
        end
      end
      lineItems
    end

    def get_applied_discount(params, order_discount)
      appliedDiscount = {
        amount: (params.dig('currentTotalDiscountsSet','shopMoney','amount').to_f + order_discount).to_s,
        valueType: 'FIXED_AMOUNT',
        value: params.dig('currentTotalDiscountsSet','shopMoney','amount').to_f + order_discount,
        title: 'Prepaid Discount'
      }
      appliedDiscount
    end
  


    def create_draft_order(order_confirmation)
      
        params = ShopifyServices::OrderFullGetService.call(
          @shop,
          order_confirmation.order_id
        )
        puts "Get order response #{params}"
        if params
          
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
          tags = params['tags'].blank? ? [] : params['tags']
          tags.push('Prepaid-From-COD')
          prepaid_discount = get_discount_amount.to_f
          shippingLine = {}
          if !params.dig('totalShippingPriceSet','shopMoney','amount').blank?
            shippingLine = {
            priceWithCurrency: {
              amount: params.dig('totalShippingPriceSet','shopMoney','amount'),
              currencyCode: params.dig('totalShippingPriceSet','shopMoney','currencyCode')
            },
            title: 'COD-Prepaid-Shipping'
          }
          end
          
          variables = {
            input: {
              appliedDiscount: get_applied_discount(params, prepaid_discount),
              customAttributes: [{ key: '_codkPrepaidDiscount', value: format('%.2f', prepaid_discount) }],
              billingAddress: get_address(params,'billingAddress'),
              customerId: (order_confirmation.customer_id.blank? ? '' :  "gid://shopify/Customer/#{order_confirmation.customer_id.gsub("gid://shopify/Customer/","")}"),
              note: "Converted COD order #{order_confirmation.order_id.to_s} to prepaid.",
              email: order_confirmation.customer_email,
              lineItems: get_line_items(params),
              shippingAddress: get_address(params,'shippingAddress'),
              # shippingLine: get_shipping_lines(params),
              tags: tags.join(","),
              taxExempt: false,
              shippingLine: shippingLine
            }
          }
          puts "Draft order variables #{variables}"
          resp = @client.query(query, variables: variables)
          
          puts "Draft order response #{resp}"
          return resp
      end
    end

    def call
      begin
        # Create draft order and update the DB
        # Create order from draft order and update the DB
        # 
          order_confirmation = OrderConfirmation.find(@order_id)
          if order_confirmation.status=='COD-Prepaid' || (!order_confirmation.draft_order_id.blank?)
            # SlackNotifyJob.perform_async(
            # ":rage:  (#{Rails.env})\n *Error* in Prepaid order while converting the order #{@order_id} -> #{@shop.shopify_domain} - Duplicate - Already converted order"
            # )
            return     
          end

          draft_order_resp =  create_draft_order(order_confirmation)
          if !draft_order_resp.to_h.dig('data','draftOrderCreate','draftOrder','id').blank?
            order_confirmation.update(prepaid_status: "Draft Order Created #{draft_order_resp.to_h.dig('data','draftOrderCreate','draftOrder','id')}")
          end
          order_confirmation = create_order_from_draft_order(draft_order_resp, order_confirmation)
          
          
          if order_confirmation.draft_order_id
            cancel_original_order(order_confirmation)
            order_confirmation.update(prepaid_status: "Original Order Cancelled")
            ShopifyJobs::OrderTagPostJob.perform_async(@shop.id, order_confirmation.order_id,'Converted-To-Prepaid')
            return ShopifyAPI::Order.find(order_confirmation.draft_order_id).order_status_url
          end
        end
      rescue Exception => e 
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* in Prepaid order while converting the order #{@order_id} -> #{@shop.shopify_domain} error: #{e.message}"
        )
      end
    end
  end

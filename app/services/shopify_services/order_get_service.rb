module ShopifyServices
  class OrderGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id,order_url)
      @client = client
      @shop = shop
      @order_id = order_id
      @order_url = order_url
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
        query ($id:ID!){
          order(id:$id){
            id,email,phone,tags,
            paymentGatewayNames,
            customerLocale,
            currencyCode,
            name,
            createdAt,
            lineItems (first: 20) {
              edges {
                node {
                  product{
                    id
                  }
                }
              }
            }
            customer{
              firstName,
              lastName,
              id,
              email
            }
            currentTotalPriceSet{
              shopMoney{
                amount,
                currencyCode
              }
            }
            currentSubtotalPriceSet{
              shopMoney{
                amount,
                currencyCode
              }
            }
            billingAddress{
              phone
              countryCodeV2
            }
            shippingAddress{
              phone
              countryCodeV2
            }
          }
        }
      GRAPHQL
      variables = {
        'id': "gid://shopify/Order/#{@order_id}"
      }
      resp = @client.query(query, variables: variables)
      puts resp.inspect
      return resp
    end

    def get_line_items(params)
      lineItems = []
      if !params.dig('lineItems','edges').blank?
        params['lineItems']['edges'].each do |node|
          if !node.dig('node','product','id').blank?
            lineItems.push({product_id: node['node']['product']['id'].gsub("gid://shopify/Product/","")})
          end
        end 
      else
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* lineItems for this #{params}"
        )
      end
      return JSON.parse(lineItems.to_json)
    end


    def call
      if !@order_id.blank?
        shopify_order = get_order
        has_graphql_errors = false
        begin
          # Check for GraphQL errors first
          if shopify_order&.respond_to?(:errors) && shopify_order.errors&.any?
            has_graphql_errors = true
            Rails.logger.error "GraphQL errors for order #{@order_id}: #{shopify_order.errors.inspect}"
          end
          
          if shopify_order && shopify_order.data && shopify_order.data.order
            shopify_order = shopify_order.data.order
          else
            shopify_order = nil
          end
        rescue StandardError => e
          puts "An error occurred: #{e.message}"
          shopify_order = nil
        end
        if !shopify_order.blank?
          params = shopify_order.to_h.deep_dup
          params['line_items'] = get_line_items(params)
          params['id']=params['id'].gsub('gid://shopify/Order/','')
          params['total_price'] = params.dig('currentTotalPriceSet','shopMoney','amount')
          if !params['customer'].blank?
            customer_hash={}
            customer_hash['first_name'] = params.dig('customer','firstName')
            customer_hash['last_name'] = params.dig('customer','lastName')
            customer_hash['id'] = params.dig('customer','id')
            customer_hash['email'] = params.dig('customer','email')
            params['customer'] = customer_hash
          end
          if !params['shippingAddress'].blank?
            shipping_hash = {}
            shipping_hash['country_code'] = params.dig('shippingAddress','countryCodeV2')
            shipping_hash['phone'] = params.dig('shippingAddress','phone')
            params['shipping_address'] = shipping_hash
          end

          if !params['billingAddress'].blank?
            billing_hash = {}
            billing_hash['country_code'] = params.dig('billingAddress','countryCodeV2')
            billing_hash['phone'] = params.dig('billingAddress','phone')
            params['billing_address'] = billing_hash
          end

          params['customer_locale'] = params['customerLocale']
          params['order_number'] = params['name']
          params['currency'] = params['currencyCode']
          params['payment_gateway_names'] = params['paymentGatewayNames']
          params['order_status_url'] = @order_url
          params['subtotal_price'] = params.dig('currentSubtotalPriceSet','shopMoney','amount')
          params['createdAt'] = params['createdAt']
          params
        else
          # Only alert if there are actual GraphQL errors, or if order_id is suspiciously small (< 3)
          # This prevents false positives for legitimate small order IDs
          should_alert = has_graphql_errors || 
                        (!@order_id.blank? && @order_id != "0" && @order_id != "1" && @order_id.to_i > 0 && @order_id.to_i > 10) ||
                        (!@order_url.blank? && @order_id.blank?)
          
          # if should_alert
          #   SlackNotifyJob.perform_async(
          #     ":rage:  (#{Rails.env})\n *Error* Unable to get order for this #{@order_url} - #{@order_id} - #{@shop.shopify_domain}"
          #   )
          # end
        end
      end
    end
  end
end

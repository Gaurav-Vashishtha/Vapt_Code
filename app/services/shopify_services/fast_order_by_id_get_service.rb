module ShopifyServices
  # params = ShopifyServices::FastOrderByIdGetService.call(
  #   Shop.last,
  #   '6122921328924' 
  # )
  class FastOrderByIdGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
         query ($id:ID!){
          order(id:$id){
          paymentGatewayNames
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

    def is_cod(shop,payment_gateway_names)
      # treat COD if payment gateways not found
      if shop.cod_include_tags=='*'
        return true
      end
      return true if payment_gateway_names.blank?
      return true if payment_gateway_names.include? 'bogus' 
      
      # Build list of gateways by combining 2 params
      payment_gateways = (payment_gateway_names).uniq.select(&:present?).map(&:downcase)
  
      # Non COD (return false) if any gateway in exclusion list
      exclude_tags = shop.cod_exclude_tags&.split(',')
      # exact tag match
      return false if exclude_tags.any? { |tag| payment_gateways.include? tag }
  
      include_tags = shop.cod_include_tags&.split(',')
      # fuzzy tag match
      return true if include_tags.any? { |tag| payment_gateways.any? { |gateway| gateway.include? tag } }
  
      false
    end

    def call
        if !@order_id.blank?
          shopify_order = get_order
          begin
            shopify_order=shopify_order && shopify_order.data && shopify_order.data.order
            if shopify_order
              return {render_otp_box: is_cod(@shop, shopify_order.payment_gateway_names),phone: (shopify_order.shipping_address&.phone || shopify_order.billing_address&.phone || '')}
            else
              SlackNotifyJob.perform_async(
                ":rage:  (#{Rails.env})\n *Error* Unable to get order for FastOrderByIdGetService #{@order_id} #{@shop.shopify_domain}"
              )
            end
          rescue Exception => e
            SlackNotifyJob.perform_async(
              ":rage:  (#{Rails.env})\n *Exception* Unable to get order for FastOrderByIdGetService #{@order_id} #{@shop.shopify_domain} #{e.backtrace}"
            )
          end
        end
        return nil
      end
  end
end

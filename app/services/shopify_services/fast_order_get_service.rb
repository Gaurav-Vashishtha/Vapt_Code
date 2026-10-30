module ShopifyServices
  class FastOrderGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, checkout_token)
      @client = client
      @shop = shop
      @checkout_token = checkout_token
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
      query($first:Int!,$query:String!) {
        orders(first: $first,query: $query) {
          edges {
            node {
              id,
              paymentGatewayNames
            }
          }
        }
      }
    GRAPHQL
      
      variables = {
        'first':1,
        'query': "checkout_token:#{@checkout_token}"
      }
    resp = @client.query(query, variables: variables)
    return resp.to_h.dig('data','orders','edges')
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
      if !@checkout_token.blank?
        shopify_order = get_order
        begin
          if shopify_order && shopify_order.first && shopify_order.first['node']
            shopify_order = shopify_order.first['node']
          else
            shopify_order = nil
          end
        rescue StandardError => e
          puts "An error occurred: #{e.message}"
          shopify_order = nil
        end
        if !shopify_order.blank?
          params = shopify_order.to_h.deep_dup
          return is_cod(@shop,params['paymentGatewayNames'])
        else
          if !@order_id.blank?
            puts "Unable to get order for this1 #{@order_id} #{@shop.shopify_domain}"
            # SlackNotifyJob.perform_async(
            #   ":rage:  (#{Rails.env})\n *Error* Unable to get order for this1 #{@order_id} #{@shop.shopify_domain}"
            # )
          end
          return nil
        end
      end
    end
  end
end

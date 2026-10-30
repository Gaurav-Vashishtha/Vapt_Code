module ShopifyServices
  class OrderPostService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id, tag, phone_number)
      @client = client
      @shop = shop
      @order_id = order_id
      @tag = tag
      @phone_number = phone_number
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
        query ($id:ID!){
          order(id:$id){
            id,email,phone,tags,
            shippingAddress{
              phone,
              address1,
              address2,
              city,
              company,
              country,
              firstName,
              lastName,
              province,
              provinceCode,
              zip
            },
            billingAddress{
              phone,
              address1,
              address2,
              city,
              company,
              country,
              firstName,
              lastName,
              province,
              provinceCode,
              zip
            }
          }
        }
      GRAPHQL
      variables = {
        'id': "gid://shopify/Order/#{@order_id}"
      }
      resp = @client.query(query, variables: variables)
    end

    def get_tags(existing_order)
      new_tags = []

      unless (existing_order.data && existing_order.data.order && existing_order.data.order.tags).blank?
        existing_order.data.order.tags.each  do |tag|
          new_tags.push(tag) unless tag.include? 'COD'
        end
      end

      new_tags.push(@tag)
    end

    def update_tags_if_shipping_phone_updated(existing_order,tags,shipping_address)
      shipping_phone = shipping_address['phone']
      e164_phone = to_e164(@phone_number)
      if shipping_phone.blank? || (to_e164(shipping_phone) != e164_phone && @tag == '✅ COD-Verified')
        shipping_address['phone'] = e164_phone
        if !@shop.shopify_domain == 'beromtindia.myshopify.com'
          tags.push('Ph:' + e164_phone) if e164_phone.present?
        end
      end
      tags
    end

    def to_e164(phone)
      return phone if phone.blank?
      phone.to_s.start_with?('+') ? phone.to_s : "+#{phone}"
    end

    def call
      begin
      existing_order = get_order
      @tags = get_tags(existing_order)

      query = @client.parse <<-'GRAPHQL'
        mutation ($input: OrderInput!) {
          orderUpdate(input: $input) {
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
      shipping_address = existing_order.data&.order&.shipping_address.to_h.deep_dup
      if shipping_address.blank?
        shipping_address = existing_order.data&.order&.billing_address.to_h.deep_dup
      end
      @tags = update_tags_if_shipping_phone_updated(existing_order, @tags,shipping_address)
      variables = {}
      if !shipping_address.blank?
        variables = {
        input: {
          id: "gid://shopify/Order/#{@order_id}",
          tags: @tags,
          shippingAddress: shipping_address
          }
        }
      else
        variables = {
        input: {
          id: "gid://shopify/Order/#{@order_id}",
          tags: @tags
          }
        }
      end
      resp = @client.query(query, variables: variables)

      rescue Exception => e
        order_confirmation = OrderConfirmation.find_by(order_id:@order_id)
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* in publishing tags for orderconfirmation #{order_confirmation.id} #{e.backtrace}"
        )
        raise
      end
    end
  end
end

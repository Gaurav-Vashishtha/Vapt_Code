require 'securerandom'

module ShopifyServices
  class DraftOrderCreateService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def call
      order_confirmation = OrderConfirmation.find(@order_id)
      if order_confirmation
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
        shipping_address = {}
        if order_confirmation.shipping_address
          ship_hash = eval(order_confirmation.shipping_address)
          shipping_address = {
            firstName: ship_hash['first_name'],
            address1: ship_hash['address1'],
            phone: ship_hash['phone'],
            city: ship_hash['city'],
            zip: ship_hash['zip'],
            province: ship_hash['province'],
            country: ship_hash['country'],
            lastName: ship_hash['last_name'],
            address2: ship_hash['address2'],
            company: ship_hash['company'],
            countryCode: ship_hash['country_code'],
            provinceCode: ship_hash['province_code']
          }
        end
     
        variables = {
          input: {
            lineItems: [
              {
                title: "Payment for #{order_confirmation.order_id} ",
                originalUnitPrice: order_confirmation.order_amount,
                quantity: 1,
                taxable: false
              }
            ],
            customerId: "gid://shopify/Customer/#{order_confirmation.customer_id}",
            note: order_confirmation.id.to_s,
            email: order_confirmation.customer_email,
            shippingAddress: shipping_address
          }
        }
        resp = @client.query(query, variables: variables)
        puts resp
        if resp && resp.data &&
           resp.data.draft_order_create &&
           resp.data.draft_order_create.draft_order &&
           order_confirmation.update(
             draft_order_uuid: resp.data.draft_order_create.draft_order.note2,
             prepaid_link: resp.data.draft_order_create.draft_order.invoice_url,
             draft_order_id: resp.data.draft_order_create.draft_order.id
           )
          order_confirmation
        else
          SlackNotifyJob.perform_async(
            ":rage:  (#{Rails.env})\n  *Unable to create draft order for shop for order #{resp}"
          )
          order_confirmation
        end
      end
    end
  end
end

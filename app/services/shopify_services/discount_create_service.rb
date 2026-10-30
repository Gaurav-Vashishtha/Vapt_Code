module ShopifyServices
    class DiscountCreateService < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :title, :discount_value, :value_type
  
      # Prefer service-specific class method to avoid relying on base kwargs
      def self.call(shop, title:, discount_value:, value_type: 'percentage')
        shop.init_session()
        client = ShopifyAPI::GraphQL.client
        new(client, shop, title: title, discount_value: discount_value, value_type: value_type).call
      end

      #ShopifyServices::DiscountCreateService.call(@shop)
      def initialize(client, shop, title:, discount_value:, value_type: 'percentage')
        @client = client
        @shop = shop
        @title = title
        @value_type = (value_type || 'percentage').to_s
        @discount_value = coerce_value(discount_value)
      end
  
      def create_discount
        query = @client.parse <<-'GRAPHQL'
        mutation ($basicCodeDiscount: DiscountCodeBasicInput!) {
          discountCodeBasicCreate(basicCodeDiscount: $basicCodeDiscount) {
            codeDiscountNode {
              codeDiscount {
                ... on DiscountCodeBasic {
                  title
                  codes(first: 10) {
                    nodes {
                      code
                    }
                  }
                  startsAt
                  endsAt
                  customerSelection {
                    ... on DiscountCustomerAll {
                      allCustomers
                    }
                  }
                  customerGets {
                    value {
                      ... on DiscountPercentage {
                        percentage
                      }
                    }
                    items {
                      ... on AllDiscountItems {
                        allItems
                      }
                    }
                  }
                  appliesOncePerCustomer
                }
              }
            }
            userErrors {
              field
              code
              message
            }
          }
        }
        GRAPHQL
  
        random_code = generate_random_code
        starts_at = Time.current.utc
        ends_at = (starts_at + 2.hours)

        value_payload = if @value_type == 'amount'
          { "discountAmount": { "amount": @discount_value, "appliesOnEachItem": false } }
        else
          { "percentage": @discount_value }
        end

        variables = {
          "basicCodeDiscount": {
            "title": @title,
            "code": random_code,
            "startsAt": starts_at.iso8601,
            "endsAt": ends_at.iso8601,
            "customerSelection": {
              "all": true
            },
            "customerGets": {
              "value": value_payload,
              "items": {
                "all": true
              }
            },
            "appliesOncePerCustomer": true
          }
        }
        
        resp = @client.query(query, variables: variables)
        resp
      end
  
     
  
      def call
        create_discount
      end

      private

      def generate_random_code
        prefix = 'CODK'
        random = SecureRandom.alphanumeric(8).upcase
        "#{prefix}-#{random}"
      end

      def normalize_percentage(value)
        return 0.0 if value.negative?
        # If user passes 10 for 10%, convert to 0.10; if already 0-1, keep as-is
        value > 1.0 ? (value / 100.0) : value
      end

      def coerce_value(value)
        v = value.to_f
        return 0.0 if v.negative?
        return v if @value_type == 'amount'
        normalize_percentage(v)
      end
    end
  end
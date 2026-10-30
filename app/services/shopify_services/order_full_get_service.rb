module ShopifyServices
  class OrderFullGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::OrderFullGetService.call(
    #   Shop.last,
    #   OrderConfirmation.last
    # )

    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
        query ($id:ID!){
          order(id:$id){
            id,
            email,
            phone,
            tags,
            paymentGatewayNames,
            customerLocale,
            currencyCode,
            createdAt,
            taxesIncluded,
            customer{
              firstName,
              lastName,
              id,
              email,
              numberOfOrders
            }
            shippingLine{
              discountedPriceSet{
                presentmentMoney{
                  amount
                  currencyCode
                }
                shopMoney{
                  amount
                  currencyCode
                }
              }
              shippingRateHandle
              title
            }
            lineItems (first: 20) {
              edges {
                node {
                  discountedTotalSet{
                    presentmentMoney{
                      amount
                      currencyCode
                    }
                    shopMoney{
                      amount
                      currencyCode
                    }
                  }
                  name
                  requiresShipping
                  originalTotalSet{
                    presentmentMoney{
                      amount
                      currencyCode
                    }
                    shopMoney{
                      amount
                      currencyCode
                    }
                  }
                  variant{
                    id
                  }
                  sku
                  title
                  quantity
                  sku
                  vendor
                  taxLines {
                    rate
                    ratePercentage
                  }
                }
              }
            }
          
            currentTotalPriceSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            billingAddress{
              address1,
              address2,
              city,
              company,
              country,
              countryCodeV2,
              firstName,
              formatted,
              formattedArea,
              lastName,
              latitude,
              longitude,
              name,
              phone,
              province,
              provinceCode,
              zip
            }
            canNotifyCustomer
            cartDiscountAmountSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            
            totalShippingPriceSet{
              shopMoney{
                amount
                currencyCode
              }
            }

            currentSubtotalLineItemsQuantity
            currentSubtotalPriceSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            currentTotalDiscountsSet{
              presentmentMoney{
                amount
                currencyCode
              }
              shopMoney{
                amount
                currencyCode
              }
            }
            currentTaxLines{
              priceSet{
                presentmentMoney{
                  amount
                  currencyCode
                }
                shopMoney{
                  amount
                  currencyCode
                }
              }
              rate
              ratePercentage
              title
            }
            shippingAddress{
              address1,
              address2,
              city,
              company,
              country,
              countryCodeV2,
              firstName,
              formatted,
              formattedArea,
              lastName,
              latitude,
              longitude,
              name,
              phone,
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
      return resp
    end

    def call
      if !@order_id.blank?
        resp = get_order
        shopify_order = resp.data.order
        if !shopify_order.blank?
          params = shopify_order.to_h.deep_dup
          params
        else
          SlackNotifyJob.perform_async(
            ":rage:  (#{Rails.env})\n *Error* Unable to get order for #{@order_url}"
          )
        end
      end
    end
  end
end

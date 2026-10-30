module OrderQueries
  SingleOrderDetails = ShopifyAPI::GraphQL.client.parse <<-'GRAPHQL'
      query ($id: ID!) {
        order(id: $id) {
          id
          name
          subtotalPriceSet { shopMoney { amount currencyCode } }
          totalShippingPriceSet { shopMoney { amount } }
          totalDiscountsSet { shopMoney { amount } }
          totalTaxSet { shopMoney { amount } }
          totalPriceSet { shopMoney { amount } }
          shippingAddress {
            name
            address1
            address2
            city
            province
            zip
            country
          }
          lineItems(first: 50) {
            edges {
              node {
                title
                variantTitle
                quantity
                originalUnitPriceSet { shopMoney { amount } }
                discountedUnitPriceSet { shopMoney { amount } }
                image {
                  url(transform: { maxWidth: 160, maxHeight: 160 })
                }
              }
            }
          }
        }
      }
    GRAPHQL
end

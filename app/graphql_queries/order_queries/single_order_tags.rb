module OrderQueries
  SingleOrderTags = ShopifyAPI::GraphQL.client.parse <<-'GRAPHQL'
      query ($id: ID!) {
        order(id: $id) {
          id
          tags
        }
      }
    GRAPHQL
end

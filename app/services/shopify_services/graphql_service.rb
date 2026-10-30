module ShopifyServices
  class GraphqlService < ApplicationService
    def self.call(*args, &block)
      shop = args[0]
      shop.init_session()
      args.unshift(ShopifyAPI::GraphQL.client)
      new(*args, &block).call
    end
  end
end
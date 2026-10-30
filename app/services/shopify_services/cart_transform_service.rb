module ShopifyServices
  class CartTransformService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # ShopifyServices::CartTransformService.call(shop)
    #ShopifyServices::CartTransformDeleteService.call(shop)
    def initialize(client, shop)
      @client = client
      @shop = shop
    end
  
    def call
      if @shop.setting.cart_transform_id.blank?
        cart_transform_id = ShopifyServices::CartTransformCreateService.call(@shop)
        if cart_transform_id.present?
          @shop.setting.update(cart_transform_id: cart_transform_id)
        end
      end
      return @shop.setting.cart_transform_id
    end
  end
end


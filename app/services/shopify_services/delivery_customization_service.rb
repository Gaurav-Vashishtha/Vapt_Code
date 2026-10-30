module ShopifyServices
    class DeliveryCustomizationService < ShopifyServices::GraphqlService
      attr_reader :shop, :client

      # ShopifyServices::DeliveryCustomizationService.call(
      #   @shop 
      # )
  
      def initialize(client, shop)
        @client = client
        @shop = shop
      end
  
      def call
        # if Rails.env.development?
        #   return nil
        # end
        if @shop.setting.delivery_customization_id.blank?
          delivery_customization_id = ShopifyServices::DeliveryFunctionCreateService.call(@shop)
          @shop.setting.update(delivery_customization_id: delivery_customization_id)
        end
        if !@shop.setting.delivery_customization_id.blank?
            params = ShopifyServices::DeliveryFunctionMetafieldService.call(@shop,@shop.setting.delivery_customization_id)
            if params.blank?
              delivery_customization_id = ShopifyServices::DeliveryFunctionCreateService.call(@shop)
              @shop.setting.update(delivery_customization_id: delivery_customization_id)
              params = ShopifyServices::DeliveryFunctionMetafieldService.call(@shop,@shop.setting.delivery_customization_id)
              SlackNotifyJob.perform_async(
                ":rage:  (#{Rails.env})\n  *ShopifyServices::DeliveryFunctionMetafieldService attempt 2#{params}"
              )
              return params
            else
              return params
            end
        end
      end
    end
  end
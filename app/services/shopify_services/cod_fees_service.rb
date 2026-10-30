module ShopifyServices
    class CodFeesService < ShopifyServices::GraphqlService
      attr_reader :shop, :client
  
      def initialize(client, shop, order_confirmation)
        @client = client
        @shop = shop
        @order_confirmation = order_confirmation
      end
  
      def call
        variant_id = ''
        if @shop.setting.is_percentage
          resp = ShopifyServices::CodfeeProductCreateService.call(@shop, 'COD-Fees', @order_confirmation.cod_fee)
          resp_hash = JSON.parse(resp.to_json).to_h
          variant_id = resp_hash['variant_id']
          # product = ShopifyServices::CodProductCreateService.call(
          #   @shop,
          #   @order_confirmation.cod_fee,
          #   false
          # )
          if !variant_id.blank?
            ShopifyServices::OrderEditService.call(
              @shop, @order_confirmation.order_id, variant_id
            )

            ShopifyJobs::ProductDestroyJob.set(wait:3.minutes).perform_later(shop.id,resp_hash['product_id'])
          end
        else
          if @shop.setting.cod_variant_id.blank?
            resp = ShopifyServices::CodfeeProductCreateService.call(@shop, 'COD-Fees', @order_confirmation.cod_fee)
            resp_hash = JSON.parse(resp.to_json).to_h
            variant_id = resp_hash['variant_id']

            @shop.setting.cod_variant_id = variant_id
            @shop.setting.save
          end
          ShopifyServices::OrderEditService.call(
            @shop, @order_confirmation.order_id, @shop.setting.cod_variant_id
          )
        end
      end
    end
  end
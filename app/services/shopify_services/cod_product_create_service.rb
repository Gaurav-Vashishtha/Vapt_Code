module ShopifyServices
    class CodProductCreateService < ShopifyServices::GraphqlService
      attr_reader :shop, :client
  
      def initialize(client, shop, price=5, is_test_order=false )
        @client = client
        @shop = shop
        @price = price
        @is_test_order = is_test_order
      end
  
      def call
        cod_fees = @price
        variants = []
        variant = ShopifyAPI::Variant.new(
          price: cod_fees,
          inventory_management: 'shopify',
          taxable: false,
          sku: 'COD'
        )
        variants.push(variant)
        product = ShopifyAPI::Product.new(
          title: @is_test_order? 'COD-King-Test-Product' : 'COD-Fees',
          variants: variants,
          status:'draft'
        )
        if product.save
          if @is_test_order
            @shop.setting.test_variant_id = product.variants.first.id  
            @shop.setting.save
          end
          return product
        else
          throw "CodProductCreateService - Error creating product #{shop.id}"
        end
      end
    end
  end
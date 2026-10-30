module ShopifyServices
    class ProductImageService < ShopifyServices::GraphqlService
  
      # Example: ShopifyServices::ProductImageService.call(@shop, product_id)
  
      attr_reader :shop, :client, :product_id
  
      def initialize(client, shop, product_id)
        @client = client
        @shop = shop
        @product_id = product_id
      end
  
      def get_product_image
        return nil if @product_id.blank?
  
        puts "🔍 Fetching image for product ID: #{@product_id}"
  
        query = @client.parse <<-'GRAPHQL'
          query($id: ID!) {
            product(id: $id) {
              featuredImage {
                url
              }
            }
          }
        GRAPHQL
  
        variables = { id: "gid://shopify/Product/#{@product_id}" }
        
        resp = @client.query(query, variables: variables)
        
        if resp&.data&.product && resp.data.product.featured_image
          image_url = resp.data.product.featured_image.url
          puts "✅ Found image: #{image_url}"
          return image_url
        else
          puts "❌ No featured image found for product: #{@product_id}"
          return nil
        end
      rescue Exception => e
        puts "💥 Error in get_product_image: #{e.message}"
        return nil
      end
  
      def call
        image_url = get_product_image
        return image_url
      end
  
      class << self
        def call(shop, product_id)
          client = shop.with_shopify_session { ShopifyAPI::GraphQL.client }
          new(client, shop, product_id).call
        rescue Exception => e
          puts "💥 Error in ProductImageService: #{e.message}"
          return nil
        end
      end
    end
  end
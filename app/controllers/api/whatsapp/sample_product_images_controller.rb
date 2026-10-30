module Api
  module Whatsapp
    # When a merchant picks the "Use the order's product image" header source,
    # Meta still requires an example image at template-review time. We auto-fill
    # the example using one of the merchant's actual product images (most
    # recent first). The merchant can override with a custom URL if they don't
    # like the auto-pick.
    class SampleProductImagesController < AuthenticatedController
      def index
        @shop.init_session

        # Pull a small page of products — we only need image URLs, so keep the
        # field list trimmed. limit:5 to keep the Shopify call fast.
        products = ::ShopifyAPI::Product.find(:all, params: { limit: 5, fields: 'id,title,images' })

        images = Array(products).flat_map do |p|
          Array(p.images).map do |img|
            src = img.respond_to?(:src) ? img.src : img['src']
            next nil if src.blank?
            {
              product_id: p.id,
              product_title: p.respond_to?(:title) ? p.title : p['title'],
              url: src
            }
          end
        end.compact.first(5)

        render json: { images: images }
      rescue => e
        Rails.logger.warn("[sample_product_images] shop=#{@shop.id} failed: #{e.class}: #{e.message}")
        render json: { images: [], error: 'Could not fetch a sample image from Shopify.' }, status: :ok
      end
    end
  end
end

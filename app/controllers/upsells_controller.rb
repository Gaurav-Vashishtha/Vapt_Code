# frozen_string_literal: true

class UpsellsController < ApiController
  # GET /upsells/products?shop=x.myshopify.com&product_ids=1,2
  def products
    shop = Shop.find_by(shopify_domain: params[:shop].to_s)
    return render(json: { products: [] }) if shop.blank?

    product_ids = params[:product_ids].to_s.split(",")
    result = Upsells::ProductsService.call(shop, product_ids)
    render json: result.merge(currency: shop.currency)
  rescue StandardError => e
    Rails.logger.warn("[Upsells#products] #{e.class}: #{e.message.to_s[0, 200]}")
    render json: { products: [] }
  end
end

require 'test_helper'

class WishProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @wish_product = wish_products(:one)
  end

  test "should get index" do
    get wish_products_url
    assert_response :success
  end

  test "should get new" do
    get new_wish_product_url
    assert_response :success
  end

  test "should create wish_product" do
    assert_difference('WishProduct.count') do
      post wish_products_url, params: { wish_product: { clean_image: @wish_product.clean_image, country_shippings: @wish_product.country_shippings, date_uploaded: @wish_product.date_uploaded, default_shipping_price: @wish_product.default_shipping_price, description: @wish_product.description, extra_images: @wish_product.extra_images, fbw_inbound_approval_status: @wish_product.fbw_inbound_approval_status, is_promoted: @wish_product.is_promoted, last_updated: @wish_product.last_updated, localized_default_shipping_price: @wish_product.localized_default_shipping_price, main_image: @wish_product.main_image, name: @wish_product.name, number_saves: @wish_product.number_saves, number_sold: @wish_product.number_sold, original_image_url: @wish_product.original_image_url, parent_sku: @wish_product.parent_sku, product_brand_name: @wish_product.product_brand_name, product_brand_status: @wish_product.product_brand_status, requested_product_brand_id: @wish_product.requested_product_brand_id, review_status: @wish_product.review_status, tags: @wish_product.tags, variants: @wish_product.variants, wish_product_id: @wish_product.wish_product_id } }
    end

    assert_redirected_to wish_product_url(WishProduct.last)
  end

  test "should show wish_product" do
    get wish_product_url(@wish_product)
    assert_response :success
  end

  test "should get edit" do
    get edit_wish_product_url(@wish_product)
    assert_response :success
  end

  test "should update wish_product" do
    patch wish_product_url(@wish_product), params: { wish_product: { clean_image: @wish_product.clean_image, country_shippings: @wish_product.country_shippings, date_uploaded: @wish_product.date_uploaded, default_shipping_price: @wish_product.default_shipping_price, description: @wish_product.description, extra_images: @wish_product.extra_images, fbw_inbound_approval_status: @wish_product.fbw_inbound_approval_status, is_promoted: @wish_product.is_promoted, last_updated: @wish_product.last_updated, localized_default_shipping_price: @wish_product.localized_default_shipping_price, main_image: @wish_product.main_image, name: @wish_product.name, number_saves: @wish_product.number_saves, number_sold: @wish_product.number_sold, original_image_url: @wish_product.original_image_url, parent_sku: @wish_product.parent_sku, product_brand_name: @wish_product.product_brand_name, product_brand_status: @wish_product.product_brand_status, requested_product_brand_id: @wish_product.requested_product_brand_id, review_status: @wish_product.review_status, tags: @wish_product.tags, variants: @wish_product.variants, wish_product_id: @wish_product.wish_product_id } }
    assert_redirected_to wish_product_url(@wish_product)
  end

  test "should destroy wish_product" do
    assert_difference('WishProduct.count', -1) do
      delete wish_product_url(@wish_product)
    end

    assert_redirected_to wish_products_url
  end
end

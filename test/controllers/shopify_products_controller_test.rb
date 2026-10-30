require 'test_helper'

class ShopifyProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @shopify_product = shopify_products(:one)
  end

  test "should get index" do
    get shopify_products_url
    assert_response :success
  end

  test "should get new" do
    get new_shopify_product_url
    assert_response :success
  end

  test "should create shopify_product" do
    assert_difference('ShopifyProduct.count') do
      post shopify_products_url, params: { shopify_product: { createdAt: @shopify_product.createdAt, defaultCursor: @shopify_product.defaultCursor, description: @shopify_product.description, descriptionHtml: @shopify_product.descriptionHtml, featuredImage: @shopify_product.featuredImage, feedback: @shopify_product.feedback, giftCardTemplateSuffix: @shopify_product.giftCardTemplateSuffix, handle: @shopify_product.handle, hasOnlyDefaultVariant: @shopify_product.hasOnlyDefaultVariant, hasOutOfStockVariants: @shopify_product.hasOutOfStockVariants, isGiftCard: @shopify_product.isGiftCard, legacyResourceId: @shopify_product.legacyResourceId, mediaCount: @shopify_product.mediaCount, onlineStorePreviewUrl: @shopify_product.onlineStorePreviewUrl, onlineStoreUrl: @shopify_product.onlineStoreUrl, options: @shopify_product.options, priceRangeV2: @shopify_product.priceRangeV2, productType: @shopify_product.productType, publishedAt: @shopify_product.publishedAt, requiresSellingPlan: @shopify_product.requiresSellingPlan, sellingPlanGroupCount: @shopify_product.sellingPlanGroupCount, seo: @shopify_product.seo, shopifyId: @shopify_product.shopifyId, status: @shopify_product.status, storefrontId: @shopify_product.storefrontId, tags: @shopify_product.tags, templateSuffix: @shopify_product.templateSuffix, title: @shopify_product.title, totalInventory: @shopify_product.totalInventory, totalVariants: @shopify_product.totalVariants, tracksInventory: @shopify_product.tracksInventory, updatedAt: @shopify_product.updatedAt, vendor: @shopify_product.vendor } }
    end

    assert_redirected_to shopify_product_url(ShopifyProduct.last)
  end

  test "should show shopify_product" do
    get shopify_product_url(@shopify_product)
    assert_response :success
  end

  test "should get edit" do
    get edit_shopify_product_url(@shopify_product)
    assert_response :success
  end

  test "should update shopify_product" do
    patch shopify_product_url(@shopify_product), params: { shopify_product: { createdAt: @shopify_product.createdAt, defaultCursor: @shopify_product.defaultCursor, description: @shopify_product.description, descriptionHtml: @shopify_product.descriptionHtml, featuredImage: @shopify_product.featuredImage, feedback: @shopify_product.feedback, giftCardTemplateSuffix: @shopify_product.giftCardTemplateSuffix, handle: @shopify_product.handle, hasOnlyDefaultVariant: @shopify_product.hasOnlyDefaultVariant, hasOutOfStockVariants: @shopify_product.hasOutOfStockVariants, isGiftCard: @shopify_product.isGiftCard, legacyResourceId: @shopify_product.legacyResourceId, mediaCount: @shopify_product.mediaCount, onlineStorePreviewUrl: @shopify_product.onlineStorePreviewUrl, onlineStoreUrl: @shopify_product.onlineStoreUrl, options: @shopify_product.options, priceRangeV2: @shopify_product.priceRangeV2, productType: @shopify_product.productType, publishedAt: @shopify_product.publishedAt, requiresSellingPlan: @shopify_product.requiresSellingPlan, sellingPlanGroupCount: @shopify_product.sellingPlanGroupCount, seo: @shopify_product.seo, shopifyId: @shopify_product.shopifyId, status: @shopify_product.status, storefrontId: @shopify_product.storefrontId, tags: @shopify_product.tags, templateSuffix: @shopify_product.templateSuffix, title: @shopify_product.title, totalInventory: @shopify_product.totalInventory, totalVariants: @shopify_product.totalVariants, tracksInventory: @shopify_product.tracksInventory, updatedAt: @shopify_product.updatedAt, vendor: @shopify_product.vendor } }
    assert_redirected_to shopify_product_url(@shopify_product)
  end

  test "should destroy shopify_product" do
    assert_difference('ShopifyProduct.count', -1) do
      delete shopify_product_url(@shopify_product)
    end

    assert_redirected_to shopify_products_url
  end
end

require "application_system_test_case"

class ShopifyProductsTest < ApplicationSystemTestCase
  setup do
    @shopify_product = shopify_products(:one)
  end

  test "visiting the index" do
    visit shopify_products_url
    assert_selector "h1", text: "Shopify Products"
  end

  test "creating a Shopify product" do
    visit shopify_products_url
    click_on "New Shopify Product"

    fill_in "Createdat", with: @shopify_product.createdAt
    fill_in "Defaultcursor", with: @shopify_product.defaultCursor
    fill_in "Description", with: @shopify_product.description
    fill_in "Descriptionhtml", with: @shopify_product.descriptionHtml
    fill_in "Featuredimage", with: @shopify_product.featuredImage
    fill_in "Feedback", with: @shopify_product.feedback
    fill_in "Giftcardtemplatesuffix", with: @shopify_product.giftCardTemplateSuffix
    fill_in "Handle", with: @shopify_product.handle
    fill_in "Hasonlydefaultvariant", with: @shopify_product.hasOnlyDefaultVariant
    fill_in "Hasoutofstockvariants", with: @shopify_product.hasOutOfStockVariants
    fill_in "Isgiftcard", with: @shopify_product.isGiftCard
    fill_in "Legacyresourceid", with: @shopify_product.legacyResourceId
    fill_in "Mediacount", with: @shopify_product.mediaCount
    fill_in "Onlinestorepreviewurl", with: @shopify_product.onlineStorePreviewUrl
    fill_in "Onlinestoreurl", with: @shopify_product.onlineStoreUrl
    fill_in "Options", with: @shopify_product.options
    fill_in "Pricerangev2", with: @shopify_product.priceRangeV2
    fill_in "Producttype", with: @shopify_product.productType
    fill_in "Publishedat", with: @shopify_product.publishedAt
    fill_in "Requiressellingplan", with: @shopify_product.requiresSellingPlan
    fill_in "Sellingplangroupcount", with: @shopify_product.sellingPlanGroupCount
    fill_in "Seo", with: @shopify_product.seo
    fill_in "Shopifyid", with: @shopify_product.shopifyId
    fill_in "Status", with: @shopify_product.status
    fill_in "Storefrontid", with: @shopify_product.storefrontId
    fill_in "Tags", with: @shopify_product.tags
    fill_in "Templatesuffix", with: @shopify_product.templateSuffix
    fill_in "Title", with: @shopify_product.title
    fill_in "Totalinventory", with: @shopify_product.totalInventory
    fill_in "Totalvariants", with: @shopify_product.totalVariants
    fill_in "Tracksinventory", with: @shopify_product.tracksInventory
    fill_in "Updatedat", with: @shopify_product.updatedAt
    fill_in "Vendor", with: @shopify_product.vendor
    click_on "Create Shopify product"

    assert_text "Shopify product was successfully created"
    click_on "Back"
  end

  test "updating a Shopify product" do
    visit shopify_products_url
    click_on "Edit", match: :first

    fill_in "Createdat", with: @shopify_product.createdAt
    fill_in "Defaultcursor", with: @shopify_product.defaultCursor
    fill_in "Description", with: @shopify_product.description
    fill_in "Descriptionhtml", with: @shopify_product.descriptionHtml
    fill_in "Featuredimage", with: @shopify_product.featuredImage
    fill_in "Feedback", with: @shopify_product.feedback
    fill_in "Giftcardtemplatesuffix", with: @shopify_product.giftCardTemplateSuffix
    fill_in "Handle", with: @shopify_product.handle
    fill_in "Hasonlydefaultvariant", with: @shopify_product.hasOnlyDefaultVariant
    fill_in "Hasoutofstockvariants", with: @shopify_product.hasOutOfStockVariants
    fill_in "Isgiftcard", with: @shopify_product.isGiftCard
    fill_in "Legacyresourceid", with: @shopify_product.legacyResourceId
    fill_in "Mediacount", with: @shopify_product.mediaCount
    fill_in "Onlinestorepreviewurl", with: @shopify_product.onlineStorePreviewUrl
    fill_in "Onlinestoreurl", with: @shopify_product.onlineStoreUrl
    fill_in "Options", with: @shopify_product.options
    fill_in "Pricerangev2", with: @shopify_product.priceRangeV2
    fill_in "Producttype", with: @shopify_product.productType
    fill_in "Publishedat", with: @shopify_product.publishedAt
    fill_in "Requiressellingplan", with: @shopify_product.requiresSellingPlan
    fill_in "Sellingplangroupcount", with: @shopify_product.sellingPlanGroupCount
    fill_in "Seo", with: @shopify_product.seo
    fill_in "Shopifyid", with: @shopify_product.shopifyId
    fill_in "Status", with: @shopify_product.status
    fill_in "Storefrontid", with: @shopify_product.storefrontId
    fill_in "Tags", with: @shopify_product.tags
    fill_in "Templatesuffix", with: @shopify_product.templateSuffix
    fill_in "Title", with: @shopify_product.title
    fill_in "Totalinventory", with: @shopify_product.totalInventory
    fill_in "Totalvariants", with: @shopify_product.totalVariants
    fill_in "Tracksinventory", with: @shopify_product.tracksInventory
    fill_in "Updatedat", with: @shopify_product.updatedAt
    fill_in "Vendor", with: @shopify_product.vendor
    click_on "Update Shopify product"

    assert_text "Shopify product was successfully updated"
    click_on "Back"
  end

  test "destroying a Shopify product" do
    visit shopify_products_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Shopify product was successfully destroyed"
  end
end

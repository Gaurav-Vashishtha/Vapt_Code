require "application_system_test_case"

class WishProductsTest < ApplicationSystemTestCase
  setup do
    @wish_product = wish_products(:one)
  end

  test "visiting the index" do
    visit wish_products_url
    assert_selector "h1", text: "Wish Products"
  end

  test "creating a Wish product" do
    visit wish_products_url
    click_on "New Wish Product"

    fill_in "Clean image", with: @wish_product.clean_image
    fill_in "Country shippings", with: @wish_product.country_shippings
    fill_in "Date uploaded", with: @wish_product.date_uploaded
    fill_in "Default shipping price", with: @wish_product.default_shipping_price
    fill_in "Description", with: @wish_product.description
    fill_in "Extra images", with: @wish_product.extra_images
    fill_in "Fbw inbound approval status", with: @wish_product.fbw_inbound_approval_status
    fill_in "Is promoted", with: @wish_product.is_promoted
    fill_in "Last updated", with: @wish_product.last_updated
    fill_in "Localized default shipping price", with: @wish_product.localized_default_shipping_price
    fill_in "Main image", with: @wish_product.main_image
    fill_in "Name", with: @wish_product.name
    fill_in "Number saves", with: @wish_product.number_saves
    fill_in "Number sold", with: @wish_product.number_sold
    fill_in "Original image url", with: @wish_product.original_image_url
    fill_in "Parent sku", with: @wish_product.parent_sku
    fill_in "Product brand name", with: @wish_product.product_brand_name
    fill_in "Product brand status", with: @wish_product.product_brand_status
    fill_in "Requested product brand", with: @wish_product.requested_product_brand_id
    fill_in "Review status", with: @wish_product.review_status
    fill_in "Tags", with: @wish_product.tags
    fill_in "Variants", with: @wish_product.variants
    fill_in "Wish product", with: @wish_product.wish_product_id
    click_on "Create Wish product"

    assert_text "Wish product was successfully created"
    click_on "Back"
  end

  test "updating a Wish product" do
    visit wish_products_url
    click_on "Edit", match: :first

    fill_in "Clean image", with: @wish_product.clean_image
    fill_in "Country shippings", with: @wish_product.country_shippings
    fill_in "Date uploaded", with: @wish_product.date_uploaded
    fill_in "Default shipping price", with: @wish_product.default_shipping_price
    fill_in "Description", with: @wish_product.description
    fill_in "Extra images", with: @wish_product.extra_images
    fill_in "Fbw inbound approval status", with: @wish_product.fbw_inbound_approval_status
    fill_in "Is promoted", with: @wish_product.is_promoted
    fill_in "Last updated", with: @wish_product.last_updated
    fill_in "Localized default shipping price", with: @wish_product.localized_default_shipping_price
    fill_in "Main image", with: @wish_product.main_image
    fill_in "Name", with: @wish_product.name
    fill_in "Number saves", with: @wish_product.number_saves
    fill_in "Number sold", with: @wish_product.number_sold
    fill_in "Original image url", with: @wish_product.original_image_url
    fill_in "Parent sku", with: @wish_product.parent_sku
    fill_in "Product brand name", with: @wish_product.product_brand_name
    fill_in "Product brand status", with: @wish_product.product_brand_status
    fill_in "Requested product brand", with: @wish_product.requested_product_brand_id
    fill_in "Review status", with: @wish_product.review_status
    fill_in "Tags", with: @wish_product.tags
    fill_in "Variants", with: @wish_product.variants
    fill_in "Wish product", with: @wish_product.wish_product_id
    click_on "Update Wish product"

    assert_text "Wish product was successfully updated"
    click_on "Back"
  end

  test "destroying a Wish product" do
    visit wish_products_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Wish product was successfully destroyed"
  end
end

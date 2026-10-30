require "application_system_test_case"

class OrderConfirmationsTest < ApplicationSystemTestCase
  setup do
    @order_confirmation = order_confirmations(:one)
  end

  test "visiting the index" do
    visit order_confirmations_url
    assert_selector "h1", text: "Order Confirmations"
  end

  test "creating a Order confirmation" do
    visit order_confirmations_url
    click_on "New Order Confirmation"

    fill_in "Confirmed at", with: @order_confirmation.confirmed_at
    fill_in "Customer name", with: @order_confirmation.customer_name
    fill_in "Order amount", with: @order_confirmation.order_amount
    fill_in "Order", with: @order_confirmation.order_id
    fill_in "Otp", with: @order_confirmation.otp
    fill_in "Shop", with: @order_confirmation.shop_id
    fill_in "Status", with: @order_confirmation.status
    click_on "Create Order confirmation"

    assert_text "Order confirmation was successfully created"
    click_on "Back"
  end

  test "updating a Order confirmation" do
    visit order_confirmations_url
    click_on "Edit", match: :first

    fill_in "Confirmed at", with: @order_confirmation.confirmed_at
    fill_in "Customer name", with: @order_confirmation.customer_name
    fill_in "Order amount", with: @order_confirmation.order_amount
    fill_in "Order", with: @order_confirmation.order_id
    fill_in "Otp", with: @order_confirmation.otp
    fill_in "Shop", with: @order_confirmation.shop_id
    fill_in "Status", with: @order_confirmation.status
    click_on "Update Order confirmation"

    assert_text "Order confirmation was successfully updated"
    click_on "Back"
  end

  test "destroying a Order confirmation" do
    visit order_confirmations_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Order confirmation was successfully destroyed"
  end
end

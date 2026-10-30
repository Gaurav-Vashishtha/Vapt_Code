require 'test_helper'

class OrderConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @order_confirmation = order_confirmations(:one)
  end

  test "should get index" do
    get order_confirmations_url
    assert_response :success
  end

  test "should get new" do
    get new_order_confirmation_url
    assert_response :success
  end

  test "should create order_confirmation" do
    assert_difference('OrderConfirmation.count') do
      post order_confirmations_url, params: { order_confirmation: { confirmed_at: @order_confirmation.confirmed_at, customer_name: @order_confirmation.customer_name, order_amount: @order_confirmation.order_amount, order_id: @order_confirmation.order_id, otp: @order_confirmation.otp, shop_id: @order_confirmation.shop_id, status: @order_confirmation.status } }
    end

    assert_redirected_to order_confirmation_url(OrderConfirmation.last)
  end

  test "should show order_confirmation" do
    get order_confirmation_url(@order_confirmation)
    assert_response :success
  end

  test "should get edit" do
    get edit_order_confirmation_url(@order_confirmation)
    assert_response :success
  end

  test "should update order_confirmation" do
    patch order_confirmation_url(@order_confirmation), params: { order_confirmation: { confirmed_at: @order_confirmation.confirmed_at, customer_name: @order_confirmation.customer_name, order_amount: @order_confirmation.order_amount, order_id: @order_confirmation.order_id, otp: @order_confirmation.otp, shop_id: @order_confirmation.shop_id, status: @order_confirmation.status } }
    assert_redirected_to order_confirmation_url(@order_confirmation)
  end

  test "should destroy order_confirmation" do
    assert_difference('OrderConfirmation.count', -1) do
      delete order_confirmation_url(@order_confirmation)
    end

    assert_redirected_to order_confirmations_url
  end
end

class OrderVerifyController < ApplicationController
  protect_from_forgery except: [:access_token]
  def index
    @order = OrderConfirmation.select(
      :order_number, :customer_email, :customer_name, :order_amount, :customer_number, :shop_id
    ).find_by(order_id: params[:order_id])

    if @order.nil?
      @order_not_found = true
      return
    end

    @shop = Shop.select(:id, :owner_name, :currency, :shopify_domain).find(@order.shop_id)
    @setting = Setting.find_by(shop_id: @shop.id)
    @auto_verify = @setting.auto_verify
    @show_cancel_button = @setting.show_cancel_button
    @order_summary = fetch_order_summary unless @auto_verify
  end

  private

  def fetch_order_summary
    ShopifyServices::OrderDetailsGetService.call(Shop.find(@shop.id), params[:order_id])
  rescue => e
    Rails.logger.error("order_verify summary fetch failed for order #{params[:order_id]}: #{e.class} #{e.message}")
    nil
  end
end
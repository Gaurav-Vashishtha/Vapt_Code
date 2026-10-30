class OrderPrepaidController < ApplicationController
  protect_from_forgery except: [:access_token]
  def index
    @order = OrderConfirmation.find_by(digest: params[:digest])
    if !@order.blank?
      @order.update(prepaid_status:'CALLBACK-RECEIVED')
    end
    @shop = Shop.select(:id, :owner_name, :currency, :shopify_domain).find(@order.shop_id)
    # @setting = Setting.find_by(shop_id: @shop.id)
    # @auto_verify = @setting.auto_verify
    # @show_cancel_button = @setting.show_cancel_button
  end

end
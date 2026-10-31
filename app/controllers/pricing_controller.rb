# frozen_string_literal: true

class PricingController < ApplicationController
  layout "pricing", :only => [ :index ] 
  http_basic_authenticate_with name: ENV.fetch("ADMIN_USER", nil), password: ENV.fetch("ADMIN_PASS", nil), only: :shopify_order_data

  # Public pricing page. All rates are computed server-side with billing's own
  # rules (PublicPricingCatalog) and handed to the page as JSON.
  # ?country=XX preselects a country; ?multiplier= scales every rate (quotes).
  def index
    catalog = PublicPricingCatalog.new(multiplier: params[:multiplier])
    @countries = catalog.countries
    @updated_on = catalog.updated_on
    codes = @countries.map { |c| c[:code] }
    @default_country = [params[:country], request.headers['CF-IPCountry'], 'IN']
                       .map { |c| c.to_s.upcase }.find { |c| codes.include?(c) } || codes.first
  end

  def shopify_order_data
    begin
      if params[:email]
        shop = Shop.find_by(owner_email: params[:email])
      elsif params[:domain]
        shop = Shop.find_by(shopify_domain: params[:domain])
      end
      shop.init_session
      if params[:order_id]
        order_id = params[:order_id]
      elsif params[:order_number]
        order_id = OrderConfirmation.find_by(
          order_number: params[:order_number],
          shop_id: shop.id
        ).order_id
      end
      if order_id
        order = ShopifyAPI::Order.find(order_id)
      else
        throw 'error occured'
      end
      render json: order
    rescue StandardError => e
      return render json: {
        option_1: '?order_id=3947340529817&email=abc@gmail.com',
        option_2: '?order_id=3947340529817&domain=atindev.myshopify.com',
        option_3: '?order_number=1234&email=abc@gmail.com',
        option_4: '?order_number=1234&domain=atindev.myshopify.com'
      }
    end
  end
end

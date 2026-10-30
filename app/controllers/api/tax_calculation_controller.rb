# frozen_string_literal: true

class Api::TaxCalculationController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:calculate]

  def calculate
    cart_data = params[:cart_data] || params[:cart]
    shipping_address = params[:shipping_address] || params[:shippingAddress]
    shop_domain = params[:shop_domain] || params[:shop] || extract_shop_from_origin

    # Validate required parameters
    unless cart_data && shipping_address
      return render json: {
        error: 'Missing required parameters',
        message: 'cart_data and shipping_address are required'
      }, status: :bad_request
    end

    unless cart_data[:items] || cart_data['items']
      return render json: {
        error: 'Invalid cart data',
        message: 'cart must contain items'
      }, status: :bad_request
    end

    # Find shop by domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      return render json: {
        error: 'Shop not found',
        message: "Shop with domain '#{shop_domain}' not found"
      }, status: :not_found
    end

    # Call service to calculate taxes
    result = ShopifyServices::DraftOrderCalculateService.call(
      shop,
      cart_data,
      shipping_address
    )

    if result[:error]
      render json: {
        error: result[:error],
        errors: result[:errors]
      }, status: :unprocessable_entity
    else
      render json: {
        success: true,
        tax_calculation: {
          total_tax: result[:total_tax],
          subtotal_price: result[:subtotal_price],
          total_price: result[:total_price],
          tax_lines: result[:tax_lines] || [],
          available_shipping_rates: result[:available_shipping_rates] || []
        }
      }, status: :ok
    end
  rescue StandardError => e
    Rails.logger.error "Error in TaxCalculationController#calculate: #{e.message} #{e.backtrace.first(5).join("\n")}"
    render json: {
      error: 'Internal server error',
      message: e.message
    }, status: :internal_server_error
  end

  private

  def extract_shop_from_origin
    # Try to extract shop domain from Origin header or Referer
    origin = request.headers['Origin'] || request.headers['Referer']
    return nil unless origin

    # Extract myshopify.com domain from origin URL
    match = origin.match(/https?:\/\/([a-zA-Z0-9-]+\.myshopify\.com)/)
    match ? match[1] : nil
  end
end

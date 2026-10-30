# frozen_string_literal: true

class Api::CodOrdersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  def create
    cart_data = params[:cart_data] || params[:cart]
    shipping_address = params[:shipping_address] || params[:shippingAddress]
    buyer_identity = params[:buyer_identity] || params[:buyerIdentity] || {}
    cod_fee = params[:cod_fee] || params[:codFee]
    shipping_rate_details = params[:shipping_rate_details] || params[:shippingRateDetails]
    verification_status = ActiveModel::Type::Boolean.new.cast(
      params[:verification_status].presence || params[:otp_verified].presence
    )
    shop_domain = params[:shop_domain] || params[:shop] || extract_shop_from_origin
    meta_click_data = params[:meta_click_data] || params[:metaClickData] || {}

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

    # COD Form D.12: origin check, log-only unless COD_ORDERS_ORIGIN_ENFORCE == "true".
    unless CodForm::OriginGuard.legacy_allowed?(shop, request)
      return render json: {
        error: 'Origin not allowed',
        message: 'This request is not allowed from this origin'
      }, status: :forbidden
    end

    campaign_raw = params[:campaign_attribution].presence || params[:campaignAttribution]
    campaign_attribution = if campaign_raw.is_a?(ActionController::Parameters)
                             CampaignAttributionHelper.normalize(
                               campaign_raw.permit(*CampaignAttributionHelper::ALLOWED_KEYS)
                             )
                           else
                             CampaignAttributionHelper.normalize(campaign_raw)
                           end

    # Call service to create COD order
    result = ShopifyServices::CodOrderCreateService.call(
      shop,
      cart_data,
      shipping_address,
      buyer_identity,
      cod_fee,
      shipping_rate_details,
      verification_status,
      meta_click_data: meta_click_data,
      client_context: {
        event_source_url: meta_click_data["event_source_url"] || meta_click_data[:event_source_url],
        client_user_agent: meta_click_data["client_user_agent"] || meta_click_data[:client_user_agent] || request.user_agent,
        client_ip_address: request.remote_ip,
      },
      campaign_attribution: campaign_attribution
    )

    if result[:error]
      render json: { 
        error: result[:error],
        errors: result[:errors] 
      }, status: :unprocessable_entity
    else
      render json: {
        success: true,
        order: {
          id: result[:order_id],
          number: result[:order_number],
          name: result[:order_name],
          total_price: result[:total_price],
          currency_code: result[:currency_code],
          order_status_url: result[:order_status_url]
        }
      }, status: :created
    end
  rescue StandardError => e
    Rails.logger.error "Error in CodOrdersController#create: #{e.message} #{e.backtrace.first(5).join("\n")}"
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
    match = origin.match(%r{https?://([a-zA-Z0-9-]+\.myshopify\.com)})
    match ? match[1] : nil
  end
end

# frozen_string_literal: true

# GET|POST /api/active_subscription
#
# Same shared secret as Api::UsageChargesController (ENV['EASY_SELL_AUTH_TOKEN']),
# accepted as `clientToken` in the body/query or as an `X-Client-Token` header.
#
# Params: { "shopify_domain": "store.myshopify.com" }  (also shop_domain / shop)
#
# 200 → { success: true, active: true,  subscription: { plan_name, price, currency, ... } }
# 200 → { success: true, active: false, reason: "no_active_subscription", subscription: null }
# 4xx → { success: false, reason: "missing_params" | "shop_not_found" | "shop_unauthorized" }
class Api::ActiveSubscriptionsController < ActionController::API
  before_action :authenticate_client_token!

  STATUS_BY_REASON = {
    'shop_not_found' => :not_found,
    'shop_unauthorized' => :conflict
  }.freeze

  def show
    domain = params[:shopify_domain].presence || params[:shop_domain].presence || params[:shop].presence

    if domain.blank?
      return render json: { success: false, reason: 'missing_params', detail: 'shopify_domain is required' },
                    status: :bad_request
    end

    result = ShopifyServices::ActiveSubscriptionService.call(domain)

    if result[:success]
      render json: result, status: :ok
    else
      render json: result, status: STATUS_BY_REASON.fetch(result[:reason], :unprocessable_entity)
    end
  rescue StandardError => e
    Rails.logger.error("[api/active_subscription] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { success: false, reason: 'internal_error', detail: e.message }, status: :internal_server_error
  end

  private

  def authenticate_client_token!
    supplied = params[:clientToken].presence || request.headers['X-Client-Token'].presence
    expected = ENV.fetch("EASY_SELL_AUTH_TOKEN", nil).presence
    return if supplied && expected && ActiveSupport::SecurityUtils.secure_compare(supplied.to_s, expected)

    render json: { status: 'Error', message: 'Unauthorized access' }, status: :unauthorized
  end
end

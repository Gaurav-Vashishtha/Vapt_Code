# frozen_string_literal: true

# POST /api/usage_charges
#
# Same shared secret as OrderConfirmationsController#refresh_payment_customization
# (ENV['EASY_SELL_AUTH_TOKEN']), accepted as `clientToken` in the body/query or
# as an `X-Client-Token` header.
#
# Body: { "shopify_domain": "store.myshopify.com", "charge": 12.5, "description": "optional" }
#
# 200 → { success: true,  subscription: {...capped_amount, balance_remaining...}, usage_charge: {...} }
# 4xx → { success: false, reason: "shop_not_found" | "no_active_subscription" |
#                                 "capped_amount_exhausted" | "invalid_charge" |
#                                 "shop_unauthorized" | "charge_failed", subscription: {...}|null }
class Api::UsageChargesController < ActionController::API
  before_action :authenticate_client_token!

  STATUS_BY_REASON = {
    'shop_not_found' => :not_found,
    'no_active_subscription' => :payment_required,
    'capped_amount_exhausted' => :payment_required,
    'invalid_charge' => :unprocessable_entity,
    'shop_unauthorized' => :conflict,
    'charge_failed' => :unprocessable_entity
  }.freeze

  def create
    domain = params[:shopify_domain].presence || params[:shop_domain].presence || params[:shop].presence
    charge = params[:charge].presence || params[:amount].presence

    if domain.blank? || charge.blank?
      return render json: { success: false, reason: 'missing_params', detail: 'shopify_domain and charge are required' },
                    status: :bad_request
    end

    result = ShopifyServices::UsageChargeApplyService.call(domain, charge, description: params[:description])

    if result[:success]
      render json: result, status: :ok
    else
      render json: result, status: STATUS_BY_REASON.fetch(result[:reason], :unprocessable_entity)
    end
  rescue StandardError => e
    Rails.logger.error("[api/usage_charges] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { success: false, reason: 'internal_error', detail: e.message }, status: :internal_server_error
  end

  private

  def authenticate_client_token!
    supplied = params[:clientToken].presence || request.headers['X-Client-Token'].presence
    expected = ENV['EASY_SELL_AUTH_TOKEN'].presence
    return if supplied && expected && ActiveSupport::SecurityUtils.secure_compare(supplied.to_s, expected)

    render json: { status: 'Error', message: 'Unauthorized access' }, status: :unauthorized
  end
end

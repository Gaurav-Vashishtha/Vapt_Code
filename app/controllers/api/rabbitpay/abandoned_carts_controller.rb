# frozen_string_literal: true

# Receives pre-order OTP rows pushed from RabbitPay (when a store has
# codking_abandoned_cart enabled) and stores them here as PreOrderOtp entries
# so they surface in CodKing's abandoned-cart flow for that shop.
#
# Auth: reuses the shared shipping secret (SHIPPING_API_SERVER_SECRET) —
# RabbitPay sends it as `X-Shipping-Api-Secret` (or Authorization: Bearer).
class Api::Rabbitpay::AbandonedCartsController < ApplicationController
  include ShippingPublicApiOrigin

  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :verify_shipping_public_api_origin!, only: [:create]

  # Only the columns that exist on CodKing's pre_order_otps. RabbitPay-only
  # fields (address, sku, current_step, last_step_at, payment_method, id,
  # shop_id, updated_at) are intentionally dropped.
  ALLOWED_OTP_KEYS = %w[
    ip_address phone status notes sid country_code device_id is_charged otp
    actual_charge_applied shopify_order_ids cart_details order_status
    verification_status ver_type internal_comment created_at
  ].freeze

  def create
    shop_domain = (params[:shopifyDomain] || params[:shop_domain]).to_s
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      return render json: { ok: false, error: "shop_not_found", shopifyDomain: shop_domain },
                    status: :not_found
    end

    raw = params[:preOrderOtp] || params[:pre_order_otp] || {}
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h

    # Keep only columns that actually exist on THIS CodKing DB — guards against
    # schema drift between RabbitPay and CodKing (e.g. a missing internal_comment
    # column) so we never blow up on "unknown attribute".
    allowed = ALLOWED_OTP_KEYS & PreOrderOtp.column_names
    attrs = raw.stringify_keys.slice(*allowed)
    attrs["shop_id"] = shop.id
    attrs["cart_details"] = normalize_cart_details(attrs["cart_details"]) if attrs.key?("cart_details")

    otp = PreOrderOtp.new(attrs)

    if otp.save
      Rails.logger.info(
        "[RabbitpayAbandonedCart] created pre_order_otp id=#{otp.id} shop=#{shop.shopify_domain} " \
        "device=#{otp.device_id} phone=#{otp.phone} is_charged=#{otp.is_charged}"
      )
      render json: { ok: true, id: otp.id }, status: :created
    else
      Rails.logger.warn(
        "[RabbitpayAbandonedCart] save failed shop=#{shop.shopify_domain} " \
        "errors=#{otp.errors.full_messages.join(', ')}"
      )
      render json: { ok: false, errors: otp.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "[RabbitpayAbandonedCart] #{e.class}: #{e.message}"
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  # cart_details is a json[] column — coerce the incoming rows to plain hashes.
  def normalize_cart_details(value)
    return [] if value.blank?
    rows = value.is_a?(Array) ? value : [value]
    rows.map do |row|
      row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row
    end
  end
end

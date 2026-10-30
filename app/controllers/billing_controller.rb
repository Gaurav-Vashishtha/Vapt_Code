# frozen_string_literal: true

class BillingController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::RequireKnownShop
  include ShopContextInitializer

  before_action :set_shop
  skip_before_action :verify_authenticity_token, only: %i[usage_summary referral_link_status apply_referral_code unlink_referral_code]
  skip_before_action :check_shop_domain, only: %i[usage_summary referral_link_status apply_referral_code unlink_referral_code], raise: false
  skip_before_action :login_again_if_different_shop, only: %i[usage_summary referral_link_status apply_referral_code unlink_referral_code], raise: false
  skip_before_action :shopify_session, only: %i[usage_summary referral_link_status apply_referral_code unlink_referral_code], raise: false

  def index
    prepare_billing_context
    render "billing/index"
  end

  def usage_summary
    shop_domain = params[:shop].presence || current_shopify_domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      render json: { error: "Unknown shop" }, status: :not_found and return
    end

    billing_data = BillingUsageSummary.new(
      shop: shop,
      days: params[:days],
      start_date: params[:start_date],
      end_date: params[:end_date]
    ).as_json

    render json: billing_data
  end

  def referral_link_status
    shop_domain = params[:shop].presence || current_shopify_domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      render json: { error: "Unknown shop" }, status: :not_found and return
    end

    render json: BillingReferralLinkService.status_for_shop(shop)
  end

  def apply_referral_code
    shop_domain = params[:shop].presence || current_shopify_domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      render json: { error: "Unknown shop" }, status: :not_found and return
    end

    result = BillingReferralLinkService.new(
      shop: shop,
      referral_code: params[:referral_code]
    ).apply

    if result[:ok]
      render json: { linked: true, partner_name: result[:partner_name] }
    else
      status = case result[:error_key]
               when :invalid_code, :blank_code then :unprocessable_entity
               when :other_partner then :conflict
               else :unprocessable_entity
               end
      render json: { error: result[:message], error_key: result[:error_key] }, status: status
    end
  end

  def unlink_referral_code
    shop_domain = params[:shop].presence || current_shopify_domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      render json: { error: "Unknown shop" }, status: :not_found and return
    end

    result = BillingReferralLinkService.new(
      shop: shop,
      referral_code: nil
    ).unlink

    if result[:ok]
      render json: { linked: false }
    else
      status = result[:error_key] == :not_linked ? :not_found : :unprocessable_entity
      render json: { error: result[:message], error_key: result[:error_key] }, status: status
    end
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
  end

  def prepare_billing_context
    result = prepare_shop_context(
      shop: @shop,
      session: session,
      request: request,
      response: response
    )

    @shop_origin = result[:shop_origin]
    @setting = result[:setting]
    @plan = result[:plan]
    @crisp_url = result[:crisp_url]
    @twilio_pricing = result[:twilio_pricing]
    @visible_plans = result[:visible_plans]

    @billing_snapshot = BillingSnapshotBuilder.new(
      shop: @shop,
      plan: @plan,
      setting: @setting,
      twilio_pricing: @twilio_pricing
    ).as_json
  end
end


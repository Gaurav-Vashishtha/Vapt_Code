# frozen_string_literal: true

class WhatsappController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::RequireKnownShop
  include ShopContextInitializer
  before_action :set_shop
  before_action :prepare_context

  def index
    render :index
  end

  def account
    render :index
  end

  def templates
    render :index
  end

  def logs
    render :index
  end

  def campaigns
    render :index
  end

  def audience
    render :index
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
  end

  def prepare_context
    result = prepare_shop_context(shop: @shop, session: session, request: request, response: response)
    @shop_origin = result[:shop_origin]
    @setting = result[:setting]
    @plan = result[:plan]
    @crisp_url = result[:crisp_url]
    @twilio_pricing = result[:twilio_pricing]
    @visible_plans = result[:visible_plans]
  end
end

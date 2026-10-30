# frozen_string_literal: true

class HelpAndSupportController < ApplicationController
    include ShopifyApp::EmbeddedApp
    include ShopifyApp::RequireKnownShop
    include ShopContextInitializer
    before_action :set_shop
  
    def index
        result = prepare_shop_context(shop: @shop, session: session, request: request, response: response)

        @shop_origin = result[:shop_origin]
        @setting = result[:setting]
        @plan = result[:plan]
        @crisp_url = result[:crisp_url]
        @twilio_pricing = result[:twilio_pricing]
        @visible_plans = result[:visible_plans]

        render "help_and_support/index"
    end
  
    private
  
    def set_shop
      @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    end
  end
  
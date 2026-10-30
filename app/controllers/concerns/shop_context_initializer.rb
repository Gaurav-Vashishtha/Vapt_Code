# frozen_string_literal: true

module ShopContextInitializer
    extend ActiveSupport::Concern
  
    def prepare_shop_context(shop:, session:, request:, response:)
      shop_origin = request.params['host'] || session[:shopify_host]
      if shop_origin.blank?
        shop_origin = Base64.encode64("#{shop.shopify_domain}/admin")
      end
      session[:shopify_host] = shop_origin
  
      response.set_header(
        'content-security-policy',
        "frame-ancestors https://#{shop.shopify_domain} https://admin.shopify.com;"
      )
  
      # Upgrade a legacy/expired offline token to an expiring one using this
      # embedded request's session token, before any Admin API call below
      # (check_scope_and_reauth hits ShopifyAPI::AccessScope.find(:all)).
      begin
        ShopifyServices::OfflineTokenService.ensure_fresh!(shop, session_token: request.params[:id_token])
      rescue ShopifyServices::OfflineTokenService::Error => e
        Rails.logger.warn("[OfflineToken] migrate-on-load failed shop=#{shop.shopify_domain}: #{e.message}")
      end
      shop.init_session
      check_scope_and_reauth
  
      setting = Setting.find_or_initialize_by(shop_id: shop.id)
      plan = shop.plan || Plan.find_by(name: 'Free')
      crisp_url = shop.crisp_url
      twilio_pricing = TwilioPricing.payload_for_shop(shop)
  
      visible_plans = []
      if shop.visible_plans.present?
        visible_plans = Plan.find(shop.visible_plans.split(','))
      end
  
      {
        shop_origin: shop_origin,
        setting: setting,
        plan: plan,
        crisp_url: crisp_url,
        twilio_pricing: twilio_pricing,
        visible_plans: visible_plans
      }
    end
  end
  
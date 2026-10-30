# frozen_string_literal: true
Rails.application.config.middleware.use(OmniAuth::Builder) do
# frozen_string_literal: true

provider :shopify,
  ShopifyApp.configuration.api_key,
  ShopifyApp.configuration.secret,
  scope: ShopifyApp.configuration.scope,
  setup: lambda { |env|
    strategy = env['omniauth.strategy']
    shopify_auth_params = strategy.session['shopify.omniauth_params']&.with_indifferent_access
    # Prefer shop captured during initial initiate step; fall back to current request params on callback/reauth
    shop_domain = if shopify_auth_params.present?
      shopify_auth_params[:shop]
    else
      strategy.request.params['shop']
    end

    # Ensure we only accept myshopify domains to satisfy omniauth-shopify validation
    if shop_domain.to_s.match?(/\.myshopify\.com\z/)
      strategy.options[:client_options][:site] = "https://#{shop_domain}"
    end

    strategy.options[:old_client_secret] = ShopifyApp.configuration.old_secret
    strategy.options[:per_user_permissions] = strategy.session[:user_tokens]
  }
end

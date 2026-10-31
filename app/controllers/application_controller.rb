class ApplicationController < ActionController::Base
  protect_from_forgery with: :null_session
  protect_from_forgery with: :exception

  include Pagy::Backend
  # before_action :set_sentry_context
  before_action :set_locale

  def check_scope_and_reauth
    shop_remote_scope = ShopifyAPI::AccessScope.find(:all).map(&:handle).sort
    # Positive proof the offline token works — the only thing entitled to clear
    # the re-mint loop guard. Swallowed downstream failures must not count.
    @admin_api_verified = true
    app_scope = ShopifyApp.configuration.scope.split(', ').sort
    if shop_remote_scope != app_scope
      set_esdk_headers
      session['omniauth.state'] = "12345"
      url = "https://#{@shop.shopify_domain}/admin/oauth/authorize"
      request_params = []
      request_params << "client_id=#{ENV.fetch("SHOPIFY_API_KEY", nil)}"
      request_params << "scope=#{app_scope.join(', ')}"
      request_params << "redirect_uri=https://#{ENV.fetch("APP_HOST", nil)}/auth/shopify/callback"
      request_params << "state=12345"
      @scope_refresh_url = "#{url}?#{request_params.join('&')}"
    end
  rescue ActiveResource::UnauthorizedAccess
    raise
  rescue StandardError => e
    Rails.logger.warn("[ScopeCheck] skipped shop=#{@shop&.shopify_domain} #{e.class}: #{e.message}")
    nil
  end

  private

  # An Admin API 401 means Shopify revoked the token we hold, whatever its
  # stored expiry claims. Minting a replacement needs the embedded request's
  # session token, so this only works on a live embedded load. Returns true
  # when the shop has a working session again.
  def recover_dead_offline_token!(shop, session_token)
    return false if shop.blank?

    # Before every other bail-out: rendering the bootstrap shell is only safe
    # once `usable?` reports false, otherwise the client's exchange
    # short-circuits on the stale expiry and reloads into the same 401.
    failed_token = shop.shopify_token
    unless ShopifyServices::OfflineTokenService.invalidate!(shop, failed_token: failed_token)
      # Another request replaced the token while this one was failing on the
      # old copy. Theirs is untested rather than known-dead, so retry on it
      # instead of minting a third token nobody asked for.
      shop.init_session
      return true
    end

    return false if ShopifyServices::OfflineTokenService.remint_attempted?(shop)
    return false if session_token.blank?

    ShopifyServices::OfflineTokenService.ensure_fresh!(shop, session_token: session_token)
    ShopifyServices::OfflineTokenService.mark_remint_attempted(shop)
    shop.init_session
    true
  rescue StandardError => e
    Rails.logger.warn("[OfflineToken] 401 recovery failed shop=#{shop.shopify_domain}: #{e.class}: #{e.message}")
    false
  end

  def current_referral_partner
    @current_referral_partner ||= ReferralPartner.find(session[:referral_partner_id]) if session[:referral_partner_id]
  end
  
  def referral_partner_signed_in?
    current_referral_partner.present?
  end
  
  def require_referral_partner_login
    unless referral_partner_signed_in?
      redirect_to referral_login_path, alert: 'Please log in to access this page.'
    end
  end
  
  

    def set_locale
      locales = request.env['HTTP_ACCEPT_LANGUAGE'] || ""
      locale = locales.scan(/[a-z]{2}(?=\;)/).find do |locale|
        I18n.available_locales.include?(locale.to_sym)
      end
      I18n.locale = locale&.to_sym || I18n.default_locale
    end

    def set_shop
      # @shop = Shop.cacher.find_by(shopify_domain: current_shopify_domain)
      @shop = Shop.find_by_shopify_domain_with_cache(current_shopify_domain)
    end

    def get_domain
      # current_shopify_domain in admin dashboard
      if defined?(current_shopify_domain) &&
         !current_shopify_domain.blank? &&
         !current_shopify_domain.nil?
            current_shopify_domain
      else
        # shop in redirect && domain in first script tag call.
        params[:shop] || params[:domain]
      end
    end

    helper_method :current_referral_partner, :referral_partner_signed_in?

    # def set_sentry_context
    #   if not Rails.env.development?
    #     Sentry.configure_scope do |scope|
    #       scope.set_extras('shop.domain' => get_domain)
    #       scope.set_extras('request.url' => request.url)
    #       scope.set_extras('request.params' => params.to_unsafe_h)
    #     end
    #     Sentry.set_user(
    #       id: get_domain,
    #     )
    #   end
    # end
end

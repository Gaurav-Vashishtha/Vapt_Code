# frozen_string_literal: true

class HomeController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::RequireKnownShop
  before_action :set_shop
  skip_before_action :check_shop_domain, only: [:update_permissions, :check_permissions], raise: false

  def index
    # required for redirect to dashboard.
    @shop_origin = request.params['host']
    if !@shop_origin.present?
      @shop_origin = session[:shopify_host]
      # base64 encode "shop/admin" if query.host is absent
      if !@shop_origin.present?
        @shop_origin = Base64.encode64("#{@shop.shopify_domain}/admin");
      end
    end
    if @shop_origin.present?
      session[:shopify_host] = @shop_origin
    end
    # initiate session
    response.set_header('content-security-policy', "frame-ancestors https://#{@shop.shopify_domain} https://admin.shopify.com;")

    # When the offline token can't serve the Admin API in THIS request — first
    # install (no token yet), a legacy non-expiring token (Shopify now 403s
    # these), or an expired token with a dead refresh token — we can't migrate it
    # inline because the initial document load carries no session token (id_token).
    # So paint the app shell now and let the client mint/migrate the token via
    # POST /session/bootstrap (which carries a fresh App Bridge session token),
    # then reload into the full flow below. Avoids both blocking on a slow
    # exchange and 403ing on a legacy token.
    return render_bootstrap_shell unless ShopifyServices::OfflineTokenService.usable?(@shop)

    # Upgrade a legacy/expired offline token to an expiring one using this
    # embedded request's session token, BEFORE any Admin API call (check_scope_and_reauth
    # calls ShopifyAPI::AccessScope.find(:all), which 403s on a stale token).
    begin
      ShopifyServices::OfflineTokenService.ensure_fresh!(@shop, session_token: params[:id_token])
    rescue ShopifyServices::OfflineTokenService::Error => e
      Rails.logger.warn("[OfflineToken] migrate-on-load failed shop=#{@shop.shopify_domain}: #{e.message}")
    end
    @shop.init_session()

    begin
      load_dashboard
    rescue ActiveResource::UnauthorizedAccess => e
      Rails.logger.warn("[OfflineToken] admin api 401 shop=#{@shop.shopify_domain}: #{e.message}")
      return bootstrap_after_dead_token unless recover_dead_offline_token!(@shop, params[:id_token])

      begin
        load_dashboard
      rescue ActiveResource::UnauthorizedAccess => retry_error
        Rails.logger.error("[OfflineToken] admin api 401 survived re-mint shop=#{@shop.shopify_domain}: #{retry_error.message}")
        return bootstrap_after_dead_token
      end
    end
    ShopifyServices::OfflineTokenService.clear_remint_marker(@shop) if @admin_api_verified
  end

  # POST /update_permissions
  # Checks if shop's OAuth scopes match app's required scopes using GraphQL and returns reauth URL if needed
  def update_permissions
    shop_domain = params[:shop].presence || current_shopify_domain
    @shop = Shop.find_by(shopify_domain: shop_domain)
    return render json: { error: 'Shop not found' }, status: :not_found unless @shop

    @shop.init_session

    # Get granted scopes from GraphQL currentAppInstallation query
    shop_remote_scope = get_granted_scopes_via_graphql
    app_scope = ShopifyApp.configuration.scope.split(',').map(&:strip).sort

    # Build OAuth URL for reauthorization
    set_esdk_headers if respond_to?(:set_esdk_headers, true)
    session['omniauth.state'] = "12345"
    url = "https://#{@shop.shopify_domain}/admin/oauth/authorize"
    request_params = []
    request_params << "client_id=#{ENV['SHOPIFY_API_KEY']}"
    request_params << "scope=#{ERB::Util.url_encode(ShopifyApp.configuration.scope)}"
    request_params << "redirect_uri=#{ERB::Util.url_encode("https://#{ENV['APP_HOST']}/auth/shopify/callback")}"
    request_params << "state=12345"
    scope_refresh_url = "#{url}?#{request_params.join('&')}"

    # Need reauth only if any required scope is not granted (required ⊆ granted)
    granted_set = shop_remote_scope.map(&:to_s).to_set
    required_missing = app_scope.reject { |s| granted_set.include?(s.to_s) }
    needs_reauth = required_missing.any?

    render json: {
      needs_reauth: needs_reauth,
      scope_refresh_url: scope_refresh_url,
      granted_scopes: shop_remote_scope,
      required_scopes: app_scope
    }
  rescue StandardError => e
    Rails.logger.error "Error in update_permissions: #{e.message} #{e.backtrace.first(5).join("\n")}"
    # Even on error, return the reauth URL so user can still update permissions
    app_scope = ShopifyApp.configuration.scope
    url = "https://#{@shop&.shopify_domain || 'unknown'}/admin/oauth/authorize"
    request_params = []
    request_params << "client_id=#{ENV['SHOPIFY_API_KEY']}"
    request_params << "scope=#{ERB::Util.url_encode(app_scope)}"
    request_params << "redirect_uri=#{ERB::Util.url_encode("https://#{ENV['APP_HOST']}/auth/shopify/callback")}"
    request_params << "state=12345"
    scope_refresh_url = "#{url}?#{request_params.join('&')}"
    render json: { 
      error: e.message, 
      scope_refresh_url: scope_refresh_url,
      needs_reauth: true
    }, status: :internal_server_error
  end

  # GET /check_permissions - lightweight check for Summary to show/hide Update Permissions button
  def check_permissions
    shop_domain = params[:shop].presence || current_shopify_domain
    @shop = Shop.find_by(shopify_domain: shop_domain)
    return render json: { needs_reauth: true }, status: :ok unless @shop

    @shop.init_session
    shop_remote_scope = get_granted_scopes_via_graphql
    app_scope = ShopifyApp.configuration.scope.split(',').map(&:strip)
    granted_set = shop_remote_scope.map(&:to_s).to_set
    required_missing = app_scope.reject { |s| granted_set.include?(s.to_s) }
    needs_reauth = required_missing.any?

    render json: { needs_reauth: needs_reauth }
  rescue StandardError => e
    Rails.logger.error "Error in check_permissions: #{e.message}"
    render json: { needs_reauth: true }, status: :ok
  end

  def get_granted_scopes_via_graphql
    client = ShopifyAPI::GraphQL.client
    query = client.parse <<~GRAPHQL
      query {
        currentAppInstallation {
          accessScopes {
            handle
          }
        }
      }
    GRAPHQL

    response = client.query(query)
    if response&.data&.current_app_installation&.access_scopes
      response.data.current_app_installation.access_scopes.map(&:handle)
    else
      Rails.logger.warn "Could not fetch granted scopes via GraphQL, falling back to empty array. Response: #{response.inspect}"
      []
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching granted scopes via GraphQL: #{e.message} #{e.backtrace.first(3).join("\n")}"
    []
  end

  private
    def set_shop
      @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    end

    # Everything past this point needs a working Admin API token, so it runs
    # as one unit that HomeController#index can retry after re-minting.
    def load_dashboard
      check_scope_and_reauth

      # Fetch store data using shopify api.
      if @shop.primary_locale.nil?
        api_shop_data = ShopifyAPI::Shop.current
        owner_name = api_shop_data.name
        @shop.update(
          customer_email: api_shop_data.customer_email,
          owner_email: api_shop_data.email ,
          owner_name: owner_name,
          primary_locale: api_shop_data.primary_locale ,
          owner_phone: api_shop_data.phone,
          country_code: api_shop_data.country_code,
          money_format: api_shop_data.money_format,
          currency: api_shop_data.currency,
          country_name: api_shop_data.country_name ,
          owner_timezone: api_shop_data.timezone,
          shop_owner: api_shop_data.shop_owner,
          plan: Plan.find_by(name: 'Free'),
          cod_include_tags: GlobalSetting.first.cod_include_tags,
          cod_exclude_tags: GlobalSetting.first.cod_exclude_tags,
          primary_domain: api_shop_data.domain,
          shopify_plan: api_shop_data.plan_name,
          shop_created_date: api_shop_data.created_at,

        )
        # Fire only after owner_phone & co. are persisted — firing earlier (from
        # InstallJob) raced this save and skipped with no_recipient. The
        # primary_locale guard means this runs exactly once per shop.
        MerchantWhatsapp::Events.fire(:installed, shop_id: @shop.id)
      end

      if I18n.available_locales.excluding(:bg, :ar, :hi, :hr, :sl).include?(@shop.primary_locale[0..1]&.to_sym)
        I18n.locale = @shop.primary_locale[0..1]&.to_sym
      else
        I18n.locale = :en
      end
      @setting = Setting.find_or_initialize_by(shop_id: @shop.id)
      @plan = @shop.plan || Plan.find_by(name: 'Free')

      @setting = Shops::EnsureSettingService.call(@shop) unless @shop.setting

      # Initialize cart transform if not already set
      begin
        if @shop.setting.present?
          ShopifyServices::CartTransformService.call(@shop)
        end
      rescue ActiveResource::UnauthorizedAccess
        # A dead token is not the "missing scope" case this rescue exists for,
        # and swallowing it here hides the 401 from the recovery path upstream.
        raise

      rescue => e
        Rails.logger.error "Failed to initialize cart transform for shop #{@shop.shopify_domain}: #{e.message}"
        # Don't break the flow if cart transform creation fails (access scope might not be available for all shops)
      end

      # code for charge initiated.
      # `@charge_processed` makes this safe to re-run after a 401 retry. It
      # persists charge_id before sending the upgrade mail and running
      # ChargeActivatedJob, so replaying it would read its own write and report
      # 'error' for a charge that actually succeeded — but skipping it wholesale
      # would drop an upgrade whose very first API call is what failed.
      @upgrade_status ||= ''
      if @shop && params['charge_id'] && !@charge_processed
        recurring_charge = ShopifyAPI::RecurringApplicationCharge.find(
          request.params['charge_id']
        )
        if recurring_charge.status == 'active' and
           request.params['charge_id'] != @shop.charge_id
          @charge_processed = true
          @shop.update(
            plan: Plan.find(params['plan_id']), charge_id: request.params['charge_id']
          )
          WelcomeMailer.plan_upgrade(
            @shop.owner_email, {
              name: @shop.shop_owner,
              shopify_domain: @shop.shopify_domain,
              owner_name: @shop.owner_name
            }).deliver_later
          ChargeActivatedJob.perform_now @shop.id
          @upgrade_status = 'success'
          if @shop.plan.name != 'Free' && (@shop.setting.lock_paid_feature==true)
            @shop.setting.update(lock_paid_feature:false)
            resp = ShopifyServices::PaymentCustomizationService.call(@shop , '')
            if resp.blank?
              SlackNotifier::CLIENT.ping(
                text: "Error refreshing meta fields while unlocking the shop - #{@shop.shopify_domain}",
              )
            end
          end
        else
          @upgrade_status = 'error'
        end
      end

      @crisp_url = @shop.crisp_url
      @twilio_pricing = TwilioPricing.payload_for_shop(@shop)
      if not @shop.visible_plans.blank?
        @visible_plans = Plan.find(@shop.visible_plans.split(','))
      else
        # @visible_plans = Plan.where(name: ['Light', 'Plus', 'Premium'])
      end

      # @products = ShopifyAPI::Product.find(:all, params: { limit: 10 })
      # @webhooks = ShopifyAPI::Webhook.find(:all)
    end

    # The shell is only useful once `usable?` reports false — otherwise the
    # client's exchange short-circuits on a stale expiry and reloads into the
    # same 401. Paths that arrive here may have skipped their invalidate (a
    # sibling had replaced the token) or failed it (row lock contention), so
    # force it. We already know this token 401s.
    def bootstrap_after_dead_token
      begin
        ShopifyServices::OfflineTokenService.invalidate!(@shop)
      rescue StandardError => e
        Rails.logger.warn("[OfflineToken] forced invalidate failed shop=#{@shop.shopify_domain}: #{e.class}: #{e.message}")
      end
      render_bootstrap_shell
    end

    # Renders the React shell with DB-only data and a `needs_bootstrap` flag, so
    # the client can mint the offline token (POST /session/bootstrap) and reload —
    # used on first install before any Admin API token exists. No Shopify Admin
    # calls here, so it can never block on the token exchange.
    def render_bootstrap_shell
      @needs_bootstrap = true
      @setting = Setting.find_or_initialize_by(shop_id: @shop.id)
      @plan = @shop.plan || Plan.find_by(name: 'Free')
      @crisp_url = @shop.crisp_url
      @twilio_pricing = TwilioPricing.payload_for_shop(@shop)
      @visible_plans = @shop.visible_plans.present? ? Plan.find(@shop.visible_plans.split(',')) : nil
      render :index
    end

end

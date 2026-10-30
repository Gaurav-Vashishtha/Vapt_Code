# frozen_string_literal: true
class ScriptController < ApplicationController
  after_action :allow_iframe, only: [:settings, :widget_preview]

  protect_from_forgery except: :index

  layout "script", only: [:show]

  def index
    if Rails.env.development?
    script_js_file = JSON.parse(
      File.read(Rails.root.join('public', 'packs', 'manifest.json'))
    )["script_react.js"]

    redirect_to "https://#{request.host}#{script_js_file}?v=#{params['version']}&shop=#{params['shop']}"
    else
      redirect_to "#{ENV['SCRIPT_JS_URL']}"
    end 
  end

  def lightweight_settings
    begin
      setting = current_shop&.setting
      unless setting
        render json: {}, status: :ok
        return
      end

      refreshed_at = setting.metafield_settings_refreshed_at
      if refreshed_at.present? && refreshed_at >= 120.minutes.ago
        # Metafields were refreshed recently; just return current settings from DB
        render json: setting.lightweight_settings_payload, status: :ok
        return
      end

      # Stale or missing metafield timestamp: still return DB payload only.
      # (RefreshMetafieldLightweightSettingsJob is not enqueued from this app — no perform_later call here.)
      render json: setting.lightweight_settings_payload, status: :ok

    rescue => e
      Rails.logger.error "Script#lightweight_settings Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        success: false,
        error: 'Failed to fetch lightweight settings'
      }, status: :internal_server_error
    end
  end

  # Accepts frontend error reports (some clients call /script/post_error).
  # We keep it lightweight and always return 200 so it never blocks UX.
  def post_error
    Rails.logger.warn "[Script#post_error] #{request.remote_ip} payload=#{params.except(:controller, :action).to_json}"
    render json: { success: true }, status: :ok
  rescue StandardError => e
    Rails.logger.warn "[Script#post_error] error=#{e.class}: #{e.message}"
    render json: { success: false }, status: :ok
  end
  
  def refresh_lightweight_settings
    begin
      current_shop&.expire_lightweight_settings_cache if current_shop.respond_to?(:expire_lightweight_settings_cache)
      
      # Call the lightweight_settings method to get fresh data
      lightweight_settings
      
    rescue => e
      Rails.logger.error "Script#refresh_lightweight_settings Error: #{e.message}"
      
      render json: {
        success: false,
        error: 'Failed to refresh settings cache'
      }, status: :internal_server_error
    end
  end

  def script_react_new
    if Rails.env.development?
    script_js_file = JSON.parse(
      File.read(Rails.root.join('public', 'packs', 'manifest.json'))
    )["script_react_new.js"]

    redirect_to "https://#{request.host}#{script_js_file}?v=#{params['version']}&shop=#{params['shop']}"
    else
      redirect_to "#{ENV['SCRIPT_JS_NEW_URL']}"
    end 
    
  end

  def notifik
    manifest_path = Rails.root.join('public', 'notifik-js-app', 'manifest.json')

    if File.exist?(manifest_path)
      manifest = JSON.parse(File.read(manifest_path))
      asset_path = manifest['notifik.js']
      redirect_to asset_path
      # redirect_to "https://cdn.shopify.com/s/files/1/0624/3985/0047/files/notifik.3825479ae682625df440.js?v=1759390440"
    elsif Rails.env.development?
      dev_server_url = ENV.fetch('VANILLA_JS_DEV_URL', 'https://localhost:9001')
      redirect_to "#{dev_server_url}/notifik.js"
    else
      # Fallback or error handling for production if manifest is not found
      render plain: "/* Asset not found */", status: :not_found, content_type: 'application/javascript'
    end
  end

  def notifik_svelte
    manifest_path = Rails.root.join('public', 'notifik-svelte-app', 'manifest.json')

    if Rails.env.production?
      redirect_to "#{ENV['SCRIPT_JS_SVELTE_URL']}"
  
    elsif File.exist?(manifest_path)
      manifest = JSON.parse(File.read(manifest_path))
      # Svelte manifest uses 'src/main.js' as the key
      entry = manifest['src/main.js']
      if entry && entry['file']
        asset_path = "/notifik-svelte-app/#{entry['file']}"
        redirect_to asset_path
      else
        render plain: "/* Svelte manifest entry not found */", status: :not_found, content_type: 'application/javascript'
      end
    elsif Rails.env.development?
      dev_server_url = ENV.fetch('SVELTE_DEV_URL', 'http://localhost:5173')
      redirect_to "#{dev_server_url}/src/main.js"
    else
      # Fallback or error handling for production if manifest is not found
      render plain: "/* Svelte asset not found */", status: :not_found, content_type: 'application/javascript'
    end
  end

  # Host page for the admin's live widget preview. Renders a stand-alone
  # document that fakes just enough storefront for the real Svelte widget to
  # boot inside it; everything shop-specific is pushed in over postMessage by
  # LiveWidgetPreview.jsx, so this stays public and takes no parameters.
  def widget_preview
    render layout: false
  end

  def notifik_svelte_css
    if Rails.env.production?
      redirect_to "#{ENV['SCRIPT_JS_SVELTE_CSS_URL']}"
      return
    end

    manifest_path = Rails.root.join('public', 'notifik-svelte-app', 'manifest.json')

    if File.exist?(manifest_path)
      manifest = JSON.parse(File.read(manifest_path))
      entry = manifest['src/main.js']
      if entry && entry['css'] && entry['css'].first
        css_path = "/notifik-svelte-app/#{entry['css'].first}"
        redirect_to css_path
      else
        render plain: "/* CSS not found */", status: :not_found, content_type: 'text/css'
      end
    elsif Rails.env.development?
      # In dev mode, CSS is injected by JS
      render plain: "/* Dev mode - CSS injected by JS */", content_type: 'text/css'
    else
      render plain: "/* CSS not found */", status: :not_found, content_type: 'text/css'
    end
  end


  def show

  end

  def translations
    render json:  I18n::JS.filtered_translations[params[:lang].to_sym][:script]
  end

  def settings
    if params[:domain].blank?
      render :json => {'success':false}
      return
    end
    @shop = Shop.find_by_shopify_domain_with_cache(params[:domain]) 
    if @shop
      @setting = @shop.setting
      render :json => @setting.to_json(
        :except => [
          :provider, :provider_api_key, :provider_sender_id,
          :payment_provider_api_key, :payment_provider_api_secret, :private_payment_provider,
          :pixel_token, :google_conversion_token, :whatsapp_operator_config,
          :ivr_introduction, :ivr_confirm_message, :ivr_cancel_message,
        ]
      )
    else
      render :json => Setting.new.to_json(
        :except => [
          :provider, :provider_api_key, :provider_sender_id,
          :ivr_introduction, :ivr_confirm_message, :ivr_cancel_message,
          :prepaid_template
        ]
      )
    end
  end

  def delete_data
    cod_form_privacy_webhook
    render json: {
       ok: true
    }
  end

  # COD Form data for Shopify's privacy webhooks (customers/data_request, customers/redact,
  # shop/redact). Guarded: it acts only on a request signed by Shopify, and it can never
  # change this endpoint's answer.
  def cod_form_privacy_webhook
    signature = request.headers['HTTP_X_SHOPIFY_HMAC_SHA256'].to_s
    secret = ENV['SHOPIFY_API_SECRET'].to_s
    return if signature.blank? || secret.blank?

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', secret, request.raw_post))
    return unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)

    payload = JSON.parse(request.raw_post)
    topic = request.headers['HTTP_X_SHOPIFY_TOPIC'].to_s
    CodForm::PrivacyService.handle_webhook(topic: topic, payload: payload)
  rescue StandardError => e
    Rails.logger.error("[codf/privacy] webhook not processed: #{e.class}")
  end

  def current_shop
    @current_shop ||= begin
      if params[:shop].present?
        Shop.find_by_shopify_domain_with_cache(params[:shop])
      elsif params[:domain].present?
        Shop.find_by_shopify_domain_with_cache(params[:domain])
      else
        nil
      end
    end
  end

  private
    def allow_iframe
      response.headers.delete "X-Frame-Options"
    end

end

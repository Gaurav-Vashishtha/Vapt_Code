# frozen_string_literal: true

require "net/http"

module CodFormAdmin
  # Google Sheets connection (I.5, INT-1). Gate `google_sheets` + ENV["GOOGLE_SHEETS_CLIENT_ID"].
  #
  #   GET /cod_form/integrations/google_sheets/auth_url  (session token) → {"url"}
  #   GET /cod_form/integrations/google_sheets/sheets    (session token) → {"spreadsheets": [{"id","name"}]}
  #   GET /cod_form/google/callback                      (public: the signed `state` is the authentication)
  class GoogleOauthController < BaseController
    AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
    SCOPES = %w[https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/drive.file].freeze
    STATE_TTL = 15.minutes
    PROVIDER = "google_sheets"

    # The callback is opened by Google in a popup: no App Bridge session token exists there.
    PUBLIC_ACTIONS = %i[callback].freeze
    skip_before_action :set_shop, :require_shop!, :load_config, :require_module!, only: PUBLIC_ACTIONS
    %i[login_again_if_different_user_or_shop login_again_if_different_shop check_shop_domain shopify_session].each do |callback|
      skip_before_action callback, only: PUBLIC_ACTIONS, raise: false
    end
    skip_around_action :activate_shopify_session, only: PUBLIC_ACTIONS, raise: false
    skip_after_action :add_top_level_redirection_headers, only: PUBLIC_ACTIONS, raise: false

    before_action :require_google_sheets!, only: %i[auth_url sheets]

    def auth_url
      state = self.class.verifier.generate({ "shop_id" => @shop.id }, expires_in: STATE_TTL, purpose: :google_sheets)
      query = {
        client_id: ENV.fetch("GOOGLE_SHEETS_CLIENT_ID", nil), redirect_uri: redirect_uri, response_type: "code",
        scope: SCOPES.join(" "), access_type: "offline", prompt: "consent", include_granted_scopes: "true",
        state: state
      }
      render json: { "url" => "#{AUTH_ENDPOINT}?#{query.to_query}" }
    end

    def sheets
      integration = CodForm::Integration.find_by(shop_id: @shop.id, provider: PROVIDER)
      invalid!("base", "connect Google Sheets first") if integration.nil? || integration.credentials["refresh_token"].blank?

      client = CodForm::Integrations::GoogleSheets::Client.new(integration)
      payload = { "spreadsheets" => Array(client.list_spreadsheets).map { |sheet| { "id" => sheet["id"], "name" => sheet["name"] } } }
      # Optional: ?spreadsheet_id=… also returns the tab names of that spreadsheet.
      spreadsheet_id = params[:spreadsheet_id].to_s
      payload["sheet_names"] = Array(client.sheet_names(spreadsheet_id)) if spreadsheet_id.match?(/\A[A-Za-z0-9_\-]{10,200}\z/)
      render json: payload
    rescue ValidationError
      raise
    rescue CodForm::Integrations::GoogleSheets::Client::AuthError
      # The merchant revoked access or the refresh token expired: the screen offers "Reconnect".
      render json: { "error" => "google_reconnect_required" }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.warn("[CodFormAdmin::GoogleOauthController] sheets failed shop_id=#{@shop.id} #{e.class}")
      render json: { "error" => "google_unavailable" }, status: :bad_gateway
    end

    def callback
      @ok = false
      payload = self.class.verifier.verified(params[:state].to_s, purpose: :google_sheets)
      shop = payload.is_a?(Hash) ? Shop.find_by(id: payload["shop_id"]) : nil
      if shop && params[:code].present? && params[:error].blank?
        tokens = exchange_code(params[:code].to_s)
        if tokens && tokens["refresh_token"].present?
          integration = CodForm::Integration.for(shop, PROVIDER)
          integration.update!(
            credentials: {
              "refresh_token" => tokens["refresh_token"], "access_token" => tokens["access_token"],
              "expires_at" => (Time.current + tokens["expires_in"].to_i.seconds).utc.iso8601
            },
            status: CodForm::Integration::STATUS_CONNECTED, last_error: nil
          )
          CodForm::MerchantAudit.record(shop, "integration.google_sheets.status", "disconnected", "connected")
          @ok = true
        end
      end
      response.set_header("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'")
      render :callback, layout: false, status: @ok ? :ok : :unprocessable_entity
    end

    def self.verifier
      Rails.application.message_verifier("cod_form_google")
    end

    private

    def require_google_sheets!
      gate!("google_sheets")
      return if ENV.fetch("GOOGLE_SHEETS_CLIENT_ID", nil).present? && ENV.fetch("GOOGLE_SHEETS_CLIENT_SECRET", nil).present?

      render json: { "error" => "not_available" }, status: :unprocessable_entity
    end

    def redirect_uri
      "https://#{ENV.fetch("APP_HOST", nil)}/cod_form/google/callback"
    end

    # => token hash, or nil. Never logs the code or the tokens.
    def exchange_code(code)
      uri = URI(TOKEN_ENDPOINT)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(
          "code" => code, "client_id" => ENV.fetch("GOOGLE_SHEETS_CLIENT_ID", nil),
          "client_secret" => ENV.fetch("GOOGLE_SHEETS_CLIENT_SECRET", nil), "redirect_uri" => redirect_uri,
          "grant_type" => "authorization_code"
        )
        http.request(request)
      end
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

      Rails.logger.warn("[CodFormAdmin::GoogleOauthController] token exchange failed status=#{response.code}")
      nil
    rescue StandardError => e
      Rails.logger.warn("[CodFormAdmin::GoogleOauthController] token exchange failed #{e.class}")
      nil
    end
  end
end

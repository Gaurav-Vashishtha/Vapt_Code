# frozen_string_literal: true

module Api
  module V1
    module Cb
      # Public custom-branded WhatsApp API. Two credentials:
      #
      # 1. PARTNER key (ENV['CB_PARTNER_API_KEY']) — ParcelX's server-side
      #    master credential. Selects the brand per request via `shop_domain`
      #    (body or query). The only credential that can register brands.
      # 2. Per-brand key (CustomBrandedApiKey, minted on the portal) — scoped
      #    to one brand; `shop_domain` is only a cross-check.
      class BaseController < ActionController::API
        before_action :authenticate_api_key!
        before_action :require_client!

        rescue_from StandardError do |e|
          Rails.logger.error("[api/v1/cb] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
          render json: { error: 'internal error' }, status: :internal_server_error
        end

        private

        attr_reader :current_api_key

        def bearer_token
          request.headers['Authorization'].to_s[/\ABearer (.+)\z/, 1]
        end

        def authenticate_api_key!
          token = bearer_token
          partner_key = ENV['CB_PARTNER_API_KEY'].presence

          if token.present? && partner_key &&
             ActiveSupport::SecurityUtils.secure_compare(token, partner_key)
            @partner_authenticated = true
            return
          end

          @current_api_key = CustomBrandedApiKey.authenticate(token)
          return if @current_api_key

          render json: { error: 'unauthorized' }, status: :unauthorized
        end

        def partner_authenticated?
          @partner_authenticated == true
        end

        # Resolve the brand this request operates on. Partner key → from
        # shop_domain; per-brand key → from the key (shop_domain only
        # cross-checked, since a key pasted into the wrong tenant's config is
        # far more likely a partner-side bug than an attack — fail loudly).
        def require_client!
          if partner_authenticated?
            domain = CustomBrandedClient.normalize_domain(params[:shop_domain])
            if domain.blank?
              return render_error('shop_domain is required when using the partner API key', :unprocessable_entity)
            end

            @client = CustomBrandedClient.find_by(domain: domain)
            return render_error("unknown brand #{domain.inspect} — register it via POST /api/v1/cb/brands first", :not_found) if @client.nil?
          else
            @client = current_api_key.custom_branded_client
            supplied = CustomBrandedClient.normalize_domain(params[:shop_domain])
            if supplied.present? && supplied != @client.domain
              render_error('shop_domain does not match this API key', :unprocessable_entity)
            end
          end
        end

        def client
          @client
        end

        def render_error(error, status = :bad_request, detail: nil)
          payload = { error: error }
          payload[:detail] = detail if detail
          render json: payload, status: status
        end
      end
    end
  end
end

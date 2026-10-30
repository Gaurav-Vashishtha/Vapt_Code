# frozen_string_literal: true

module Api
  module Form
    # Public storefront API of the COD Form (docs/cod-form/ARCHITECTURE.md D.0).
    #
    # Transport: POST with `Content-Type: text/plain` and a JSON string body (a CORS "simple
    # request": no preflight), `?shop=<myshopify domain>` on every URL, the session token in
    # the body. The body is never logged and never becomes `params`.
    class BaseController < ActionController::API
      MAX_BODY_BYTES = 64 * 1024
      TOKEN_SALT = "cod_form_session_v1"
      HONEYPOT_FIELD = CodForm::OrderService::HONEYPOT_FIELD

      rescue_from StandardError, with: :render_internal_error
      rescue_from CodForm::Errors::ApiError, with: :render_api_error

      before_action :parse_body!
      before_action :load_shop!
      before_action :check_origin!
      before_action :check_module!
      before_action :authenticate_session!

      class << self
        # 32-byte HMAC key derived from secret_key_base; never leaves the server.
        def token_secret
          @token_secret ||= Rails.application.key_generator.generate_key(TOKEN_SALT, 32)
        end
      end

      private

      attr_reader :body, :shop, :shop_config, :form_session

      def parse_body!
        raw = request.raw_post.to_s
        raise CodForm::Errors.build("invalid_request") if raw.bytesize > MAX_BODY_BYTES

        parsed = raw.strip.empty? ? {} : JSON.parse(raw)
        raise CodForm::Errors.build("invalid_request") unless parsed.is_a?(Hash)

        @body = parsed
      rescue JSON::ParserError
        raise CodForm::Errors.build("invalid_request")
      end

      def load_shop!
        domain = params[:shop].to_s.strip.downcase
        unless domain.match?(/\A[a-z0-9][a-z0-9\-]*\.myshopify\.com\z/)
          raise CodForm::Errors.build("shop_not_found")
        end

        @shop = Shop.find_by_shopify_domain_with_cache(domain)
        raise CodForm::Errors.build("shop_not_found") if @shop.nil?

        @shop_config = CodForm::ShopConfig.for(@shop)
      end

      def check_origin!
        return if CodForm::OriginGuard.allowed?(shop, shop_config, request)

        raise CodForm::Errors.build("origin_not_allowed")
      end

      # Kill switch / module flag / mode / core gate. A shop that is not live yet (mode off)
      # is still usable by staff test sessions: that is settled in authenticate_session!.
      def check_module!
        @availability = CodForm::Availability.call(shop, config: shop_config)
        return if @availability[:available] || @availability[:mode_off]

        raise CodForm::Errors.build(@availability[:fallback] == "kill_switch" ? "kill_switch" : "module_disabled")
      end

      def authenticate_session!
        result = CodForm::Engine::SessionToken.verify(
          secret: self.class.token_secret, token: body["token"].to_s, now: Time.current.to_i
        )
        failure = CodForm::Errors.token_failure(result, shop_id: shop.id)
        raise CodForm::Errors.build(failure) if failure

        session = CodForm::Session.find_by(shop_id: shop.id, public_id: result["session_id"])
        raise CodForm::Errors.build("invalid_token") if session.nil?
        raise CodForm::Errors.build("token_expired") if session.expired? || session.status == CodForm::Session::STATUS_EXPIRED
        # The test flag is part of the signature and of the row; they must agree.
        raise CodForm::Errors.build("invalid_token") unless (result["test"] == true) == (session.is_test == true)
        raise CodForm::Errors.build("module_disabled") unless CodForm::Availability.usable?(@availability, test: session.is_test)

        @token = result
        @form_session = session
      end

      # Optional authentication (events): a bad or missing token is simply "no session".
      def authenticate_session_if_present
        return if body["token"].to_s.empty?

        authenticate_session!
      rescue CodForm::Errors::ApiError
        @form_session = nil
      end

      def request_meta
        {
          "ip" => request.remote_ip.to_s,
          "user_agent" => request.user_agent.to_s[0, 500],
          "token_issued_at" => @token ? @token["issued_at"] : nil
        }
      end

      # No keyword parameters on purpose: callers pass string-keyed hashes without braces.
      def render_ok(payload = {})
        response.headers["Cache-Control"] = "no-store"
        render json: { "ok" => true }.merge(payload), status: :ok
      end

      def render_api_error(error)
        response.headers["Cache-Control"] = "no-store"
        response.headers["Retry-After"] = error.retry_after.to_i.to_s if error.retry_after
        render json: error.to_h, status: error.http_status
      end

      # Class and location only: an exception message can carry buyer data.
      def render_internal_error(error)
        Rails.logger.error(
          "[Api::Form] #{self.class.name}##{action_name} shop=#{params[:shop].to_s[0, 80]} #{error.class} at " \
          "#{Array(error.backtrace).first(3).map { |line| line.to_s.sub(Rails.root.to_s, '')[0, 120] }.join(' < ')}"
        )
        Sentry.capture_exception(error) if defined?(Sentry)
        render json: CodForm::Errors.envelope("internal_error"), status: :internal_server_error
      end
    end
  end
end

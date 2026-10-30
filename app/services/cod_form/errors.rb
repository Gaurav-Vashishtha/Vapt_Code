# frozen_string_literal: true

# Error catalogue of the storefront API (ARCHITECTURE.md D.0.3).
#
# Pure Ruby: no Rails, no ActiveSupport. The controllers rescue
# CodForm::Errors::ApiError and render `error.to_h` with `error.http_status`.
module CodForm
  module Errors
    # code => [http status, message_key, fallback]
    # Every message_key is a text key of the storefront form (ARCHITECTURE.md G.7, src/i18n/en.json):
    # the browser renders the key, so a key outside that list would show as the generic error.
    # test/services/cod_form/errors_test.rb checks the list against config/cod_form/default_texts.json.
    DEFINITIONS = {
      "invalid_request"       => [400, "error_generic", nil],
      "invalid_token"         => [401, "error_generic", nil],
      "token_expired"         => [401, "error_generic", nil],
      "origin_not_allowed"    => [403, "error_generic", "checkout"],
      "module_disabled"       => [403, "error_generic", "checkout"],
      "shop_not_found"        => [404, "error_generic", "checkout"],
      "cap_reached"           => [409, "error_generic", "checkout"],
      "total_changed"         => [409, "error_total_changed", nil],
      "already_processing"    => [409, "error_generic", nil],
      "upsell_expired"        => [410, "error_generic", nil],
      "validation_failed"     => [422, "error_generic", nil],
      "not_eligible"          => [422, "error_not_eligible", nil],
      "blocked"               => [422, "error_blocked", nil],
      "limit_reached"         => [422, "error_limit_reached", nil],
      "bot_suspected"         => [422, "error_generic", nil],
      "no_shipping_rate"      => [422, "error_no_shipping", nil],
      "out_of_stock"          => [422, "error_out_of_stock", nil],
      "discount_invalid"      => [422, "error_discount_invalid", nil],
      "otp_invalid"           => [422, "error_otp_invalid", nil],
      "otp_attempts_exceeded" => [422, "error_otp_attempts", nil],
      "otp_required"          => [428, "error_generic", nil],
      "rate_limited"          => [429, "error_generic", nil],
      "otp_throttled"         => [429, "error_otp_send", nil],
      "order_failed"          => [502, "error_order_failed", nil],
      "kill_switch"           => [503, "error_generic", "checkout"],
      "internal_error"        => [500, "error_generic", nil]
    }.freeze

    # Raised by services, rendered by Api::Form::BaseController.
    class ApiError < StandardError
      attr_reader :code, :http_status, :message_key, :custom_message, :fallback, :fields, :retry_after, :extra

      # extra: top-level keys merged into the response body next to "ok" and
      # "error" (e.g. "quote", "eligibility", "poll_after_ms", "attempts_left").
      def initialize(code, message: nil, message_key: nil, fields: nil, retry_after: nil, extra: nil, fallback: :default)
        code = code.to_s
        definition = DEFINITIONS[code] || DEFINITIONS["internal_error"]
        @code = code
        @http_status = definition[0]
        @message_key = message_key || definition[1]
        @fallback = fallback == :default ? definition[2] : fallback
        @custom_message = message.to_s.strip.empty? ? nil : message.to_s
        @fields = fields.is_a?(Hash) ? fields : {}
        @retry_after = retry_after
        @extra = extra.is_a?(Hash) ? extra : {}
        super(code)
      end

      def to_h
        Errors.envelope(
          code,
          message: custom_message, message_key: message_key, fields: fields,
          retry_after: retry_after, extra: extra, fallback: fallback
        )
      end
    end

    # Unknown / malformed cart item (CodForm::CatalogService).
    class InvalidItem < ApiError
      def initialize(detail = nil)
        @detail = detail
        super("invalid_request", fields: { "items" => "error_generic" })
      end

      attr_reader :detail
    end

    module_function

    def known?(code)
      DEFINITIONS.key?(code.to_s)
    end

    def http_status(code)
      (DEFINITIONS[code.to_s] || DEFINITIONS["internal_error"])[0]
    end

    def build(code, **opts)
      ApiError.new(code, **opts)
    end

    # The D.0.3 envelope as a string-keyed hash. `message` is present only when
    # the merchant configured a custom text.
    def envelope(code, message: nil, message_key: nil, fields: nil, retry_after: nil, extra: nil, fallback: :default)
      code = code.to_s
      definition = DEFINITIONS[code] || DEFINITIONS["internal_error"]
      error = {
        "code" => code,
        "message_key" => message_key || definition[1],
        "fallback" => (fallback == :default ? definition[2] : fallback),
        "fields" => fields.is_a?(Hash) ? fields : {},
        "retry_after" => retry_after
      }
      error["message"] = message.to_s unless message.to_s.strip.empty?
      body = { "ok" => false, "error" => error }
      extra.each { |k, v| body[k.to_s] = v unless %w[ok error].include?(k.to_s) } if extra.is_a?(Hash)
      body
    end

    # Maps the result of CodForm::Engine::SessionToken.verify (E.12) to an API
    # error code, also checking that the token was issued for this shop.
    # Returns nil when the token is acceptable.
    def token_failure(result, shop_id:)
      return "invalid_token" unless result.is_a?(Hash)

      unless result["ok"] == true
        return result["error"].to_s == "expired" ? "token_expired" : "invalid_token"
      end
      return "invalid_token" if result["session_id"].to_s.empty?
      return "invalid_token" unless result["shop_id"].to_s == shop_id.to_s && !shop_id.to_s.empty?

      nil
    end
  end
end

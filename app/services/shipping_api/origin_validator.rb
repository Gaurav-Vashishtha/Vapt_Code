# frozen_string_literal: true

module ShippingApi
  # Validates request Origin (or Referer-derived origin) against
  # ENV["SHIPPING_API_ALLOWED_ORIGINS"] — comma-separated rules.
  #
  # When the env var is blank, all requests are allowed (backward compatible).
  #
  # Server-to-server: when SHIPPING_API_ALLOWED_ORIGINS is set, browsers send Origin;
  # other backends usually do not. Set SHIPPING_API_SERVER_SECRET and send either:
  #   X-Shipping-Api-Secret: <secret>
  #   Authorization: Bearer <secret>
  # That bypasses the origin check (same secret as env value).
  #
  # Each rule can be:
  # - Full origin: "https://my-store.myshopify.com"
  # - Host glob: "*.myshopify.com" (any single-label subdomain + suffix)
  # - Bare hostname: "checkout.shopify.com" (exact host match)
  #
  # In development/test only, a single rule "*" allows any origin (for local tooling).
  class OriginValidator
    class << self
      def permitted?(request)
        return server_to_server_authorized?(request) if require_secret?

        rules = parse_rules
        return true if rules.empty?

        return true if server_to_server_authorized?(request)

        origin = extract_origin(request)
        return false if origin.blank?

        normalized = normalize_origin(origin)
        return false if normalized.blank?

        rules.any? { |rule| matches?(normalized, rule) }
      end

      def parse_rules
        ENV.fetch("SHIPPING_API_ALLOWED_ORIGINS", "").split(",").map(&:strip).reject(&:blank?)
      end

      private

      def require_secret?
        ENV.fetch("SHIPPING_API_REQUIRE_SECRET", "").to_s.strip.casecmp?("true")
      end

      def server_to_server_authorized?(request)
        expected = ENV.fetch("SHIPPING_API_SERVER_SECRET", "").to_s
        return false if expected.blank?

        h = request.headers
        header_secret =
          h["X-Shipping-Api-Secret"].presence ||
          h["HTTP_X_SHIPPING_API_SECRET"].presence
        return true if secret_matches?(expected, header_secret)

        auth = h["Authorization"].presence || h["HTTP_AUTHORIZATION"].presence
        if auth.to_s.match?(/\ABearer\s+/i)
          token = auth.sub(/\ABearer\s+/i, "").strip
          return true if secret_matches?(expected, token)
        end

        false
      end

      def secret_matches?(expected, received)
        return false if received.blank?
        return false if expected.bytesize != received.bytesize

        ActiveSupport::SecurityUtils.secure_compare(expected, received)
      end

      def extract_origin(request)
        h = request.headers
        o = h["Origin"].presence || h["HTTP_ORIGIN"].presence
        return o if o.present?

        ref = h["Referer"].presence || h["HTTP_REFERER"].presence
        return nil if ref.blank?

        uri = URI.parse(ref)
        "#{uri.scheme}://#{uri.host}#{port_part(uri)}"
      rescue URI::InvalidURIError
        nil
      end

      def port_part(uri)
        return "" if uri.port.nil? || [80, 443].include?(uri.port)

        ":#{uri.port}"
      end

      def normalize_origin(str)
        u = URI.parse(str)
        "#{u.scheme}://#{u.host}#{port_part(u)}"
      rescue URI::InvalidURIError
        nil
      end

      def matches?(normalized_origin, rule)
        rule = rule.strip
        return dev_star_allowed? if rule == "*"

        origin_host = URI.parse(normalized_origin).host.to_s.downcase
        return false if origin_host.blank?

        if rule.start_with?("http://", "https://")
          normalize_origin(rule).casecmp?(normalized_origin)
        elsif rule.include?("*")
          host_glob_match?(origin_host, rule.downcase)
        else
          rh = rule.downcase
          origin_host == rh || origin_host.end_with?(".#{rh}")
        end
      rescue URI::InvalidURIError
        false
      end

      def dev_star_allowed?
        Rails.env.development? || Rails.env.test?
      end

      # "*.myshopify.com" => one subdomain label + suffix (e.g. shop-name.myshopify.com)
      def host_glob_match?(host, pattern)
        m = pattern.match(/\A\*\.(.+)\z/)
        return false unless m

        suffix = m[1]
        /\A[a-z0-9][a-z0-9\-]*\.#{Regexp.escape(suffix)}\z/i.match?(host)
      end
    end
  end
end

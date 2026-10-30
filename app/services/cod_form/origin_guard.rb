# frozen_string_literal: true

require "uri"

# Origin check of the storefront API (ARCHITECTURE.md D.0.2, F22/F23).
#
# The host matching is pure Ruby (no Rails) so it can be tested standalone;
# only `allowed?` / `check` touch a request, a shop and ENV.
module CodForm
  class OriginGuard
    PREVIEW_SUFFIX = ".shopifypreview.com"
    LOCAL_HOSTS = %w[localhost 127.0.0.1].freeze

    class << self
      # D.0.2: true when the request may proceed.
      # With COD_FORM_ORIGIN_ENFORCE=false a rejection is only logged.
      def allowed?(shop, shop_config, request)
        result = check(shop, shop_config, request)
        return true if result[:allowed]

        log_rejection(shop, result, "cod_form")
        !enforce?
      end

      # Never blocks by itself: returns {allowed:, host:, reason:}.
      def check(shop, shop_config, request)
        host = host_from(header(request, "Origin"), header(request, "Referer"))
        hosts = allowed_hosts(
          shopify_domain: shop.respond_to?(:shopify_domain) ? shop.shopify_domain : nil,
          primary_domain: shop.respond_to?(:primary_domain) ? shop.primary_domain : nil,
          extra: shop_config.respond_to?(:allowed_origins) ? shop_config.allowed_origins : nil
        )
        ok = host_allowed?(host, allowed_hosts: hosts, allow_localhost: allow_localhost?)
        { allowed: ok, host: host, reason: (ok ? nil : (host.nil? ? "missing_origin" : "host_not_allowed")) }
      end

      # D.12: legacy POST /api/cod_orders. Log-only unless
      # COD_ORDERS_ORIGIN_ENFORCE == "true". Returns true when the request may proceed.
      def legacy_allowed?(shop, request)
        shop_config = legacy_shop_config(shop)
        result = check(shop, shop_config, request)
        return true if result[:allowed]

        log_rejection(shop, result, "cod_orders")
        ENV["COD_ORDERS_ORIGIN_ENFORCE"].to_s != "true"
      rescue StandardError
        true
      end

      # --- pure helpers -----------------------------------------------------

      # Host (lower-case, no port) of the Origin header, else of the Referer.
      def host_from(origin, referer)
        extract_host(origin) || extract_host(referer)
      end

      def extract_host(value)
        str = value.to_s.strip
        return nil if str.empty? || str == "null"

        str = "https://#{str}" unless str.include?("://")
        host = URI.parse(str).host.to_s.downcase.sub(/\.\z/, "")
        host.empty? ? nil : host
      rescue URI::InvalidURIError
        nil
      end

      # Normalised list of hosts a shop may call from.
      def allowed_hosts(shopify_domain:, primary_domain:, extra:)
        list = [shopify_domain, primary_domain]
        list.concat(extra) if extra.is_a?(Array)
        list.map { |entry| extract_host(entry) }.compact.uniq
      end

      def host_allowed?(host, allowed_hosts:, allow_localhost: false)
        host = host.to_s.downcase
        return false if host.empty?
        return true if allowed_hosts.include?(host)
        return true if preview_host?(host)
        return true if allow_localhost && LOCAL_HOSTS.include?(host)

        false
      end

      # Any *.shopifypreview.com host (theme previews). The bare suffix and
      # look-alikes such as "evilshopifypreview.com" do not match.
      def preview_host?(host)
        host.end_with?(PREVIEW_SUFFIX) && host.length > PREVIEW_SUFFIX.length &&
          host.match?(/\A[a-z0-9][a-z0-9\-.]*\z/)
      end

      private

      def header(request, name)
        headers = request.respond_to?(:headers) ? request.headers : {}
        value = headers[name]
        value = headers["HTTP_#{name.upcase}"] if value.nil? || value.to_s.empty?
        value
      end

      def enforce?
        ENV["COD_FORM_ORIGIN_ENFORCE"].to_s != "false"
      end

      def allow_localhost?
        return true if ENV["COD_FORM_ALLOW_LOCALHOST"].to_s == "true"

        defined?(Rails) && Rails.respond_to?(:env) && Rails.env.development?
      end

      def legacy_shop_config(shop)
        return nil unless defined?(CodForm::ShopConfig)

        CodForm::ShopConfig.find_by(shop_id: shop.id)
      rescue StandardError
        nil
      end

      # No PII: shop id, the offending host and the reason only.
      def log_rejection(shop, result, scope)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        shop_id = shop.respond_to?(:id) ? shop.id : nil
        Rails.logger.warn(
          "[CodForm::OriginGuard] scope=#{scope} shop_id=#{shop_id} reason=#{result[:reason]} host=#{result[:host].to_s[0, 120]}"
        )
      end
    end
  end
end

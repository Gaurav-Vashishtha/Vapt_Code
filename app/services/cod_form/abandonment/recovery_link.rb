# frozen_string_literal: true

require "uri"
# Plain Ruby (tests) loads the sibling itself; under Rails Zeitwerk autoloads it.
require_relative "../engine/recovery" unless defined?(::Rails)

module CodForm
  module Abandonment
    # Pure choice of the page a recovery link points at (ARCHITECTURE.md I.4, ABN-2). No Rails.
    # The link itself is formatted by CodForm::Engine::Recovery.url.
    module RecoveryLink
      PARAM = CodForm::Engine::Recovery::PARAM
      PAGE_SOURCES = %w[product quick_buy embedded].freeze

      module_function

      # "https://<primary domain>/?codk_recover=<token>"; a product session reopens on its
      # product page (tracking.page_url) with the parameter appended. page_url is used only
      # when it is https and its host is one of the shop's own hosts, so a forged page_url can
      # never put a foreign link into a merchant's message.
      def build(primary_domain:, token:, source: nil, page_url: nil, allowed_hosts: [])
        host = host_of(primary_domain)
        return nil if host.nil? || token.to_s.empty?

        base = nil
        if PAGE_SOURCES.include?(source.to_s)
          hosts = [host] + Array(allowed_hosts).filter_map { |h| host_of(h) }
          base = clean_page_url(page_url, hosts)
        end
        CodForm::Engine::Recovery.url(primary_domain: base || host, token: token)
      end

      # The page URL without fragment and without an earlier recovery parameter, or nil when
      # it is not an https URL on one of `hosts`.
      def clean_page_url(page_url, hosts)
        uri = URI.parse(page_url.to_s.strip)
        return nil unless uri.is_a?(URI::HTTPS) && uri.host
        return nil unless hosts.map(&:downcase).include?(uri.host.downcase)

        params = URI.decode_www_form(uri.query.to_s).reject { |key, _| key == PARAM }
        uri.query = params.empty? ? nil : URI.encode_www_form(params)
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      # "brand.com", "https://brand.com/", "brand.com/path" -> "brand.com"
      def host_of(value)
        text = value.to_s.strip.downcase
        return nil if text.empty?

        text = text.sub(%r{\Ahttps?://}, "").split("/").first.to_s.split("?").first.to_s
        text.match?(/\A[a-z0-9]([a-z0-9.-]*[a-z0-9])?\z/) && text.include?(".") ? text : nil
      end
    end
  end
end

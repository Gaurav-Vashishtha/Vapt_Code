# frozen_string_literal: true

module CodForm
  # Refreshes `cod_form_shop_configs.allowed_origins` from the shop's Shopify domains (B.1, D.0.2).
  # The origin guard always accepts the myshopify domain and `shops.primary_domain`; this list
  # adds the other storefront hosts (market domains, www / apex variants).
  #
  # The GraphQL field cannot be checked against the schema dump in this mirror (F35): a parse or
  # query error keeps the stored list untouched.
  class DomainSyncService
    MAX_HOSTS = 50
    HOST_RE = /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+\z/.freeze

    class << self
      # => Array of hosts stored, or nil when Shopify could not be read.
      def call(shop)
        hosts = fetch_hosts(shop)
        return nil if hosts.nil?

        config = CodForm::ShopConfig.for(shop)
        list = clean(hosts, shopify_domain: shop.shopify_domain, primary_domain: shop.primary_domain)
        config.update_columns(allowed_origins: list, updated_at: Time.current) if list != config.allowed_origins
        list
      rescue StandardError => e
        Rails.logger.warn("[CodForm::DomainSyncService] shop_id=#{shop&.id} #{e.class}")
        nil
      end

      # Pure: lower-case hosts, without scheme / path, without the two hosts the guard already
      # accepts, de-duplicated, capped.
      def clean(hosts, shopify_domain:, primary_domain:)
        skip = [host_of(shopify_domain), host_of(primary_domain)].compact
        Array(hosts).map { |host| host_of(host) }.compact.uniq.reject { |host| skip.include?(host) }.first(MAX_HOSTS)
      end

      def host_of(value)
        host = value.to_s.strip.downcase.sub(%r{\Ahttps?://}, "").split("/").first.to_s.split(":").first.to_s
        host.match?(HOST_RE) ? host : nil
      end

      private

      def fetch_hosts(shop)
        shop.init_session
        client = ShopifyAPI::GraphQL.client
        query = client.parse <<-'GRAPHQL'
          query {
            shop {
              primaryDomain { host }
              domains { host }
            }
          }
        GRAPHQL
        data = client.query(query)&.data&.shop
        return nil unless data

        hosts = Array(data.domains).map(&:host)
        hosts << data.primary_domain&.host
        hosts.compact
      end
    end
  end
end

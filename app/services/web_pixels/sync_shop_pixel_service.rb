# frozen_string_literal: true

module WebPixels
  # Admin GraphQL webPixelCreate / webPixelUpdate — keeps app pixel settings in sync with Shopify.
  # Requires write_pixels + read_customer_events (see config/initializers/shopify_app.rb).
  # The settings hash must match extensions/cod-king-web-pixel/shopify.extension.toml exactly
  # or the mutation is rejected, so deploy the extension before shipping changes here.
  class SyncShopPixelService < ApplicationService
    QUERY_PIXEL_ID = <<~GRAPHQL
      query {
        webPixel {
          id
        }
      }
    GRAPHQL

    MUTATION_CREATE = <<~GRAPHQL
      mutation ($webPixel: WebPixelInput!) {
        webPixelCreate(webPixel: $webPixel) {
          userErrors {
            field
            message
            code
          }
          webPixel {
            id
            settings
          }
        }
      }
    GRAPHQL

    MUTATION_UPDATE = <<~GRAPHQL
      mutation ($id: ID!, $webPixel: WebPixelInput!) {
        webPixelUpdate(id: $id, webPixel: $webPixel) {
          userErrors {
            field
            message
            code
          }
          webPixel {
            id
            settings
          }
        }
      }
    GRAPHQL

    # Shopify rejects a blank value on any declared web pixel settings field, so unused
    # fields carry this sentinel and the pixel treats it as absent.
    UNSET = "-"

    def initialize(shop:)
      super()
      @shop = shop
    end

    def call
      if ENV.fetch("WEB_PIXEL_AUTO_ACTIVATE", nil).to_s == "false"
        Rails.logger.info("[WebPixels] skip shop=#{@shop.shopify_domain} reason=WEB_PIXEL_AUTO_ACTIVATE=false")
        return
      end
      if public_app_origin.blank?
        Rails.logger.warn("[WebPixels] skip shop=#{@shop.shopify_domain} reason=APP_HOST blank (set APP_HOST for metaEventsUrl)")
        return
      end

      @shop.with_shopify_session do
        client = ShopifyAPI::GraphQL.client
        settings = build_settings
        input = { settings: settings }

        existing_id = fetch_existing_pixel_id(client)
        query_def = client.parse(existing_id.present? ? MUTATION_UPDATE : MUTATION_CREATE)
        variables =
          if existing_id.present?
            { id: existing_id, webPixel: input }
          else
            { webPixel: input }
          end

        response = client.query(query_def, variables: variables)
        log_result(existing_id.present? ? :update : :create, response)
      end
    end

    private

    def public_app_origin
      host = ENV.fetch("APP_HOST", nil).to_s.strip
      return "" if host.blank?

      base = host.match?(%r{\Ahttps?://}) ? host : "https://#{host}"
      base.sub(%r{/+\z}, "")
    end

    def meta_events_active?
      @shop.setting&.meta_events_active? == true
    end

    def build_settings
      return disabled_settings unless meta_events_active?

      {
        metaEventsEnabled: "true",
        metaPixelId: present_or_unset(@shop.setting.pixel_id),
        metaEventsUrl: present_or_unset("#{public_app_origin}/events/meta"),
        metaEventsToken: present_or_unset(::MetaEvents::Token.for(@shop)),
        metaDebug: debug_flag,
        metaTestEventCode: present_or_unset(@shop.setting.pixel_test_event_id),
      }
    end

    def disabled_settings
      {
        metaEventsEnabled: "false",
        metaPixelId: UNSET,
        metaEventsUrl: UNSET,
        metaEventsToken: UNSET,
        metaDebug: debug_flag,
        metaTestEventCode: UNSET,
      }
    end

    # Reuses the shop's existing storefront debug switch so support can turn on the
    # pixel's console logging for one merchant without a deploy.
    def debug_flag
      (@shop.setting&.debug == true).to_s
    end

    def present_or_unset(value)
      value.to_s.strip.presence || UNSET
    end

    def fetch_existing_pixel_id(client)
      q = client.parse(QUERY_PIXEL_ID)
      res = client.query(q)
      res&.original_hash&.dig("data", "webPixel", "id").presence
    rescue StandardError => e
      Rails.logger.warn("[WebPixels] query webPixel failed shop=#{@shop.shopify_domain} #{e.class}: #{e.message}")
      nil
    end

    def log_result(action, response)
      hash = response&.original_hash || {}
      if hash["errors"].present?
        Rails.logger.warn(
          "[WebPixels] #{action} graphql errors shop=#{@shop.shopify_domain} #{hash['errors'].inspect}",
        )
        return
      end

      payload_key = action == :update ? "webPixelUpdate" : "webPixelCreate"
      payload = hash.dig("data", payload_key) || {}
      errors = payload["userErrors"] || []

      if errors.any?
        Rails.logger.warn(
          "[WebPixels] #{action} failed shop=#{@shop.shopify_domain} errors=#{errors.inspect}",
        )
      else
        Rails.logger.info(
          "[WebPixels] #{action} ok shop=#{@shop.shopify_domain} meta_events=#{meta_events_active?}",
        )
      end
    end
  end
end

# frozen_string_literal: true

module CodForm
  module Tracking
    # Sends one moment of one session to every matching server pixel (ARCHITECTURE.md I.3).
    # Each pixel is isolated: one failing vendor never stops the others, and nothing here
    # raises into the caller. Returns [{"key", "platform", outcome keys…}].
    class Dispatcher
      CLIENTS = {
        "meta" => MetaClient, "tiktok" => TiktokClient, "ga4" => Ga4Client,
        "google_ads" => GoogleAdsClient, "snapchat" => SnapchatClient, "pinterest" => PinterestClient
      }.freeze
      GOOGLE_ADS_SETTING_KEY = "google_ads:setting"
      SESSION_KEYS = %w[public_id client_id contact address tracking attribution quote_snapshot order_id
                        order_name order_total_cents currency country_code ip user_agent].freeze

      def self.call(session:, moment:, only: nil)
        new(session, moment, only).call
      end

      def self.pixel_key(pixel)
        "#{pixel['platform']}:#{pixel['pixel_id']}"
      end

      def initialize(session, moment, only)
        @session = session
        @moment = moment.to_s
        @only = only.to_s.empty? ? nil : only.to_s
        @shop = session.shop
      end

      def call
        return [] if @shop.nil? || !EventMap.moment?(@moment)
        return [] if @moment == EventMap::MOMENT_PURCHASE && @session.order_id.to_s.empty?

        event = EventBuilder.build(session: session_hash, moment: @moment, now: Time.current.to_i)
        event["page_url"] ||= storefront_url
        results = []

        pixels.each do |pixel|
          key = self.class.pixel_key(pixel)
          next if @only && @only != key

          results << run(key, pixel["platform"]) do
            next Http.skipped("no_consent") unless consent_for?(pixel["platform"], event)

            send_to(pixel, event)
          end
        end

        if @moment == EventMap::MOMENT_PURCHASE && (@only.nil? || @only == GOOGLE_ADS_SETTING_KEY)
          results << run(GOOGLE_ADS_SETTING_KEY, "google_ads") do
            next Http.skipped("no_consent") unless consent_for?("google_ads", event)

            GoogleAdsClient.send_purchase(session: @session, setting: @shop.setting, event: event)
          end
        end

        results
      end

      private

      def run(key, platform)
        outcome = yield
        outcome.merge("key" => key, "platform" => platform)
      rescue StandardError => e
        # Class name only: vendor error messages can echo request data.
        Http.failed(e.class.name, retryable: false).merge("key" => key, "platform" => platform)
      end

      def send_to(pixel, event)
        client = CLIENTS[pixel["platform"]]
        return Http.skipped("unknown_platform") if client.nil?

        client.send_event(pixel: pixel, event: event)
      end

      # G.8: with general.consent.respect_customer_privacy (default true) marketing pixels need
      # marketing consent and GA4 needs analytics consent.
      def consent_for?(platform, event)
        return true unless respect_privacy?

        consent = event["consent"] || {}
        platform == "ga4" ? consent["analytics"] != false : consent["marketing"] != false
      end

      def respect_privacy?
        return @respect_privacy if defined?(@respect_privacy)

        general = CodForm::ShopConfig.for(@shop).general
        consent = general.is_a?(Hash) && general["consent"].is_a?(Hash) ? general["consent"] : {}
        @respect_privacy = consent["respect_customer_privacy"] != false
      end

      def pixels
        lines = @session.quote_snapshot.is_a?(Hash) ? Array(@session.quote_snapshot["lines"]) : []
        lines = lines.select { |line| line.is_a?(Hash) }
        PixelResolver.server_pixels(
          @shop,
          product_ids: lines.map { |line| line["product_id"].to_s }.reject(&:empty?).uniq,
          collection_ids: lines.flat_map { |line| Array(line["collection_ids"]).map(&:to_s) }.uniq
        )
      end

      def storefront_url
        host = @shop.primary_domain.presence || @shop.shopify_domain
        host.present? ? "https://#{host}/" : nil
      end

      def session_hash
        @session.attributes.slice(*SESSION_KEYS)
      end
    end
  end
end

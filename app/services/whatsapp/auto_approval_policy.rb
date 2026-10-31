# frozen_string_literal: true

module Whatsapp
  # Decides whether a shop's request to send WhatsApp from COD King's default number is approved
  # without manual review: shops in a fast-track country (campaign markets, Egypt by default;
  # WHATSAPP_AUTO_APPROVE_COUNTRIES="EG,PK", or "none" to switch it off), or established stores.
  class AutoApprovalPolicy
    MIN_SHOP_AGE_DAYS = 60
    MIN_CUSTOMER_COUNT = 1000
    DEFAULT_AUTO_APPROVE_COUNTRIES = %w[EG].freeze

    def self.auto_approve_countries
      raw = ENV.fetch("WHATSAPP_AUTO_APPROVE_COUNTRIES", nil)
      return DEFAULT_AUTO_APPROVE_COUNTRIES if raw.nil?
      return [] if raw.strip.casecmp?("none")

      raw.split(",").map { |code| code.strip.upcase }.reject(&:empty?)
    end

    def initialize(shop)
      @shop = shop
    end

    def eligible?
      return false if @shop.blank?
      return true if fast_track_country?

      old_enough? && enough_customers?
    end

    def note
      return "Auto-approved: #{shop_country} store (fast-track country)" if fast_track_country?

      "Auto-approved: store is #{shop_age_days} days old with #{customer_count} customers"
    end

    private

    def shop_country
      @shop.country_code.to_s.strip.upcase
    end

    def fast_track_country?
      shop_country.present? && self.class.auto_approve_countries.include?(shop_country)
    end

    def old_enough?
      shop_age_days.present? && shop_age_days > MIN_SHOP_AGE_DAYS
    end

    def enough_customers?
      customer_count > MIN_CUSTOMER_COUNT
    end

    def shop_age_days
      return @shop_age_days if defined?(@shop_age_days)

      created_at = Time.zone.parse(@shop.shop_created_date.to_s)
      @shop_age_days = created_at && ((Time.current - created_at) / 1.day).floor
    rescue ArgumentError
      @shop_age_days = nil
    end

    # shops.customer_count is an install-time snapshot outside PH/IN (only those are
    # re-synced by CustomerCountSyncJob), so a below-threshold value is re-checked live.
    def customer_count
      @customer_count ||= begin
        stored = @shop.customer_count.to_i
        stored > MIN_CUSTOMER_COUNT ? stored : (live_customer_count || stored)
      end
    end

    def live_customer_count
      count = ShopifyServices::CustomerCountFetchService.call(@shop)
      return unless count.is_a?(Integer)

      @shop.update_column(:customer_count, count)
      count
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::AutoApprovalPolicy] #{@shop.shopify_domain}: #{e.class}: #{e.message}")
      nil
    end
  end
end

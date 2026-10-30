module ShopifyServices
  class ShortLinkService < ApplicationService
    MIN_LENGTH_TO_SHORTEN = 60

    def initialize(shop, url)
      @shop = shop
      @url = url.to_s
    end

    def call
      return @url if @shop.blank? || @url.blank?
      return @url if @url.length < MIN_LENGTH_TO_SHORTEN

      existing = reusable_redirect_path
      return existing if existing.present?

      short = ShopifyServices::CreateRedirectService.call(@shop, @url)
      usable?(short) ? short : @url
    rescue StandardError => e
      Rails.logger.warn("[short_link] falling back to full url shop=#{@shop&.shopify_domain} #{e.class}: #{e.message}")
      @url
    end

    private

    def reusable_redirect_path
      Redirect.where(shop_id: @shop.id, target: @url).order(id: :desc).first&.path
    rescue StandardError
      nil
    end

    def usable?(short)
      short.present? && short.to_s != "false" && short.to_s.start_with?("http")
    end
  end
end

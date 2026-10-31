module ShopifyServices
    class CreateRedirectService < ApplicationService
      attr_reader :shop, :target
  
      def initialize(shop,target)
        @shop = shop
        @target = target
      end
  
      # Shortening a link is a nicety; the message that carries it is not.
      # Every failure here — a blank target, a rejected access token (401), a
      # Shopify outage — falls back to the bitlink and ultimately to nil, and
      # the caller sends the long URL rather than losing the notification.
      def call
        return get_bitlink if @target.blank?

        domain = @shop.primary_domain.blank? ? @shop.shopify_domain : @shop.primary_domain
        return get_bitlink unless @shop.id > 630 #This is for shops older than current launch date.

        url_handle = (0...6).map { ('a'..'z').to_a[rand(26)] }.join
        @shop.init_session
        redirect = ShopifyAPI::Redirect.new(path: "/ck?q=#{url_handle}",target: @target)
        if !redirect.save # error from shopify
            return get_bitlink
        end
        db_redirect = Redirect.
                    new(path: "https://#{domain}#{redirect.path}",
                          shopify_redirect_id: redirect.id,
                          target: @target, 
                          shop_id: shop.id)
        if !db_redirect.save #Error in saving the data in DB   
            return get_bitlink
        end
        db_redirect.path
      rescue StandardError => e
        Rails.logger.warn("[create_redirect] shop=#{@shop&.shopify_domain} failed (#{e.class}: #{e.message}) — falling back")
        get_bitlink
      end

      def get_bitlink
        return nil if @target.blank?

        NetworkServices::CutlyLinkService.call(@target)
      rescue StandardError => e
        Rails.logger.warn("[create_redirect] shortener failed shop=#{@shop&.shopify_domain}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
  
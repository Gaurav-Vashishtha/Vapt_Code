module ShopifyServices
    class CreateRedirectService < ApplicationService
      attr_reader :shop, :target
  
      def initialize(shop,target)
        @shop = shop
        @target = target
      end
  
      def call
        if @target.blank? 
            throw 'Pass target to create redirect'
        end
        domain = @shop.primary_domain.blank? ? @shop.shopify_domain : @shop.primary_domain
        if @shop.id>630 #This is for shops older than current launch date.
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
          return db_redirect.path
        else
         return get_bitlink
        end
      end

      def get_bitlink
        return NetworkServices::CutlyLinkService.call(@target)
      end
    end
  end
  
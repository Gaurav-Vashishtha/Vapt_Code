class ApiController < ActionController::API
  include ActionController::Cookies
  include Pagy::Backend
  # before_action :set_sentry_context

  private

  
    def set_shop
      @shop = Shop.find_by(shopify_domain: current_shopify_domain)
      response.set_header('content-security-policy', "frame-ancestors https://#{@shop.shopify_domain} https://admin.shopify.com;")
    end

    def get_domain
      # current_shopify_domain in admin dashboard
      if defined?(current_shopify_domain) &&
         !current_shopify_domain.blank? &&
         !current_shopify_domain.nil?
            current_shopify_domain
      else
        # shop in redirect && domain in first script tag call.
        params[:shop] || params[:domain]
      end
    end

    # def set_sentry_context
    #   if not Rails.env.development?
    #     Sentry.configure_scope do |scope|
    #       scope.set_extras('shop.domain' => get_domain)
    #       scope.set_extras('request.url' => request.url)
    #       scope.set_extras('request.params' => params.to_unsafe_h)
    #     end
    #     Sentry.set_user(
    #       id: get_domain,
    #     )
    #   end
    # end
end

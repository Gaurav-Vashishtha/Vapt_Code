class ReferralAdmin::ApplicationController < ApplicationController
    before_action :authenticate_referral_admin!

    # When REFERRAL_APP_HOST is set in .env, all URLs in referral admin (links, forms, redirects)
    # use this host so you can run locally but point to prod backend.
    def default_url_options
      return super unless ENV["REFERRAL_APP_HOST"].to_s.present?
      host = ENV["REFERRAL_APP_HOST"].to_s.strip.sub(/\Ahttps?:\/\//, "")
      { host: host, protocol: "https" }
    end

    private

    def authenticate_referral_admin!
      # Implement your referral admin authentication
      unless current_referral_admin
        redirect_to referral_login_path # Update this to your admin login path
      end
    end
    
    def current_referral_admin
      # Implement your referral admin session logic
      @current_referral_admin ||= session[:referral_admin_user] || 'admin'
    end
  end
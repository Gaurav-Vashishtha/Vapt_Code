class ReferralAdmin::ShopsController < ApplicationController
    # Comment out or fix the authentication
    # before_action :require_admin_login
    
    before_action :set_shop, only: [:show, :approve, :reject]
    
    def index
      @pending_shops = ReferralShop.pending_approval.includes(:referral_partner)
      @approved_shops = ReferralShop.approved.includes(:referral_partner).limit(20)
      @rejected_shops = ReferralShop.where.not(rejection_reason: nil).includes(:referral_partner).limit(20)
    end
    
    def show
      # Show shop details for admin review
    end
    
    def approve
      # Replace current_admin_user.name with a simple string or actual admin name
      @shop.approve!('Admin User')  # or use a hardcoded name like 'System Admin'
      redirect_to referral_admin_shops_path, notice: "Shop #{@shop.shop_domain} approved successfully!"
    end
    
    def reject
      reason = params[:reason].presence || "No reason provided"
      @shop.reject!(reason, 'Admin User')  # or use a hardcoded name like 'System Admin'
      redirect_to referral_admin_shops_path, notice: "Shop #{@shop.shop_domain} rejected."
    end
    
    private
    
    def set_shop
      @shop = ReferralShop.find(params[:id])
    end
  end
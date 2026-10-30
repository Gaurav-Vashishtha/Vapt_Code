class ReferralShopsController < ApplicationController
    before_action :require_referral_partner_login
    before_action :set_shop, only: [:show, :edit, :update, :destroy]
    
    def index
      @shops = current_referral_partner.referral_shops.includes(:referral_earnings)
      @approved_shops = @shops.approved
      @pending_shops = @shops.pending_approval
    end
    
    def show
      # Only show earnings for approved shops
      if @shop.approved?
        @earnings_30_days = @shop.referral_earnings.for_period(30.days.ago.to_date, Date.current)
        @earnings_all_time = @shop.referral_earnings.all
        @revenue_breakdown_30_days = @shop.revenue_breakdown(:last_30_days)
        @revenue_breakdown_all_time = @shop.revenue_breakdown(:all_time)
      else
        @earnings_30_days = []
        @earnings_all_time = []
        @revenue_breakdown_30_days = {}
        @revenue_breakdown_all_time = {}
      end
    end
    
    def new
      @shop = current_referral_partner.referral_shops.build
    end
    
    def create
      @shop = current_referral_partner.referral_shops.build(shop_params)
      # New shops start as unapproved
      @shop.approved = false
      
      if @shop.save
        redirect_to referral_shop_path(@shop), notice: 'Shop submitted for approval. It will be reviewed by our admin team.'
      else
        render :new
      end
    end
    
    def edit
    end
    
    def update
      if @shop.update(shop_params.except(:shop_domain)) # Don't allow domain changes after creation
        redirect_to referral_shop_path(@shop), notice: 'Shop was successfully updated.'
      else
        render :edit
      end
    end
    
    def destroy
      @shop.destroy
      redirect_to referral_shops_path, notice: 'Shop was successfully removed.'
    end
    
    private
    
    def set_shop
      @shop = current_referral_partner.referral_shops.find(params[:id])
    end
    
    def shop_params
      params.require(:referral_shop).permit(:shop_domain, :notes, :active)
    end
  end
  
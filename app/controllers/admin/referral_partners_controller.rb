class Admin::ReferralPartnersController < ApplicationController
    # before_action :require_admin_login # Assuming you have admin authentication
    before_action :set_partner, only: [:show, :edit, :update, :destroy, :toggle_active]
    
    def index
      @partners = ReferralPartner.includes(:referral_shops, :referral_earnings)
                                 .order(:name)
    end
    
    def show
      @total_shops = @partner.referral_shops.count
      @active_shops = @partner.referral_shops.active.count
      @total_commission = @partner.total_commission_earned(:all_time)
      @commission_30_days = @partner.total_commission_earned(:last_30_days)
    end
    
    def new
      @partner = ReferralPartner.new
    end
    
    def create
      @partner = ReferralPartner.new(partner_params)
      
      if @partner.save
        redirect_to admin_referral_partner_path(@partner), notice: 'Partner created successfully.'
      else
        render :new
      end
    end
    
    def edit
    end
    
    def update
      if @partner.update(partner_params)
        redirect_to admin_referral_partner_path(@partner), notice: 'Partner updated successfully.'
      else
        render :edit
      end
    end
    
    def destroy
      @partner.destroy
      redirect_to admin_referral_partners_path, notice: 'Partner deleted successfully.'
    end
    
    def toggle_active
      @partner.update!(active: !@partner.active)
      redirect_to admin_referral_partners_path, 
                  notice: "Partner #{@partner.active? ? 'activated' : 'deactivated'} successfully."
    end
    
    private
    
    def set_partner
      @partner = ReferralPartner.find(params[:id])
    end
    
    def partner_params
      params.require(:referral_partner).permit(
        :name, :email, :password, :password_confirmation,
        :subscription_commission_rate, :usage_commission_rate, :onetime_commission_rate,
        :active, :notes
      )
    end
  end
  
class ReferralAccountController < ApplicationController
    before_action :require_referral_partner_login
    before_action :set_partner
    
    def show
      # Show account details and settings
    end
    
    def edit_password
      # Form to change password
    end
    
    def update_password
      if @partner.authenticate(params[:current_password])
        if @partner.update(password_params)
          redirect_to referral_account_path, notice: 'Password updated successfully!'
        else
          flash.now[:alert] = 'Password confirmation does not match'
          render :edit_password
        end
      else
        flash.now[:alert] = 'Current password is incorrect'
        render :edit_password
      end
    end
    
    def edit_account_details
      # Form to add/edit bank or PayPal details
    end
    
    def update_account_details
      if @partner.update(account_params)
        redirect_to referral_account_path, notice: 'Account details updated successfully!'
      else
        render :edit_account_details
      end
    end
    
    private
    
    def set_partner
      @partner = current_referral_partner
    end
    
    def password_params
      params.require(:referral_partner).permit(:password, :password_confirmation)
    end
    
    def account_params
      params.require(:referral_partner).permit(
        :account_type, :bank_account_number, :bank_ifsc_code, 
        :bank_account_name, :bank_name, :paypal_email
      )
    end
  end
class ReferralSessionsController < ApplicationController
    def new
      redirect_to referral_dashboard_path if referral_partner_signed_in?
    end
    
    def create
      partner = ReferralPartner.find_by(email: params[:email])
      
      if partner&.authenticate(params[:password])
        session[:referral_partner_id] = partner.id
        redirect_to referral_dashboard_path, notice: 'Successfully logged in!'
      else
        flash.now[:alert] = 'Invalid email or password'
        render :new
      end
    end
    
    def destroy
      session[:referral_partner_id] = nil
      redirect_to referral_login_path, notice: 'Successfully logged out!'
    end
  end
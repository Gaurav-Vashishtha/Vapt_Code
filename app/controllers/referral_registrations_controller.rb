class ReferralRegistrationsController < ApplicationController
  DEFAULT_SUBSCRIPTION_RATE = 20
  DEFAULT_USAGE_RATE = 10
  DEFAULT_ONETIME_RATE = 10

  def new
    @partner = ReferralPartner.new(
      subscription_commission_rate: DEFAULT_SUBSCRIPTION_RATE,
      usage_commission_rate: DEFAULT_USAGE_RATE,
      onetime_commission_rate: DEFAULT_ONETIME_RATE
    )
    redirect_to referral_dashboard_path if referral_partner_signed_in?
  end

  def create
    @partner = ReferralPartner.new(partner_attributes)
    @partner.subscription_commission_rate = DEFAULT_SUBSCRIPTION_RATE
    @partner.usage_commission_rate = DEFAULT_USAGE_RATE
    @partner.onetime_commission_rate = DEFAULT_ONETIME_RATE
    @partner.active = true
    @partner.account_verified = false

    plain_password = params.dig(:referral_partner, :password)

    if @partner.save
      begin
        WelcomeMailer.referral_partner_signup(@partner.id, plain_password).deliver_later
      rescue => e
        Rails.logger.error "[ReferralRegistrationsController] welcome email failed: #{e.message}"
      end

      begin
        WelcomeMailer.referral_partner_created_admin_notification(@partner.id).deliver_later
      rescue => e
        Rails.logger.error "[ReferralRegistrationsController] admin notify failed: #{e.message}"
      end

      redirect_to referral_login_path,
                  notice: "Account created. Check your email for your referral code and login details."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def partner_attributes
    params.require(:referral_partner).permit(
      :name,
      :email,
      :phone,
      :password,
      :password_confirmation
    )
  end
end

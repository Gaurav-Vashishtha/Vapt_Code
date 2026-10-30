class ReferralPayoutsController < ApplicationController
    before_action :authenticate_referral_partner!
    before_action :set_payout, only: [:show]
  
    def index
      @partner = current_referral_partner
      @payouts = @partner.payouts.order(created_at: :desc).limit(20)
      
      @payout_summary = {
        total_paid: @partner.total_paid_earnings,
        total_pending: @partner.total_unpaid_earnings,
        last_payout: @partner.last_payout,
        next_payout_eligible: calculate_next_payout_eligibility
      }
      
      @monthly_payouts = @partner.payouts
                                .completed
                                .group_by { |p| p.payout_date.beginning_of_month }
                                .transform_values { |payouts| payouts.sum(&:total_amount) }
                                .sort.reverse
                                .first(12)
    end
  
    def show
      @payout = @payout
      @earnings = @payout.referral_earnings
                        .includes(:referral_shop)
                        .order(:earning_date)
      
      @earnings_breakdown = @earnings.group(:transaction_type).sum(:commission_amount)
      @shops_breakdown = @earnings.joins(:referral_shop)
                                 .group('referral_shops.shop_domain')
                                 .sum(:commission_amount)
    end
  
    private
  
    def set_payout
      @payout = current_referral_partner.payouts.find(params[:id])
    end
  
    def calculate_next_payout_eligibility
      return nil unless current_referral_partner.account_verified?
      
      unpaid_amount = current_referral_partner.total_unpaid_earnings
      minimum_payout = 50.0
      
      {
        eligible: unpaid_amount >= minimum_payout,
        amount: unpaid_amount,
        minimum_required: minimum_payout,
        estimated_payout_date: unpaid_amount >= minimum_payout ? calculate_next_payout_date : nil
      }
    end
  
    def calculate_next_payout_date
      today = Date.current
      if today.day <= 15
        Date.new(today.year, today.month, 15)
      else
        next_month = today.next_month
        Date.new(next_month.year, next_month.month, 15)
      end
    end
  
    def authenticate_referral_partner!
      redirect_to referral_login_path unless current_referral_partner
    end
  
    def current_referral_partner
      @current_referral_partner ||= ReferralPartner.find(session[:referral_partner_id]) if session[:referral_partner_id]
    end
  end
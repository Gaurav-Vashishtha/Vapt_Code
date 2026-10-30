# REPLACE YOUR app/controllers/referral_earnings_controller.rb with this fixed version:

class ReferralEarningsController < ApplicationController
    before_action :authenticate_referral_partner!
  
    def index
      @partner = current_referral_partner
      @earnings = @partner.referral_earnings
                         .includes(:referral_shop)
                         .order(earning_date: :desc)
                         .limit(50)
      
      # Apply filters
      @earnings = apply_filters(@earnings)
      
      @earnings_summary = {
        total_unpaid: @partner.referral_earnings.where(payout_status: 'unpaid').sum(:commission_amount),
        total_paid: @partner.referral_earnings.where(payout_status: 'paid').sum(:commission_amount),
        this_month: @partner.referral_earnings
                           .where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
                           .sum(:commission_amount),
        last_month: @partner.referral_earnings
                           .where(earning_date: 1.month.ago.beginning_of_month..1.month.ago.end_of_month)
                           .sum(:commission_amount)
      }
      
      # Fixed: Use separate queries instead of grouped queries that cause PostgreSQL issues
      @breakdown_by_type = {
        'subscription' => @earnings.where(transaction_type: 'subscription').sum(:commission_amount),
        'usage' => @earnings.where(transaction_type: 'usage').sum(:commission_amount),
        'onetime' => @earnings.where(transaction_type: 'onetime').sum(:commission_amount)
      }
      
      # Fixed: Calculate shop breakdown without complex GROUP BY
      @breakdown_by_shop = {}
      @earnings.includes(:referral_shop).each do |earning|
        shop_domain = earning.referral_shop.shop_domain
        @breakdown_by_shop[shop_domain] ||= 0
        @breakdown_by_shop[shop_domain] += earning.commission_amount
      end
    end
  
    def summary
      @partner = current_referral_partner
      
      # Simplified monthly earnings calculation
      @monthly_earnings = {}
      @partner.referral_earnings.each do |earning|
        month_key = earning.earning_date.strftime('%Y-%m')
        @monthly_earnings[month_key] ||= 0
        @monthly_earnings[month_key] += earning.commission_amount
      end
      
      # Daily earnings for last 30 days
      @daily_earnings_30d = {}
      @partner.referral_earnings
             .where(earning_date: 30.days.ago..Date.current)
             .each do |earning|
        @daily_earnings_30d[earning.earning_date] ||= 0
        @daily_earnings_30d[earning.earning_date] += earning.commission_amount
      end
      
      # Type breakdown
      @type_breakdown = {
        'subscription' => @partner.referral_earnings.where(transaction_type: 'subscription').sum(:commission_amount),
        'usage' => @partner.referral_earnings.where(transaction_type: 'usage').sum(:commission_amount),
        'onetime' => @partner.referral_earnings.where(transaction_type: 'onetime').sum(:commission_amount)
      }
      
      respond_to do |format|
        format.json do
          render json: {
            monthly_earnings: @monthly_earnings,
            daily_earnings_30d: @daily_earnings_30d,
            type_breakdown: @type_breakdown
          }
        end
        format.html
      end
    end
  
    private
  
    def apply_filters(earnings)
      earnings = earnings.where(payout_status: params[:status]) if params[:status].present?
      earnings = earnings.where(transaction_type: params[:type]) if params[:type].present?
      
      if params[:from_date].present? && params[:to_date].present?
        earnings = earnings.where(earning_date: params[:from_date]..params[:to_date])
      end
      
      earnings
    end
  
    def authenticate_referral_partner!
      redirect_to referral_login_path unless current_referral_partner
    end
  
    def current_referral_partner
      @current_referral_partner ||= ReferralPartner.find(session[:referral_partner_id]) if session[:referral_partner_id]
    end
  end
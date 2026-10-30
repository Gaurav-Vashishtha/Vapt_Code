class ReferralAdmin::EarningsController < ReferralAdmin::ApplicationController
    def index
      @earnings = ReferralEarning.includes(:referral_partner, :referral_shop, :payouts)
                                .order(earning_date: :desc)
                                .limit(100)
      
      @earnings = apply_filters(@earnings)
      
      @summary = {
        total_unpaid: @earnings.unpaid.sum(:commission_amount),
        total_paid: @earnings.paid.sum(:commission_amount),
        unpaid_count: @earnings.unpaid.count,
        paid_count: @earnings.paid.count
      }
    end
  
    def show
      @earning = ReferralEarning.find(params[:id])
    end
  
    def unpaid_summary
      @unpaid_by_partner = ReferralEarning.unpaid
                                         .joins(:referral_partner)
                                         .group('referral_partners.name', 'referral_partners.id')
                                         .sum(:commission_amount)
      
      @unpaid_by_type = ReferralEarning.unpaid
                                      .group(:transaction_type)
                                      .sum(:commission_amount)
      
      respond_to do |format|
        format.json do
          render json: {
            by_partner: @unpaid_by_partner,
            by_type: @unpaid_by_type,
            total: ReferralEarning.unpaid.sum(:commission_amount)
          }
        end
        format.html
      end
    end
  
    private
  
    def apply_filters(earnings)
      earnings = earnings.where(payout_status: params[:payout_status]) if params[:payout_status].present?
      earnings = earnings.where(transaction_type: params[:transaction_type]) if params[:transaction_type].present?
      earnings = earnings.where(referral_partner_id: params[:partner_id]) if params[:partner_id].present?
      
      if params[:from_date].present? && params[:to_date].present?
        earnings = earnings.where(earning_date: params[:from_date]..params[:to_date])
      end
      
      earnings
    end
  end

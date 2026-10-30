class ReferralDashboardController < ApplicationController
  before_action :require_referral_partner_login
  before_action :allow_iframe_embedding
  
  def index
    @partner = current_referral_partner
    @shops = @partner.referral_shops.active.includes(:referral_earnings)
    @approved_shops = @partner.referral_shops.approved_and_active.includes(:referral_earnings)
    
    # Calculate summary statistics (only for approved shops)
    @total_shops = @shops.count
    @approved_shops_count = @approved_shops.count
    @pending_approval_count = @partner.pending_approval_shops_count
    @total_commission_30_days = @partner.total_commission_earned(:last_30_days)
    @total_commission_all_time = @partner.total_commission_earned(:all_time)
    @commission_breakdown_30_days = @partner.commission_breakdown(:last_30_days).compact
    
    # Recent earnings (only from approved shops)
    @recent_earnings = @partner.referral_earnings
                              .joins(:referral_shop)
                              .where(referral_shops: { approved: true })
                              .includes(:referral_shop)
                              .recent
                              .limit(10)
    
    # Revenue sync status
    @last_sync = @partner.referral_earnings.maximum(:processed_at)
    
    # Account setup reminder
    @needs_account_setup = !@partner.has_account_details?

    # NEW: Payout-related data
    @payout_summary = {
      total_unpaid: @partner.total_unpaid_earnings,
      total_paid: @partner.total_paid_earnings,
      last_payout: @partner.last_payout,
      next_payout_eligible: calculate_next_payout_eligibility
    }
    
    # Update last sync to use the new field
    @last_sync = @partner.referral_shops.maximum(:last_sync_date) || @partner.referral_earnings.maximum(:processed_at)
  end
  
  def sync_earnings
    sync_service = ReferralRevenueSyncService.new(
      ENV['SHOPIFY_ORGANIZATION_ID'], 
      ENV['SHOPIFY_PARTNER_ACCESS_TOKEN']
    )
    # Only sync approved shops
    @sync_results = sync_service.sync_partner_earnings(current_referral_partner, approved_only: true)
    
    successful_syncs = @sync_results.count { |r| r[:success] }
    total_syncs = @sync_results.count
    
    if successful_syncs == total_syncs
      flash[:notice] = "Successfully synced earnings for all #{total_syncs} approved shops"
    elsif successful_syncs > 0
      flash[:notice] = "Synced #{successful_syncs} out of #{total_syncs} approved shops"
      flash[:alert] = "Some shops failed to sync. Check the details below."
    else
      flash[:alert] = "Failed to sync earnings for approved shops"
    end
    
    render :sync_results
  end

  private

  def allow_iframe_embedding
    response.headers.delete('X-Frame-Options')
    response.headers.delete('Content-Security-Policy')
    response.headers['X-Frame-Options'] = 'ALLOWALL'
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
end
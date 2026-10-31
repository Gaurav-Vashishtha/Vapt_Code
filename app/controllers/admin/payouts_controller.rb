# app/controllers/admin/payouts_controller.rb
class Admin::PayoutsController < ApplicationController
    before_action :authenticate_admin!
    before_action :set_payout, only: [:show, :process_payout, :cancel]
    before_action :set_referral_partner, only: [:partner_summary, :create_partner_payout]
  
    def index
      @payouts = Payout.includes(:referral_partner)
                      .order(created_at: :desc)
                      .page(params[:page])
                      .per(20)
      
      # Apply filters
      @payouts = @payouts.where(status: params[:status]) if params[:status].present?
      @payouts = @payouts.by_partner(params[:partner_id]) if params[:partner_id].present?
      @payouts = @payouts.by_date_range(params[:from_date], params[:to_date]) if params[:from_date].present? && params[:to_date].present?
  
      @summary = {
        total_pending: Payout.pending.sum(:total_amount),
        total_completed: Payout.completed.sum(:total_amount),
        pending_count: Payout.pending.count,
        completed_count: Payout.completed.count
      }
    end
  
    def show
      @earnings = @payout.referral_earnings
                        .includes(:referral_shop)
                        .order(:earning_date)
    end
  
    def new
      @partners_with_pending = ReferralPartner.active
                                            .joins(:referral_earnings)
                                            .where(referral_earnings: { payout_status: 'unpaid' })
                                            .distinct
                                            .order(:name)
    end
  
    def partner_summary
      payout_service = PayoutService.new(current_admin_user)
      @summary = payout_service.get_pending_payout_summary(@partner, params[:to_date]&.to_date)
      
      if @summary.nil?
        redirect_to new_admin_payout_path, alert: "No pending earnings found for this partner"
        return
      end
  
      render json: @summary
    end
  
    def create_partner_payout
      payout_service = PayoutService.new(current_admin_user)
      
      begin
        @payout = payout_service.create_payout(@partner, payout_params)
        
        if @payout.persisted?
          redirect_to admin_payout_path(@payout), notice: "Payout created successfully"
        else
          redirect_to new_admin_payout_path, alert: "Failed to create payout: #{@payout.errors.full_messages.join(', ')}"
        end
      rescue PayoutService::PayoutError => e
        redirect_to new_admin_payout_path, alert: e.message
      end
    end
  
    def bulk_create
      partner_ids = params[:partner_ids]&.reject(&:blank?)
      
      if partner_ids.blank?
        redirect_to new_admin_payout_path, alert: "Please select at least one partner"
        return
      end
  
      payout_service = PayoutService.new(current_admin_user)
      results = payout_service.bulk_create_payouts(partner_ids, bulk_payout_params)
      
      successful_count = results.count { |r| r[:success] }
      total_amount = results.select { |r| r[:success] }.sum { |r| r[:amount] }
      
      if successful_count > 0
        flash[:notice] = "Successfully created #{successful_count} payouts totaling $#{total_amount}"
      end
      
      if results.any? { |r| !r[:success] }
        failed_partners = results.reject { |r| r[:success] }.map { |r| "#{r[:partner].name}: #{r[:error]}" }
        flash[:alert] = "Some payouts failed: #{failed_partners.join('; ')}"
      end
      
      redirect_to admin_payouts_path
    end
  
    def process_payout
      payout_service = PayoutService.new(current_admin_user)
      
      if payout_service.process_payout(@payout)
        redirect_to admin_payout_path(@payout), notice: "Payout processed successfully"
      else
        redirect_to admin_payout_path(@payout), alert: "Failed to process payout: #{@payout.notes}"
      end
    end
  
    def cancel
      if @payout.status == 'pending'
        @payout.update!(status: 'cancelled', notes: params[:cancellation_reason])
        
        # Revert earnings back to unpaid
        @payout.referral_earnings.update_all(payout_status: 'unpaid')
        
        redirect_to admin_payout_path(@payout), notice: "Payout cancelled successfully"
      else
        redirect_to admin_payout_path(@payout), alert: "Cannot cancel payout in #{@payout.status} status"
      end
    end
  
    def export
      @payouts = Payout.includes(:referral_partner, :referral_earnings)
      
      # Apply same filters as index
      @payouts = @payouts.where(status: params[:status]) if params[:status].present?
      @payouts = @payouts.by_partner(params[:partner_id]) if params[:partner_id].present?
      @payouts = @payouts.by_date_range(params[:from_date], params[:to_date]) if params[:from_date].present? && params[:to_date].present?
      
      respond_to do |format|
        format.csv do
          send_data generate_csv(@payouts), filename: "payouts_#{Date.current}.csv"
        end
      end
    end
  
    private
  
    def set_payout
      @payout = Payout.find(params[:id])
    end
  
    def set_referral_partner
      @partner = ReferralPartner.find(params[:partner_id] || params[:referral_partner_id])
    end
  
    def payout_params
      params.require(:payout).permit(
        :earnings_from_date, :earnings_to_date, :payout_date, :notes
      )
    end
  
    def bulk_payout_params
      params.permit(:earnings_to_date, :payout_date, :notes)
    end
  
    def generate_csv(payouts)
      CSV.generate(headers: true) do |csv|
        csv << [
          'Payout ID', 'Partner Name', 'Partner Email', 'Amount', 'Currency',
          'Status', 'Payment Method', 'Payout Date', 'Earnings Period',
          'Transaction Reference', 'Created At', 'Completed At'
        ]
        
        payouts.each do |payout|
          csv << [
            payout.id,
            payout.referral_partner.name,
            payout.referral_partner.email,
            payout.total_amount,
            payout.currency,
            payout.status.humanize,
            payout.payment_method.humanize,
            payout.payout_date,
            "#{payout.earnings_from_date} to #{payout.earnings_to_date}",
            payout.transaction_reference,
            payout.created_at.strftime('%Y-%m-%d %H:%M'),
            payout.completed_at&.strftime('%Y-%m-%d %H:%M')
          ]
        end
      end
    end
  end
  
  # app/controllers/admin/referral_sync_controller.rb
  class Admin::ReferralSyncController < ApplicationController
    before_action :authenticate_admin!
  
    def index
      @partners = ReferralPartner.active.includes(:referral_shops, :referral_earnings)
      @sync_stats = {
        total_partners: @partners.count,
        shops_needing_historical_sync: ReferralShop.needs_historical_sync.count,
        total_unpaid_earnings: ReferralEarning.unpaid.sum(:commission_amount),
        last_sync_jobs: recent_sync_jobs
      }
    end
  
    def sync_partner
      partner = ReferralPartner.find(params[:id])
      
      begin
        sync_service = ReferralRevenueSyncService.new(
          ENV.fetch("SHOPIFY_ORGANIZATION_ID", nil), 
          ENV.fetch("SHOPIFY_PARTNER_ACCESS_TOKEN", nil)
        )
        
        include_historical = params[:include_historical] == 'true'
        results = sync_service.sync_partner_earnings(partner, approved_only: true, include_historical: include_historical)
        
        successful_syncs = results.count { |r| r[:success] }
        total_commission = results.sum { |r| r[:total_commission] || 0 }
        
        flash[:notice] = "Synced #{successful_syncs}/#{results.count} shops. Total new commission: $#{total_commission}"
        
        if results.any? { |r| !r[:success] }
          failed_shops = results.reject { |r| r[:success] }.map { |r| "#{r[:shop].shop_domain}: #{r[:error]}" }
          flash[:alert] = "Some syncs failed: #{failed_shops.join('; ')}"
        end
        
      rescue => e
        flash[:alert] = "Sync failed: #{e.message}"
      end
      
      redirect_to admin_referral_sync_index_path
    end
  
    def sync_all_historical
      begin
        HistoricalSyncJob.perform_later
        flash[:notice] = "Historical sync job started. This may take several minutes."
      rescue => e
        flash[:alert] = "Failed to start historical sync: #{e.message}"
      end
      
      redirect_to admin_referral_sync_index_path
    end
  
    def sync_all_current
      begin
        CurrentSyncJob.perform_later
        flash[:notice] = "Current sync job started for all partners."
      rescue => e
        flash[:alert] = "Failed to start sync: #{e.message}"
      end
      
      redirect_to admin_referral_sync_index_path
    end
  
    private
  
    def recent_sync_jobs
      # Assuming you're using Sidekiq for job tracking
      SidekiqJob.where(class_name: ['HistoricalSyncJob', 'CurrentSyncJob'])
               .order(created_at: :desc)
               .limit(10)
    end
  end
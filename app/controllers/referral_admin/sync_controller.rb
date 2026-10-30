class ReferralAdmin::SyncController < ReferralAdmin::ApplicationController
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
          ENV['SHOPIFY_ORGANIZATION_ID'], 
          ENV['SHOPIFY_PARTNER_ACCESS_TOKEN']
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
      
      redirect_to referral_admin_sync_index_path
    end
  
    def sync_all_historical
      begin
        HistoricalSyncJob.perform_later
        flash[:notice] = "Historical sync job started. This may take several minutes."
      rescue => e
        flash[:alert] = "Failed to start historical sync: #{e.message}"
      end
      
      redirect_to referral_admin_sync_index_path
    end
  
    def sync_all_current
      begin
        CurrentSyncJob.perform_later
        flash[:notice] = "Current sync job started for all partners."
      rescue => e
        flash[:alert] = "Failed to start sync: #{e.message}"
      end
      
      redirect_to referral_admin_sync_index_path
    end
  
    def sync_status
      recent_jobs = SidekiqJob.where(class_name: ['HistoricalSyncJob', 'CurrentSyncJob'])
                             .order(created_at: :desc)
                             .limit(5)
      
      render json: {
        jobs: recent_jobs.map do |job|
          {
            id: job.id,
            class_name: job.class_name,
            status: job.status,
            started_at: job.started_at,
            finished_at: job.finished_at,
            result: job.result
          }
        end
      }
    end
  
    private
  
    def recent_sync_jobs
      SidekiqJob.where(class_name: ['HistoricalSyncJob', 'CurrentSyncJob', 'ScheduledSyncJob'])
               .order(created_at: :desc)
               .limit(10)
    end
  end
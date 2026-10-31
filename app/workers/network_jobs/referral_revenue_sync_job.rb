# app/workers/network_jobs/referral_revenue_sync_job.rb

# NetworkJobs::ReferralRevenueSyncJob.perform_async
# NetworkJobs::ReferralRevenueSyncJob.perform_async(true) # with historical sync
module NetworkJobs
    class ReferralRevenueSyncJob < ApplicationJob
      sidekiq_options queue: 'administration', retry: 2
      
      def perform(include_historical: false)
        Rails.logger.info "Starting referral revenue sync job (include_historical: #{include_historical})"
        
        begin
          # Get organization_id and partner_access_token from environment or settings
          organization_id = ENV.fetch("SHOPIFY_ORGANIZATION_ID", nil)
          partner_access_token = ENV.fetch("SHOPIFY_PARTNER_ACCESS_TOKEN", nil)
          
          if organization_id.blank? || partner_access_token.blank?
            error_msg = "Missing required environment variables: SHOPIFY_PARTNER_ORGANIZATION_ID or SHOPIFY_PARTNER_ACCESS_TOKEN"
            Rails.logger.error error_msg
            SlackNotifyJob.perform_async(
              ":warning: Referral Revenue Sync *Failed* (#{Rails.env})\n*Error*: #{error_msg}"
            )
            return
          end
          
          # Initialize the service
          sync_service = ReferralRevenueSyncService.new(organization_id, partner_access_token)
          
          # Sync all partners
          results = sync_service.sync_all_partners(include_historical: include_historical)
          
          # Process results and generate summary
          total_partners = results.count
          successful_partners = results.count { |r| r[:results].all? { |shop_result| shop_result[:success] } }
          failed_partners = total_partners - successful_partners
          
          total_shops_synced = results.sum { |r| r[:results].count }
          successful_shops = results.sum { |r| r[:results].count { |shop_result| shop_result[:success] } }
          failed_shops = total_shops_synced - successful_shops
          
          total_commission = results.sum do |r|
            r[:results].sum { |shop_result| shop_result[:total_commission] || 0 }
          end
          
          # Log summary
          Rails.logger.info "Referral revenue sync completed:"
          Rails.logger.info "  Partners: #{successful_partners}/#{total_partners} successful"
          Rails.logger.info "  Shops: #{successful_shops}/#{total_shops_synced} successful"
          Rails.logger.info "  Total commission calculated: $#{total_commission}"
          
          # Send Slack notification for summary
          slack_message = if failed_partners > 0 || failed_shops > 0
            ":warning: Referral Revenue Sync *Completed with Errors* (#{Rails.env})\n" \
            "*Partners*: #{successful_partners}/#{total_partners} successful\n" \
            "*Shops*: #{successful_shops}/#{total_shops_synced} successful\n" \
            "*Total Commission*: $#{total_commission}\n" \
            "*Historical Sync*: #{include_historical ? 'Yes' : 'No'}"
          else
            ":white_check_mark: Referral Revenue Sync *Successful* (#{Rails.env})\n" \
            "*Partners*: #{total_partners} synced\n" \
            "*Shops*: #{total_shops_synced} synced\n" \
            "*Total Commission*: $#{total_commission}\n" \
            "*Historical Sync*: #{include_historical ? 'Yes' : 'No'}"
          end
          
          SlackNotifyJob.perform_async(slack_message)
          
          # Log individual failures for debugging
          results.each do |partner_result|
            partner = partner_result[:partner]
            partner_result[:results].each do |shop_result|
              next if shop_result[:success]
              
              Rails.logger.error "Failed to sync shop #{shop_result[:shop]&.shop_domain} for partner #{partner.name}: #{shop_result[:error]}"
            end
          end
          
        rescue StandardError => e
          error_msg = "Referral revenue sync job failed: #{e.message}"
          Rails.logger.error error_msg
          Rails.logger.error e.backtrace.join("\n")
          
          SlackNotifyJob.perform_async(
            ":rage: Referral Revenue Sync *Critical Error* (#{Rails.env})\n" \
            "*Error*: #{e.message}\n" \
            "*Historical Sync*: #{include_historical ? 'Yes' : 'No'}"
          )
          
          raise e # Re-raise to trigger Sidekiq retry mechanism
        end
      end
    end
  end
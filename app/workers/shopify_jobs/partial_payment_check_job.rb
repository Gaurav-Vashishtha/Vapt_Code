module ShopifyJobs
  class PartialPaymentCheckJob < ApplicationJob

    # ShopifyJobs::PartialPaymentCheckJob.perform_async
    
    LOOK_BACK_DAYS = 2
    # In-Progress / step-marker orders untouched this long are treated as crashed runs and retried
    STALE_AFTER = 10.minutes
    
    def perform
      puts 'PartialPaymentCheckJob job started'
      scanned_orders = 0 
      failed_orders = 0 
      success_orders = 0
      success_order_ids = []
      failed_order_ids = []
      
      order_confirmations = OrderConfirmation.where.not(partial_payment_variants: [nil, '']).
        where('created_at > ?', Time.now - LOOK_BACK_DAYS.days).
        where.not(status: ['COD-Partial-Payment-Received', 'COD-Prepaid', 'Partial-Payment-Retry-Failed', 'Partial-Payment-Order-Skipped']).
        # Step markers whose retry already failed wait for a manual retry
        where.not('status LIKE ?', "%#{ShopifyServices::PartialOrderEditService::Bundle::RETRY_FAILED_SUFFIX}").
        # In-Progress / step markers touched in the last STALE_AFTER likely have a run still going
        where.not('(status = ? OR status LIKE ?) AND updated_at > ?',
                  'Partial-Payment-In-Progress', 'COD-Partial-Payment-Received-%', STALE_AFTER.ago)

      order_confirmations.each do |order_confirmation|
        begin
          scanned_orders = scanned_orders + 1

          # Only the bundle SAME_ORDER flow resumes safely (step markers) - a crashed
          # NEW_ORDER / v1 run may already have made its Shopify change, so leave it alone
          setting = order_confirmation.shop.setting
          if order_confirmation.status == 'Partial-Payment-In-Progress' &&
             !(setting.partial_payment_flow_version == 2 && setting.partial_payment_flow != 'NEW_ORDER')
            next
          end

          if order_confirmation.shop.setting.partial_payment_flow_version == 2
            ShopifyJobs::PartialOrderEditJob.perform_async(
              order_confirmation.shop.id, 
              order_confirmation.order_id, 
              order_confirmation.partial_payment_variants,
              true
            )
            next
          end
          
          if order_confirmation.partial_payment_variants.present?
            # ShopifyJobs::PartialOrderEditJob.perform_async(
            #   order_confirmation.shop.id, 
            #   order_confirmation.order_id, 
            #   order_confirmation.partial_payment_variants
            # )

            ShopifyServices::PartialOrderMappingService.call(order_confirmation.shop, order_confirmation.order_id)

            success_orders = success_orders + 1
            success_order_ids << order_confirmation.id
          end
          
        rescue Exception => e
          SlackNotifier::CLIENT.ping(
            text: "Error processing Partial Payment Check (#{Rails.env}) - Order Confirmation ID: #{order_confirmation.id} - #{order_confirmation.shop.shopify_domain} #{e} Partial Variants: #{order_confirmation.partial_payment_variants}",
          )
          failed_orders = failed_orders + 1
          failed_order_ids << order_confirmation.id
        end
      end
      
      # Send final report with success and failed IDs
      success_ids_text = success_order_ids.any? ? "Success IDs: #{success_order_ids.join(', ')}" : "No successful orders"
      failed_ids_text = failed_order_ids.any? ? "Failed IDs: #{failed_order_ids.join(', ')}" : "No failed orders"
      
      SlackNotifier::CLIENT.ping(
        text: "Report for Partial Payment Check Job (#{Rails.env}) - Scanned Orders #{scanned_orders} - Success Orders #{success_orders} - Failed Orders #{failed_orders}\n#{success_ids_text}\n#{failed_ids_text}",
      )
      puts 'PartialPaymentCheckJob job completed'
    end
  end
end
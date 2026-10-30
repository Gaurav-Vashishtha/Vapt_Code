module SidekiqJobs
    #SidekiqJobs::WebhookCustomerCreateJob.perform_async
  class WebhookCustomerCreateJob < ApplicationJob
    BATCH_SIZE = 1000

    def perform(*args)

      count = 0
      success_count = 0
      replaced_count = 0
      already_count = 0
      failed_count = 0

      webhook3 = {
        topic: 'customers/create',
        address: 'arn:aws:events:us-west-2::event-source/aws.partner/shopify.com/5284415/codkingprodcustomercreate',
        format: 'json'
        }

        batch_index = 0
        # in_batches keeps memory bounded for large shop tables and gives us a
        # natural place to emit per-batch progress totals.
        Shop.in_batches(of: BATCH_SIZE, order: :desc) do |shop_batch|
          batch_index += 1
          batch_started_at = Time.current
          puts "==== Batch #{batch_index} starting (size=#{shop_batch.size}) ===="

          shop_batch.each do |shop|
            count = count + 1
            puts "[#{count}] -> #{shop.shopify_domain} (id=#{shop.id})"
            begin
              shop.init_session

              existing = ShopifyAPI::Webhook.find(:all)
              customer_create_hooks = existing.is_a?(Array) ? existing.select { |w| w.topic == 'customers/create' } : []

              # Case 1: a customers/create webhook already points at the target ARN — nothing to do.
              if customer_create_hooks.any? { |w| w.address == webhook3[:address] }
                already_count = already_count + 1
                puts "    already at target ARN"
                next
              end

              # Case 2: customers/create webhook(s) exist at a different ARN — destroy them
              # so we end up with exactly one subscription at the target ARN.
              # Case 3: no customers/create webhook exists — this loop is a no-op.
              customer_create_hooks.each do |w|
                w.destroy
                puts "    deleted stale webhook (#{w.address})"
              end

              # Creates the webhook for both Case 2 (after destroying old) and Case 3 (from scratch).
              is_success = ShopifyAPI::Webhook.new(webhook3).save
              if is_success
                if customer_create_hooks.any?
                  replaced_count = replaced_count + 1
                  puts "    replaced"
                else
                  success_count = success_count + 1
                  puts "    created"
                end
              else
                failed_count = failed_count + 1
                puts "    save failed"
              end
            rescue Exception => e
              puts "    EXCEPTION #{e.class}: #{e.message}"
              failed_count = failed_count + 1
              # SlackNotifyJob.perform_async(
              #   ":rage:  (#{Rails.env})\n  Webhookrefresh job -Exception - #{shop.shopify_domain} #{e.message}"
              # )
            end
          end

          duration = (Time.current - batch_started_at).round(1)
          puts "==== Batch #{batch_index} done in #{duration}s | running totals: scanned=#{count} created=#{success_count} replaced=#{replaced_count} already=#{already_count} failed=#{failed_count} ===="
        end

      SlackNotifyJob.perform_async(
        ":heart:  (#{Rails.env})\n  WebhookCustomerCreateJob job - Shops scanned - #{count} \nWebhooks created #{success_count} \nReplaced #{replaced_count} \nAlready subscribed #{already_count} \nFailed Count #{failed_count}"
      )
    end
  end
end

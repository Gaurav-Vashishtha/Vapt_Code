module ShopifyJobs
    class SqsConsumerJob < ApplicationJob
    sidekiq_options queue: 'default'
  
      def perform(cron_triggered = true)
        sqs = Aws::SQS::Client.new(region: ENV['AWS_SQS_Q_REGION'],
        access_key_id: ENV['AWS_SQS_ACCESS_KEY'],
        secret_access_key: ENV['AWS_SQS_ACCESS_SECRET']
        )
  
        result = sqs.receive_message({
          queue_url: ENV['AWS_SQS_Q_URL'],
          max_number_of_messages: 10
        })
  
        # schedule 5 SQS jobs every 10 seconds
        # if cron_triggered
        #   [10, 20, 30, 40, 50].each do | num |
        #     ShopifyJobs::SqsConsumerJob.perform_in(num.seconds, false)
        #   end
        # end
        
        if result.messages.count < 1
          puts "========== No Messages Received from SQS ======"
          #ShopifyJobs::SqsConsumerJob.perform_in(30.seconds, false)
          return 
        end
  
        puts "========================== Received #{result.messages.count} message(s) ====================="
        result.messages.each do |message|
          process_message(message)
        end
        resp = sqs.delete_message_batch({
          queue_url: ENV['AWS_SQS_Q_URL'],
          entries: result.messages.map.with_index do |message, index|
            {
              id: index.to_s,
              receipt_handle: message.receipt_handle,
            }
          end
        })
        puts "========================== Deleted #{resp.successful.count} message(s) ======================="
        # SlackNotifyJob.perform_async(
        #   ":heart: SQS Consumer *Success* (#{Rails.env}) \n*messages*:\n #{resp.successful.count}",
        # )
  
        ShopifyJobs::SqsConsumerJob.perform_in(1.seconds, false)
      end
  
      def process_message (message)
        # handle messages with long payload error...... > 256KB
        # https://shopify.dev/apps/webhooks/configuration/eventbridge#large-payloads
        # handled for product jobs*
        begin
          data = JSON.parse(message.body)
          metadata = data['detail']['metadata']
          payload = data['detail']['payload']
        #   webhook_job_klass(metadata['X-Shopify-Topic']).perform_async(
        #     metadata['X-Shopify-Shop-Domain'], payload
        #   )
        if metadata['X-Shopify-Topic'] == 'orders/fulfilled'
            # DEBUG: temporary alert for codkingdemo. Remove once the BSP
            # fulfilment flow is verified end-to-end. Fires on every fulfilled
            # webhook for this shop so we can confirm SQS → consumer → dispatch.
            shop_domain_dbg = metadata['X-Shopify-Shop-Domain']
            if shop_domain_dbg == 'codkingdemo.myshopify.com'
              SlackNotifyJob.perform_async(
                ":mag: orders/fulfilled webhook received (#{Rails.env}) " \
                "shop=#{shop_domain_dbg} order=#{payload['id']} " \
                "name=#{payload['name']} " \
                "fulfillments_in_payload=#{Array(payload['fulfillments']).size}"
              )
            end

            NetworkJobs::WebhookForwarderJob.perform_async(payload,metadata['X-Shopify-Shop-Domain'],'fulfiled')
            # Fan out to the per-shop BSP WhatsApp pipeline. Skips silently if no binding/account.
            # Some Shopify API versions don't embed `fulfillments[]` in the
            # orders/fulfilled webhook payload. Fall back to an empty fulfillment
            # hash so variables that reference tracking will at least flow
            # through the `—` blank-fallback in VariableResolver instead of the
            # whole dispatch being silently dropped here.
            latest_fulfillment = Array(payload['fulfillments']).max_by { |f| f['updated_at'] || f['created_at'] || '' } || {}
            if Array(payload['fulfillments']).empty?
              Rails.logger.info("[sqs_consumer] orders/fulfilled payload had no embedded fulfillments — dispatching with empty fulfillment shop=#{metadata['X-Shopify-Shop-Domain']} order=#{payload['id']}")
            end
            bsp_jid = Whatsapp::DispatchEventJob.perform_async(
              'order_fulfilled',
              metadata['X-Shopify-Shop-Domain'],
              { 'order' => payload, 'fulfillment' => latest_fulfillment }
            )

            # DEBUG: confirm the BSP dispatch was enqueued (or wasn't).
            # If this alert fires but the merchant gets no message, the drop
            # is inside DispatchEventJob (no binding / account not ready /
            # template not approved / recipient blank — sidekiq log will say).
            if shop_domain_dbg == 'codkingdemo.myshopify.com'
              SlackNotifyJob.perform_async(
                ":arrow_forward: DispatchEventJob enqueued (#{Rails.env}) " \
                "shop=#{shop_domain_dbg} order=#{payload['id']} " \
                "jid=#{bsp_jid.inspect} " \
                "fulfillment_id=#{latest_fulfillment['id'].inspect}"
              )
            end
        elsif ::Whatsapp::ShopifyEventRouter.handles?(metadata['X-Shopify-Topic'])
          ::Whatsapp::ShopifyEventRouter.call(metadata['X-Shopify-Topic'], metadata['X-Shopify-Shop-Domain'], payload)
        elsif metadata['X-Shopify-Topic'] == 'orders/updated'
          NetworkJobs::WebhookForwarderJob.perform_async(payload,metadata['X-Shopify-Shop-Domain'],'order_updated')
        elsif metadata['X-Shopify-Topic'] == 'app/uninstalled'
          NetworkJobs::WebhookForwarderJob.perform_async(payload,metadata['X-Shopify-Shop-Domain'],'uninstalled')
        elsif metadata['X-Shopify-Topic'] == 'customers/create'
          puts "Omitting customer create"
          #NetworkJobs::WebhookForwarderJob.perform_async(payload,metadata['X-Shopify-Shop-Domain'],'customer_create')
        end         
        #Add similar for other webhooks like uninstall...

        rescue StandardError => e
          SlackNotifyJob.perform_async(
            ":rage: SQS Consumer *Error* (#{Rails.env}) \n*message*:\n #{message.inspect}",
          )
        end
      end
  
      def webhook_job_klass(topic)
        [webhook_namespace, "#{topic}_job"].compact.join('/').classify.constantize
      end
  
      def webhook_namespace
        'shopify_jobs'
      end
  
    end
  end

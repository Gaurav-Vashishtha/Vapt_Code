# app/services/sqs_message_processor_service.rb
class SqsMessageProcessorService
    def initialize
      @sqs_client = Aws::SQS::Client.new(
        region: ENV.fetch("AWS_SQS_Q_REGION", nil),
        access_key_id: ENV.fetch("AWS_SQS_ACCESS_KEY", nil),
        secret_access_key: ENV.fetch("AWS_SQS_ACCESS_SECRET", nil)
      )
      @total_processed = 0
      @batch_count = 0
    end
  
    def process_all_messages
      puts "Starting SQS message processing..."
      
      loop do
        @batch_count += 1
        puts "\n--- Batch #{@batch_count} ---"
        
        # Receive messages from SQS
        result = receive_messages
        
        # Break if no messages received
        if result.messages.empty?
          puts "No more messages in queue. Processing complete!"
          break
        end
        
        puts "Received #{result.messages.count} message(s)"
        
        # Process each message
        processed_messages = process_message_batch(result.messages)
        
        # Delete processed messages from SQS
        delete_processed_messages(processed_messages) if processed_messages.any?
        
        # Small delay between batches to avoid overwhelming the system
        sleep(0.5)
      end
      
      print_summary
    end
  
    private
  
    def receive_messages
      @sqs_client.receive_message({
        queue_url: ENV.fetch("AWS_SQS_Q_URL", nil),
        max_number_of_messages: 10,
        wait_time_seconds: 2 # Short polling to avoid long waits when queue is empty
      })
    end
  
    def process_message_batch(messages)
      processed_messages = []
      
      messages.each_with_index do |message, index|
        begin
          process_single_message(message)
          processed_messages << { message: message, index: index }
          puts "  ✓ Processed message #{index + 1}"
        rescue StandardError => e
          puts "  ✗ Error processing message #{index + 1}: #{e.message}"
          log_error(message, e)
          # Still add to processed_messages to delete it (you might want to change this behavior)
          processed_messages << { message: message, index: index }
        end
      end
      
      processed_messages
    end
  
    def process_single_message(message)
      data = JSON.parse(message.body)
      metadata = data['detail']['metadata']
      payload = data['detail']['payload']
      
      topic = metadata['X-Shopify-Topic']
      shop_domain = metadata['X-Shopify-Shop-Domain']
      
      case topic
      when 'orders/fulfilled'
        puts "    Processing order fulfillment for #{shop_domain}"

        # DEBUG: temporary alert for codkingdemo, mirrors SqsConsumerJob.
        # Remove once the BSP fulfilment flow is verified end-to-end.
        if shop_domain == 'codkingdemo.myshopify.com'
          SlackNotifyJob.perform_async(
            ":mag: [service-processor] orders/fulfilled received (#{Rails.env}) " \
            "shop=#{shop_domain} order=#{payload['id']} name=#{payload['name']} " \
            "fulfillments_in_payload=#{Array(payload['fulfillments']).size}"
          )
        end

        # MSG91 / legacy fulfilment path.
        NetworkJobs::WebhookForwarderJob.perform_async(payload, shop_domain, 'fulfiled')

        # BSP fan-out — mirror SqsConsumerJob. Some Shopify API versions don't
        # embed `fulfillments[]` in the payload; fall back to an empty hash so
        # the dispatch isn't silently dropped.
        latest_fulfillment = Array(payload['fulfillments']).max_by { |f|
          f['updated_at'] || f['created_at'] || ''
        } || {}
        if Array(payload['fulfillments']).empty?
          Rails.logger.info(
            "[sqs_service] orders/fulfilled payload had no embedded fulfillments — " \
            "dispatching with empty fulfillment shop=#{shop_domain} order=#{payload['id']}"
          )
        end
        bsp_jid = Whatsapp::DispatchEventJob.perform_async(
          'order_fulfilled',
          shop_domain,
          { 'order' => payload, 'fulfillment' => latest_fulfillment }
        )

        # DEBUG: confirm the BSP dispatch enqueued. Drop is then inside
        # DispatchEventJob (no binding / not approved / no recipient / Meta error).
        if shop_domain == 'codkingdemo.myshopify.com'
          SlackNotifyJob.perform_async(
            ":arrow_forward: [service-processor] DispatchEventJob enqueued (#{Rails.env}) " \
            "shop=#{shop_domain} order=#{payload['id']} jid=#{bsp_jid.inspect} " \
            "fulfillment_id=#{latest_fulfillment['id'].inspect}"
          )
        end
      when *::Whatsapp::ShopifyEventRouter::TOPICS
        ::Whatsapp::ShopifyEventRouter.call(topic, shop_domain, payload)
      when 'app/uninstalled'
        puts "    Processing app uninstall for #{shop_domain}"
        NetworkJobs::WebhookForwarderJob.perform_async(payload, shop_domain, 'uninstalled')
      when 'customers/create'
        puts "    Omitting customer create for #{shop_domain}"
        # NetworkJobs::WebhookForwarderJob.perform_async(payload, shop_domain, 'customer_create')
      else
        puts "    Unknown topic: #{topic} for #{shop_domain}"
      end
    rescue JSON::ParserError => e
      puts "    JSON parsing error: #{e.message}"
      raise e
    rescue StandardError => e
      puts "    Processing error: #{e.message}"
      raise e
    end
  
    def delete_processed_messages(processed_messages)
      delete_resp = @sqs_client.delete_message_batch({
        queue_url: ENV.fetch("AWS_SQS_Q_URL", nil),
        entries: processed_messages.map do |pm|
          {
            id: pm[:index].to_s,
            receipt_handle: pm[:message].receipt_handle,
          }
        end
      })
      
      deleted_count = delete_resp.successful.count
      puts "Deleted #{deleted_count} message(s) from queue"
      @total_processed += deleted_count
      
      # Handle any failed deletions
      if delete_resp.failed.any?
        puts "Failed to delete #{delete_resp.failed.count} message(s)"
        delete_resp.failed.each do |failed|
          puts "  Failed: #{failed.code} - #{failed.message}"
        end
      end
    end
  
    def log_error(message, error)
      # Optional: Send Slack notification for errors
      # SlackNotifyJob.perform_async(
      #   ":rage: SQS Service Processor *Error* (#{Rails.env}) \n*message*:\n #{message.inspect}\n*error*:\n #{error.message}",
      # )
      Rails.logger.error "SQS Processing Error: #{error.message} - Message: #{message.inspect}"
    end
  
    def print_summary
      puts "\n=== Processing Summary ==="
      puts "Total batches processed: #{@batch_count - 1}" # -1 because last batch was empty
      puts "Total messages processed: #{@total_processed}"
      puts "Processing completed at: #{Time.current}"
    end
  end
module ShopifyJobs
  # Polls a dedicated SQS queue (fed by the customers/create EventBridge subscription)
  # and inline-calls ShopifyServices::CustomerSingleDataSaveService for each message.
  #
  # Mirrors the self-rescheduling polling pattern of SqsConsumerJob but is scoped to a
  # single topic, runs on its own Sidekiq queue ('customer_create_sqs'), and consumes
  # its own SQS queue (AWS_SQS_CUSTOMER_CREATE_Q_URL) so it can be tuned/paused
  # independently of the multi-topic consumer.
  #
  # Kill switch:
  #   heroku config:set SQS_CUSTOMER_CREATE_CONSUMER_ENABLED=false
  # The next invocation returns early without rescheduling, so the polling loop
  # dies within ~4s. Set back to true (or unset) and trigger one invocation to
  # restart the loop.
  class CustomerCreateSqsConsumerJob < ApplicationJob
    sidekiq_options queue: 'customer_create_sqs'

    POLL_INTERVAL = 4.seconds
    MAX_MESSAGES = 10

    def perform(_cron_triggered = true)
      return unless enabled?

      queue_url = ENV['AWS_SQS_CUSTOMER_CREATE_Q_URL']
      if queue_url.blank?
        Rails.logger.warn('[CustomerCreateSqsConsumerJob] AWS_SQS_CUSTOMER_CREATE_Q_URL not set; aborting')
        return
      end

      sqs = Aws::SQS::Client.new(
        region: ENV['AWS_SQS_Q_REGION'],
        access_key_id: ENV['AWS_SQS_ACCESS_KEY'],
        secret_access_key: ENV['AWS_SQS_ACCESS_SECRET']
      )

      result = sqs.receive_message(queue_url: queue_url, max_number_of_messages: MAX_MESSAGES)

      if result.messages.count < 1
        puts "========== No customers/create messages received from SQS ======"
        return
      end

      puts "========================== Received #{result.messages.count} customers/create message(s) ====================="
      result.messages.each { |message| process_message(message) }

      resp = sqs.delete_message_batch(
        queue_url: queue_url,
        entries: result.messages.map.with_index do |message, index|
          { id: index.to_s, receipt_handle: message.receipt_handle }
        end
      )
      puts "========================== Deleted #{resp.successful.count} customers/create message(s) ======================="

      # Re-check the kill switch before rescheduling so a flip to false stops
      # the loop without waiting for the next poll to no-op.
      ShopifyJobs::CustomerCreateSqsConsumerJob.perform_in(POLL_INTERVAL, false) if enabled?
    end

    def process_message(message)
      data = JSON.parse(message.body)
      metadata = data['detail']['metadata']
      payload = data['detail']['payload']

      topic = metadata['X-Shopify-Topic']
      unless topic == 'customers/create'
        puts "Skipping non-customers/create topic on dedicated queue: #{topic}"
        return
      end

      shopify_domain = metadata['X-Shopify-Shop-Domain']
      shop = Shop.find_by(shopify_domain: shopify_domain)
      unless shop
        SlackNotifyJob.perform_async(
          ":rage: CustomerCreateSqsConsumerJob (#{Rails.env}) shop not found #{shopify_domain}"
        )
        return
      end

      # Mirror the existing WebhookForwarderJob#customer_create branch — service
      # expects camelCase keys (GraphQL convention).
      customer = JSON.parse(payload.to_json).to_h
      camelized_hash = customer.transform_keys { |key| key.to_s.camelize(:lower) }
      ShopifyServices::CustomerSingleDataSaveService.call(shop, camelized_hash)
    rescue StandardError => e
      SlackNotifyJob.perform_async(
        ":rage: CustomerCreateSqsConsumer *Error* (#{Rails.env}) \n*message*:\n #{message.inspect} \n*err*: #{e.class}: #{e.message}"
      )
    end

    private

    # Default ON so an unset env var means same behavior as today.
    # Treat any non-"false" value as enabled.
    def enabled?
      ENV.fetch('SQS_CUSTOMER_CREATE_CONSUMER_ENABLED', 'true').to_s.downcase != 'false'
    end
  end
end

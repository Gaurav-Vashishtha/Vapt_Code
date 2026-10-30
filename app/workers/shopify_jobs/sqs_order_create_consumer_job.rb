module ShopifyJobs
    class SqsOrderCreateConsumerJob < ApplicationJob
      sidekiq_options queue: 'sqs'
  
      def perform(cron_triggered = true)
        puts 'Kicking in SqsOrderCreateConsumerJob'
        
        sqs = Aws::SQS::Client.new(region: ENV['AWS_SQS_Q_REGION'],
        access_key_id: ENV['AWS_SQS_ACCESS_KEY'],
        secret_access_key: ENV['AWS_SQS_ACCESS_SECRET']
        )
  
        result = sqs.receive_message({
          queue_url: ENV['AWS_SQS_ORDER_CREATE'],
          max_number_of_messages: 10
        })
  
        # schedule 5 SQS jobs every 10 seconds
        # if cron_triggered
        #   [10, 20, 30, 40, 50].each do | num |
        #     ShopifyJobs::SqsConsumerJob.perform_in(num.seconds, false)
        #   end
        # end
  
        if result.messages.count < 1
          puts "========== No Messages Received from SQS Order Create======"
          # ShopifyJobs::SqsOrderCreateConsumerJob.perform_in(1.seconds, false)
          return
        end
  
        puts "========================== Received #{result.messages.count} message(s) ====================="
        result.messages.each do |message|
          process_message(message)
        end
        resp = sqs.delete_message_batch({
          queue_url: ENV['AWS_SQS_ORDER_CREATE'],
          entries: result.messages.map.with_index do |message, index|
            {
              id: index.to_s,
              receipt_handle: message.receipt_handle,
            }
          end
        })
        puts "========================== Deleted #{resp.successful.count} message(s) ======================="
        # SlackNotifyJob.perform_async(
        #   ":heart: SQS Consumer Order Create *Success* (#{Rails.env}) \n*messages*:\n #{resp.successful.count}",
        # )
  
        # ShopifyJobs::SqsOrderCreateConsumerJob.perform_in(1.seconds, false)
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
        if metadata['X-Shopify-Topic'] == 'orders/create'
            shop_domain = metadata['X-Shopify-Shop-Domain']

            # Forward to the legacy MSG91 pipeline. WebhookForwarderJob also
            # runs OrderConfirmationCreateJob inline, which is the canonical
            # owner of the BSP `cod_verification` dispatch — so we DO NOT
            # fan out cod_verification here. Doing it in two places opened
            # a race (both dispatchers passing the dedup check before either
            # created a log row → duplicate Meta send).
            NetworkJobs::WebhookForwarderJob.perform_async(payload, shop_domain, 'create')

            # BSP `order_created` fan-out stays here because it has no
            # corresponding handler inside OrderConfirmationCreateJob —
            # this is its single source of truth.
            #
            # EXCEPT for COD orders that are about to receive the BSP
            # cod_verification prompt: sending "Order Confirmed" in the same
            # breath as "please confirm" defeats the verification. For those,
            # Whatsapp::HandleCodVerificationReplyJob dispatches order_created
            # once the buyer taps Confirm (DispatchEventJob dedups on order id,
            # so it must NOT have been sent here first).
            if awaiting_cod_verification?(shop_domain, payload)
              Rails.logger.info(
                "[sqs_order_create] shop=#{shop_domain} order=#{payload['id']} " \
                "order_created deferred until COD verification is confirmed"
              )
            else
              Whatsapp::DispatchEventJob.perform_async('order_created', shop_domain, { 'order' => payload })
            end
        end
        #Add similar for other webhooks like uninstall...

        rescue StandardError => e
          SlackNotifyJob.perform_async(
            ":rage: SQS Consumer *Error* (#{Rails.env}) \n*message*:\n #{message.inspect}",
          )
        end
      end
  
      # True when OrderConfirmationCreateJob is about to ask the buyer to verify
      # this COD order — via the BSP cod_verification template OR the legacy
      # MSG91 path (OTP SMS / WhatsApp verification link). The order_created
      # message then waits for that verification: every verification path
      # (BSP Confirm tap, /order_confirmations/confirm, manual confirm) sends it
      # through Whatsapp::OrderConfirmationNotifier. Sending it here as well
      # would make DispatchEventJob's per-order dedup swallow the post-verify
      # send, so the buyer would never get the confirmation after verifying.
      #
      # Mirrors the gates in OrderConfirmationCreateJob#create_order so we never
      # defer an order that won't actually get a verification prompt (it would
      # then never get order_created at all). Any error → false, so a bug here
      # can only ever send order_created early, never suppress it.
      def awaiting_cod_verification?(shop_domain, payload)
        shop = Shop.find_by(shopify_domain: shop_domain)
        return false unless shop

        setting = shop.setting
        return false unless setting
        return false if payload['source_name'].to_s == 'pos'
        return false unless OrderConfirmation.new(shop: shop).is_cod(payload)

        draft = payload['source_name'].to_s == 'shopify_draft_order'
        return false if draft && setting.skip_draft_order

        country = payload.dig('shipping_address', 'country_code') ||
                  payload.dig('billing_address', 'country_code') ||
                  payload.dig('customer', 'default_address', 'country_code')
        if setting.include_countries.present? && !setting.include_countries.split(',').include?(country)
          return false
        end

        # A paused cod_verification sends no prompt on any channel (see
        # OrderConfirmationCreateJob), so nothing would ever release a deferred order_created.
        return false if cod_verification_paused?(shop)
        return true if bsp_cod_verification_ready?(shop)

        # The WhatsApp verification link goes out even when the buyer already
        # verified their phone with the pre-order OTP (order saved COD-Verified).
        return true if setting.send_verification_link_only && !draft

        # Buyer already verified their phone with the pre-order OTP — no OTP
        # SMS prompt, so the legacy path sends the confirmation straight away.
        otp_verified = Array(payload['note_attributes']).any? do |na|
          na.is_a?(Hash) && na['name'] == '_otpVerifiedPhoneNumber' && na['value'].present?
        end
        return false if otp_verified

        return true if setting.sms

        false
      rescue StandardError => e
        Rails.logger.warn("[sqs_order_create] awaiting_cod_verification? failed shop=#{shop_domain}: #{e.class}: #{e.message}")
        false
      end

      def cod_verification_paused?(shop)
        shop.whatsapp_template_bindings.for_event('cod_verification').paused.exists?
      end

      def bsp_cod_verification_ready?(shop)
        binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'cod_verification')
        return false unless binding

        (binding.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send? ? true : false
      end

      def webhook_job_klass(topic)
        [webhook_namespace, "#{topic}_job"].compact.join('/').classify.constantize
      end
  
      def webhook_namespace
        'shopify_jobs'
      end
  
    end
  end
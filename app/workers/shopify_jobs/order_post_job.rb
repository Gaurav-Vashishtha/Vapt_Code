module ShopifyJobs
  class OrderPostJob
    include Sidekiq::Worker
    sidekiq_options retry: false

    MAX_RETRIES = 3
    DEFAULT_VERIFICATION_TAG = '✅ COD-Verified'.freeze
    # COD-Cancelled is only ever set by the customer (verification link, IVR, WhatsApp/BSP reply).
    CUSTOMER_CANCELLED_TAG = '❌ COD-Customer-Cancelled'.freeze

    TAGS_MAP = {
      'Pending': '⚠ COD-Pending',
      'COD-Verified': DEFAULT_VERIFICATION_TAG,
      'COD-Prepaid': '✅ COD-Prepaid',
      'COD-Cancelled': CUSTOMER_CANCELLED_TAG,
      'COD-Manual-Verified': '✅ COD-Manual-Verified',
      'COD-SKIP-VERIFICATION': '⛔ COD-Skip-Verification'
    }

    def perform(shop_id, order_confirmation_id, input_tag = '', attempt = 1)
      begin
        order_confirmation = OrderConfirmation.find(order_confirmation_id)
        shop = order_confirmation.shop

        if order_confirmation.status.blank? && input_tag.blank?
          if attempt < MAX_RETRIES
            self.class.perform_in(10.seconds, shop_id, order_confirmation_id, input_tag, attempt + 1)
          else
            SlackNotifyJob.perform_async(
              ":warning: (#{Rails.env}) `OrderPostJob` status remained blank for shop_id: #{shop_id}, order_confirmation_id: #{order_confirmation_id}"
            )
          end
          return
        end

        return unless shop.setting.sms || shop.setting.enable_pre_order_otp || shop.setting.send_verification_link_only

        status_sym = order_confirmation.status.to_sym
        verification_tag = shop.setting&.verification_tag.presence || DEFAULT_VERIFICATION_TAG

        tag = if input_tag.present?
                input_tag
              elsif status_sym == :'COD-Verified'
                verification_tag
              else
                TAGS_MAP[status_sym]
              end

        return if tag.blank? # Exit quietly if tag couldn't be resolved

        ShopifyServices::OrderPostService.call(
          shop,
          order_confirmation.order_id,
          tag,
          order_confirmation.customer_number
        )

      rescue => e
        SlackNotifyJob.perform_async(
          ":rage: (#{Rails.env}) `OrderPostJob` error on attempt #{attempt} for shop_id: #{shop_id}, order_confirmation_id: #{order_confirmation_id}\n> `#{e.message}`\n```#{e.backtrace.take(10).join("\n")}```"
        )

        if attempt < MAX_RETRIES
          self.class.perform_in(4.seconds, shop_id, order_confirmation_id, input_tag, attempt + 1)
        else
          SlackNotifyJob.perform_async(
            ":x: (#{Rails.env}) `OrderPostJob` failed after #{MAX_RETRIES} attempts for shop_id: #{shop_id}, order_confirmation_id: #{order_confirmation_id}"
          )
        end
      end
    end
  end
end

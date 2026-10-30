# frozen_string_literal: true

module Whatsapp
  # Confirm / cancel side effects shared by the quick-reply button handler and the AI agent.
  module CodVerificationActions
    TERMINAL_STATUSES = %w[COD-Verified COD-Cancelled COD-Auto-Cancelled].freeze

    module_function

    def terminal?(order_confirmation)
      TERMINAL_STATUSES.include?(order_confirmation.status.to_s)
    end

    def confirm!(shop:, oc:, payload_snapshot: nil)
      verification_tag =
        shop.setting&.verification_tag.presence ||
        ShopifyJobs::OrderPostJob::DEFAULT_VERIFICATION_TAG

      ShopifyServices::OrderPostService.call(shop, oc.order_id, verification_tag, oc.customer_number)
      oc.update(status: 'COD-Verified', confirmed_at: Time.current, is_otp_verified: true)
      Whatsapp::OrderConfirmationNotifier.call(shop: shop, order_confirmation: oc, payload_snapshot: payload_snapshot)

      if defined?(CodFormCustomerSyncJob)
        CodFormCustomerSyncJob.perform_async(oc.shop_id, oc.customer_number, oc.customer_email, oc.customer_name)
      end
      oc
    end

    def cancel!(shop:, oc:, only_if_cancelled: false)
      ShopifyServices::OrderPostService.call(
        shop, oc.order_id, ShopifyJobs::OrderPostJob::CUSTOMER_CANCELLED_TAG, oc.customer_number
      )
      result = ShopifyServices::CancelCodOrderService.call(shop: shop, order_id: oc.order_id)
      oc.update(status: 'COD-Cancelled', confirmed_at: Time.current) if !only_if_cancelled || result.cancelled
      result
    end
  end
end

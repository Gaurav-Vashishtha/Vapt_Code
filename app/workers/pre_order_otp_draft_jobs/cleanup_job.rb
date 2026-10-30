# frozen_string_literal: true

module PreOrderOtpDraftJobs
  # The shopper placed an order: delete the open abandoned-cart draft so the merchant
  # doesn't see (or complete) a duplicate. Enqueued by PreOrderOtpDraftJobs::OrderHook.
  class CleanupJob < ApplicationJob
    sidekiq_options queue: "low", retry: 3

    def perform(draft_row_id, shopify_order_id)
      row = PreOrderOtpDraftOrder.find_by(id: draft_row_id)
      return if row.blank? || !row.open_draft?

      row.with_lock do
        next unless row.open_draft?

        svc = ShopifyServices::OtpDraftOrderService.for(row.shop)
        current = svc.status(row.draft_order_gid)
        raise "draft status lookup failed: #{current.errors.inspect}" unless current.ok?

        case current.status
        when "OPEN", "INVOICE_SENT"
          result = svc.delete(row.draft_order_gid)
          raise "draftOrderDelete failed: #{result.errors.inspect}" unless result.ok?

          row.update!(status: "converted", shopify_order_id: shopify_order_id.to_s, last_error: nil)
        when "COMPLETED"
          row.update!(status: "completed")
        else
          row.update!(status: "deleted", shopify_order_id: shopify_order_id.to_s)
        end
        Rails.logger.info("[otp_draft_order] shop=#{row.shop_id} device=#{row.device_id} cleanup -> #{row.status}")
      end
    end
  end
end

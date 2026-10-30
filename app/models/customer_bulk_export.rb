# frozen_string_literal: true

# One Shopify bulk export of a shop's customers (see ShopifyServices::CustomerBulkExportService).
#
#   requested -> running -> completed -> loading -> loaded
#                                   \-> failed (any step)
class CustomerBulkExport < ApplicationRecord
  belongs_to :shop

  AT_SHOPIFY = %w[requested running].freeze
  LOADABLE   = %w[loading completed].freeze # Shopify's file is ready; `loading` = partly loaded
  ACTIVE     = (AT_SHOPIFY + LOADABLE).freeze

  scope :active, -> { where(status: ACTIVE) }
  scope :at_shopify, -> { where(status: AT_SHOPIFY) }
  scope :loadable, -> { where(status: LOADABLE) }

  # Shop is fully imported: flag it complete (the live queue then only does incremental pulls)
  # and close its pending/failed rows in the old pull queue.
  def finalize_shop!
    done_at = [shop.initial_customer_pull_completed, requested_at].compact.max
    shop.update(initial_customer_pull_completed: done_at)
    CustomerPullJobQueue.where(shop_id: shop_id, status: %w[pending failed])
                        .update_all(status: 'done', error_message: nil, updated_at: Time.current)
  end

  def fail!(message)
    update!(status: 'failed', error: message.to_s.truncate(1000))
  end
end

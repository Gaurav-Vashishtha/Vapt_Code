# frozen_string_literal: true

class CustomerBulkExport < ApplicationRecord
  belongs_to :shop

  AT_SHOPIFY = %w[requested running].freeze
  LOADABLE = %w[loading completed].freeze
  ACTIVE = (AT_SHOPIFY + LOADABLE).freeze

  scope :active, -> { where(status: ACTIVE) }
  scope :at_shopify, -> { where(status: AT_SHOPIFY) }
  scope :loadable, -> { where(status: LOADABLE) }

  def finalize_shop!
    done_at = [shop.initial_customer_pull_completed, requested_at].compact.max
    shop.update(initial_customer_pull_completed: done_at)
    CustomerSyncState.record_success!(shop_id, baseline: expected_count)
  end

  def fail!(message, count_failure: true)
    update!(status: 'failed', error: message.to_s.truncate(1000))
    if CustomerSyncState.unauthorized_message?(message)
      CustomerSyncState.mark_unreachable!(shop, message)
    else
      CustomerSyncState.record_failure!(shop_id, message, count_failure: count_failure)
    end
  end
end

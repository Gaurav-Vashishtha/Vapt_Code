# frozen_string_literal: true

# One relay attempt of a Meta webhook batch to the partner's webhook URL.
# Written by Whatsapp::ForwardWebhookJob; Sidekiq retries create fresh rows,
# so the portal shows every attempt, not just the final outcome.
class CustomBrandedWebhookDelivery < ApplicationRecord
  belongs_to :custom_branded_client

  scope :recent, -> { order(created_at: :desc) }

  KEEP_PER_CLIENT = 500

  def self.prune!(client_id)
    ids = where(custom_branded_client_id: client_id).order(id: :desc).offset(KEEP_PER_CLIENT).pluck(:id)
    where(id: ids).delete_all if ids.any?
  rescue StandardError
    nil
  end

  def delivered?
    response_code.present? && (200..299).cover?(response_code)
  end
end

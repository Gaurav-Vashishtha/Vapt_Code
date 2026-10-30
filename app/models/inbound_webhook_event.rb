# frozen_string_literal: true

class InboundWebhookEvent < ApplicationRecord
  belongs_to :shop
  belongs_to :webhook_endpoint, optional: true

  enum :status, { received: 0, processed: 1, skipped: 2, failed: 3 }, validate: true

  validates :provider, presence: true
  validates :received_at, presence: true

  scope :recent, -> { order(received_at: :desc) }
  scope :for_event, ->(name) { where(event_name: name.to_s) }
  scope :older_than, ->(time) { where(received_at: ...time) }

  def mark_processed!(internal_event_type_key: nil)
    update!(
      status: :processed,
      internal_event_type_key: internal_event_type_key,
      processed_at: Time.current,
      error: nil
    )
  end

  def mark_skipped!(reason)
    update!(status: :skipped, skip_reason: reason.to_s, processed_at: Time.current)
  end

  def mark_failed!(exception_or_message)
    message =
      if exception_or_message.respond_to?(:message)
        "#{exception_or_message.class}: #{exception_or_message.message}"
      else
        exception_or_message.to_s
      end

    update!(status: :failed, error: message.truncate(2000), processed_at: Time.current)
  end
end

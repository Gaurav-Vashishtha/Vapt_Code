class WhatsappCampaignRecipient < ApplicationRecord
  belongs_to :whatsapp_campaign
  belongs_to :shop

  STATUSES = %w[pending suppressed queued sent delivered read failed retry_pending].freeze

  scope :sendable, -> { where(status: 'pending') }
  scope :suppressed, -> { where(status: 'suppressed') }
  scope :awaiting_retry, -> { where(status: 'retry_pending') }
  scope :due_for_send, ->(at = Time.current) {
    where("status = 'pending' OR (status = 'retry_pending' AND next_retry_at <= ?)", at)
  }

  def suppress!(reason)
    update_columns(status: 'suppressed', suppression_reason: reason, updated_at: Time.current)
  end

  # Hands an unsent recipient back to the dispatcher (quiet hours, or the
  # campaign was paused after this send was enqueued). Conditional so it can
  # never undo a send that already happened.
  def return_to_pending!
    now = Time.current
    changed = self.class.where(id: id, status: 'queued').update_all(status: 'pending', queued_at: nil, updated_at: now)
    assign_attributes(status: 'pending', queued_at: nil) if changed.positive?
    changed.positive?
  end
end

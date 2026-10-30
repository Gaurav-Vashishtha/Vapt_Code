class CustomerPullJobQueue < ApplicationRecord
  belongs_to :shop

  enum status: {
    pending: 'pending',
    processing: 'processing',
    done: 'done',
    failed: 'failed',
    cancelled: 'cancelled'
  }

  # Scopes for processor: only process pending; cancelled entries are skipped (force-stop).
  scope :processable, -> { where(status: statuses[:pending]) }
end

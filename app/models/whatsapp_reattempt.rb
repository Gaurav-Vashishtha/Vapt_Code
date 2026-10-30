# frozen_string_literal: true

# Retry state for one WhatsApp message that Meta refused for a retryable reason.
# See Whatsapp::ReattemptPolicy (schedule), Whatsapp::ReattemptRecorder (failures
# in), Whatsapp::ReattemptDispatchJob (resends out).
class WhatsappReattempt < ApplicationRecord
  FLOWS = %w[msg91 bsp].freeze
  STATUSES = %w[pending sending sent delivered dropped cancelled].freeze
  FINISHED = %w[delivered dropped cancelled].freeze

  # A claimed row whose worker died is picked up again after this long.
  STALE_SENDING_AFTER = 30.minutes

  belongs_to :source, polymorphic: true, optional: true
  belongs_to :shop, optional: true

  validates :flow, inclusion: { in: FLOWS }
  validates :status, inclusion: { in: STATUSES }

  scope :due, lambda { |now = Time.current|
    where("(status = 'pending' AND next_retry_at <= :now) OR (status = 'sending' AND updated_at < :stale)",
          now: now, stale: now - STALE_SENDING_AFTER)
  }

  def finished?
    FINISHED.include?(status)
  end

  def bsp?
    flow == 'bsp'
  end

  def msg91?
    flow == 'msg91'
  end
end

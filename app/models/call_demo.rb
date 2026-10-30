# frozen_string_literal: true

class CallDemo < ApplicationRecord
  # Lifecycle of a scheduled demo.
  STATUSES = %w[scheduled conducted rescheduled no_show cancelled onboarded].freeze

  STATUS_LABELS = {
    "scheduled" => "Scheduled",
    "conducted" => "Conducted",
    "rescheduled" => "Rescheduled",
    "no_show" => "No-show",
    "cancelled" => "Cancelled",
    "onboarded" => "Onboarded"
  }.freeze

  # Statuses that still need attention (as opposed to closed-out ones).
  OPEN_STATUSES = %w[scheduled rescheduled].freeze

  # Moving a demo's date keeps it "scheduled" so it stays in the Scheduled
  # list, so "rescheduled" is not offered as a status an agent can pick. It
  # stays in STATUSES so rows written before that change still render.
  SELECTABLE_STATUSES = (STATUSES - %w[rescheduled]).freeze

  # Soonest-upcoming demo first; demos with no scheduled time fall last.
  scope :upcoming_first, -> { order(Arel.sql("scheduled_at ASC NULLS LAST"), created_at: :asc) }
  scope :with_status, ->(status) { STATUSES.include?(status.to_s) ? where(status: status.to_s) : all }

  def self.normalize_status(value)
    STATUSES.include?(value.to_s) ? value.to_s : "scheduled"
  end

  def status_label
    STATUS_LABELS.fetch(status.to_s, status.to_s.tr("_", " ").capitalize)
  end
end

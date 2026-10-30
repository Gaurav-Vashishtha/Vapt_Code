# frozen_string_literal: true

class ScheduledReportDelivery < ApplicationRecord
  belongs_to :shop
  belongs_to :scheduled_shop_report
  belongs_to :scheduled_report_definition

  STATUSES = %w[sent failed].freeze

  validates :report_kind, presence: true
  validates :status, inclusion: { in: STATUSES }
end


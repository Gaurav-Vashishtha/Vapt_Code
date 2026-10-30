# frozen_string_literal: true

class MerchantWhatsappLog < ApplicationRecord
  belongs_to :merchant_whatsapp_rule, optional: true

  STATUSES = %w[queued dry_run sent delivered read replied failed skipped].freeze
  RANK = { "queued" => 0, "dry_run" => 0, "sent" => 1, "delivered" => 2, "read" => 3, "replied" => 4 }.freeze

  scope :real, -> { where(dry_run: false) }
  scope :on_date, ->(date) { where(created_at: date.beginning_of_day..date.end_of_day) }

  def self.recent_send_for_domain(domain, within_hours)
    real.where(shopify_domain: domain, status: %w[sent delivered read replied])
        .where("sent_at >= ?", within_hours.hours.ago)
        .order(sent_at: :desc)
        .first
  end

  def advance_status!(new_status, at: Time.current)
    return unless RANK.key?(new_status)
    return if RANK[new_status].to_i <= RANK[status].to_i && !%w[queued dry_run].include?(status)

    column = { "delivered" => :delivered_at, "read" => :read_at, "replied" => :replied_at }[new_status]
    attrs = { status: new_status }
    attrs[column] = at if column
    update_columns(attrs.merge(updated_at: Time.current))
  end
end

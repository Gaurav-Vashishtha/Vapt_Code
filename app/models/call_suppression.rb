# frozen_string_literal: true

class CallSuppression < ApplicationRecord
  REASONS = %w[do_not_call not_interested invalid_number].freeze

  scope :active, -> { where("until_on IS NULL OR until_on >= ?", Date.current) }

  def self.suppressed_domains
    active.distinct.pluck(:shopify_domain)
  end

  def self.suppress!(domain:, reason:, days: nil, by: nil)
    until_on = days ? Date.current + days.days : nil
    record = find_or_initialize_by(shopify_domain: domain)
    record.assign_attributes(reason: reason, until_on: until_on, created_by: by)
    record.save!
    record
  end

  def permanent?
    until_on.nil?
  end
end

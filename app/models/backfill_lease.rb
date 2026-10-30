# frozen_string_literal: true

class BackfillLease < ApplicationRecord
  belongs_to :shop_domain

  validates :lease_key, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :expired, -> { where("expires_at < ?", Time.current) }

  def expired?
    expires_at < Time.current
  end
end


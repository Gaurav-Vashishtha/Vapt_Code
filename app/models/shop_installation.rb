# frozen_string_literal: true

class ShopInstallation < ApplicationRecord
  belongs_to :shop_domain
  belongs_to :shop, optional: true

  STATUSES = %w[installed uninstalled invalid].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "installed") }

  def mark_uninstalled!
    update!(status: "uninstalled", uninstalled_at: Time.current)
  end
end


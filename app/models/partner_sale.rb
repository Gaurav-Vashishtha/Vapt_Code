class PartnerSale < ApplicationRecord
  SALE_TYPES = %w[subscription usage adjustment].freeze

  scope :in_period, ->(from, to) { where(occurred_at: from..to) }
  scope :of_type, ->(type) { where(sale_type: type) }
  scope :for_domain, ->(domain) { where(shopify_domain: domain) }
end

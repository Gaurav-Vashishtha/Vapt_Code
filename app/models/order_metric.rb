class OrderMetric < ApplicationRecord
  belongs_to :shop
  belongs_to :order_confirmation, optional: true

  DELIVERY_STATUSES = %w[unfulfilled in_transit delivered rto returned cancelled refunded].freeze
end

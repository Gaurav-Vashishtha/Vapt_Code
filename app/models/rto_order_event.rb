# frozen_string_literal: true

class RtoOrderEvent < ApplicationRecord
  belongs_to :shop_domain

  validates :order_id, presence: true
  validates :event_type, presence: true
  validates :source, presence: true
end


class MrrSnapshot < ApplicationRecord
  belongs_to :shop, optional: true

  scope :on_date, ->(date) { where(snapshot_date: date) }
  scope :paying, -> { where('mrr > 0') }
end

class ChurnRiskSnapshot < ApplicationRecord
  belongs_to :shop, optional: true

  BANDS = %w[healthy watch at_risk critical].freeze

  scope :on_date, ->(date) { where(snapshot_date: date) }
  scope :actionable, -> { where(band: %w[at_risk critical]) }
  scope :by_priority, -> { order(Arel.sql('mrr * score DESC')) }
end

class FeatureAdoptionEvent < ApplicationRecord
  belongs_to :shop, optional: true

  scope :enabled_unused, -> { where(first_used_at: nil).where.not(first_enabled_at: nil) }
end

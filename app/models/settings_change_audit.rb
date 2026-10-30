class SettingsChangeAudit < ApplicationRecord
  belongs_to :shop, optional: true

  scope :disables, -> { where(new_value: %w[false f 0]) }
  scope :since, ->(time) { where('changed_at >= ?', time) }
end

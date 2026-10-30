class FollowUpComment < ApplicationRecord
  belongs_to :follow_up

  validates :comment, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }
end


# app/models/unsubscribed_email.rb
class UnsubscribedEmail < ApplicationRecord
  validates :email, presence: true, uniqueness: true

  # Case-insensitive lookup (use when checking before send/schedule)
  scope :for_email, ->(email) { where("LOWER(TRIM(email)) = ?", email.to_s.downcase.strip) }
end
  
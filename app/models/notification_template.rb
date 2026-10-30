class NotificationTemplate < ApplicationRecord
    validates :name, :subject, :view_file, :trigger_type, presence: true
  end
  
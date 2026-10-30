# frozen_string_literal: true

class EmailClickRedirect < ApplicationRecord
  belongs_to :scheduled_email

  validates :token, presence: true, uniqueness: true
  validates :destination_url, presence: true
end

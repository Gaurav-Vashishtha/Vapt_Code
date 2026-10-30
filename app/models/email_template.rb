# frozen_string_literal: true

class EmailTemplate < ApplicationRecord
  has_many :email_rules, dependent: :restrict_with_error

  validates :name, presence: true
  validates :subject, presence: true
  validates :body, presence: true
end

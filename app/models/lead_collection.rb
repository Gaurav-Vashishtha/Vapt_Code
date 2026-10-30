class LeadCollection < ApplicationRecord
  PURPOSE_OPTIONS = %w[
    product_demo
    facing_issue
    setup_help
    pricing_query
    integration_support
    agency_referral_program
    one_click_checkout
    rabbit_express
    other
  ].freeze

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone_number, presence: true
  validates :preferred_time_to_connect, presence: true
  validates :purpose, presence: true, inclusion: { in: PURPOSE_OPTIONS }
  validates :website, length: { maximum: 255 }, allow_blank: true
  validates :notes, length: { maximum: 2_000 }, allow_blank: true
end

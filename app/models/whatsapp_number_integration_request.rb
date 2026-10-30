# app/models/whatsapp_number_integration_request.rb
class WhatsappNumberIntegrationRequest < ApplicationRecord
  validates :shop_domain, presence: true
  validates :phone_number, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(status: 'pending') }
end


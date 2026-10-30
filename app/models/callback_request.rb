# app/models/callback_request.rb
class CallbackRequest < ApplicationRecord
    validates :shop_domain, presence: true
    validates :name, presence: true
    validates :phone_number, presence: true
    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    
    scope :recent, -> { order(created_at: :desc) }
    scope :pending, -> { where(status: 'pending') }
    
    def can_request_callback?
      return true if last_callback_request_at.nil?
      
      hours_since_last_request = (Time.current - last_callback_request_at) / 1.hour
      hours_since_last_request >= 24
    end
  end
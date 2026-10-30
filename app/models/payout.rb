# CREATE NEW FILE: app/models/payout.rb
class Payout < ApplicationRecord
    belongs_to :referral_partner
    has_many :payout_earnings, dependent: :destroy
    has_many :referral_earnings, through: :payout_earnings
  
    validates :total_amount, presence: true, numericality: { greater_than: 0 }
    validates :currency, presence: true
    validates :status, presence: true, inclusion: { in: %w[pending processing completed failed cancelled] }
    validates :payment_method, presence: true, inclusion: { in: %w[bank_transfer paypal] }
    validates :payout_date, presence: true
    validates :earnings_from_date, presence: true
    validates :earnings_to_date, presence: true
    validates :created_by, presence: true
  
    validate :earnings_date_range_valid
    #validate :no_overlapping_payouts
  
    scope :pending, -> { where(status: 'pending') }
    scope :completed, -> { where(status: 'completed') }
    scope :by_partner, ->(partner_id) { where(referral_partner_id: partner_id) }
    scope :by_date_range, ->(from_date, to_date) { where(payout_date: from_date..to_date) }
  
    def mark_as_processing!
      update!(status: 'processing', processed_at: Time.current)
    end
  
    def mark_as_completed!(transaction_reference = nil)
      update!(
        status: 'completed', 
        completed_at: Time.current,
        transaction_reference: transaction_reference
      )
      
      referral_earnings.update_all(payout_status: 'paid')
    end
  
    def mark_as_failed!(error_message = nil)
      update!(status: 'failed', notes: error_message)
    end
  
    def payment_details_json
      return {} if payment_details.blank?
      JSON.parse(payment_details)
    rescue JSON::ParserError
      {}
    end
  
    def payment_details_json=(data)
      self.payment_details = data.to_json
    end
  
    private
  
    def earnings_date_range_valid
      return unless earnings_from_date && earnings_to_date
      
      if earnings_from_date > earnings_to_date
        errors.add(:earnings_to_date, "must be after earnings from date")
      end
    end
  
    def no_overlapping_payouts
      return unless referral_partner_id && earnings_from_date && earnings_to_date
      
      overlapping = referral_partner.payouts
        .where.not(id: id)
        .where(status: ['pending', 'processing', 'completed'])
        .where(
          "(earnings_from_date <= ? AND earnings_to_date >= ?) OR " \
          "(earnings_from_date <= ? AND earnings_to_date >= ?) OR " \
          "(earnings_from_date >= ? AND earnings_to_date <= ?)",
          earnings_from_date, earnings_from_date,
          earnings_to_date, earnings_to_date,
          earnings_from_date, earnings_to_date
        )
      
      if overlapping.exists?
        errors.add(:base, "Payout period overlaps with existing payout")
      end
    end
  end
  
  # CREATE NEW FILE: app/models/payout_earning.rb
  class PayoutEarning < ApplicationRecord
    belongs_to :payout
    belongs_to :referral_earning
  
    validates :payout_id, uniqueness: { scope: :referral_earning_id }
  end
  
  # UPDATE EXISTING FILE: app/models/referral_partner.rb
  # Add these methods to your existing ReferralPartner model:
  
  class ReferralPartner < ApplicationRecord
    # Your existing associations and validations...
    
    # ADD THESE NEW ASSOCIATIONS:
    has_many :payouts, dependent: :destroy
  
    # ADD THESE NEW METHODS:
    def total_unpaid_earnings
      referral_earnings.unpaid.sum(:commission_amount)
    end
  
    def total_paid_earnings
      referral_earnings.paid.sum(:commission_amount)
    end
  
    def total_lifetime_earnings
      referral_earnings.sum(:commission_amount)
    end
  
    def last_payout
      payouts.completed.order(:earnings_to_date).last
    end
  
    def next_payout_from_date
      last_payout&.earnings_to_date&.+ 1.day || referral_earnings.minimum(:earning_date)
    end
  
    def payment_info
      case account_type
      when 'bank'
        {
          type: 'bank_transfer',
          details: {
            account_number: bank_account_number,
            ifsc: bank_ifsc_code,
            account_name: bank_account_name,
            bank_name: bank_name
          }
        }
      when 'paypal'
        {
          type: 'paypal',
          details: {
            email: paypal_email
          }
        }
      else
        nil
      end
    end
  end
  
  # UPDATE EXISTING FILE: app/models/referral_shop.rb
  # Add these methods to your existing ReferralShop model:
  
  class ReferralShop < ApplicationRecord
    # Your existing associations and validations...
  
    # ADD THESE NEW SCOPES:
    scope :needs_historical_sync, -> { where(historical_sync_completed: false) }
  
    # ADD THESE NEW METHODS:
    def mark_historical_sync_completed!
      update!(
        historical_sync_completed: true,
        last_sync_date: Date.current
      )
    end
  
    def historical_sync_date_range
      return nil unless created_at
      
      from_date = historical_sync_from_date || [created_at.to_date - 30.days, created_at.to_date].min
      to_date = created_at.to_date
      
      { from: from_date, to: to_date }
    end
  
    def next_sync_from_date
      last_sync_date || created_at&.to_date || Date.current
    end
  end
  
  # UPDATE EXISTING FILE: app/models/referral_earning.rb
  # Add these to your existing ReferralEarning model:
  
  class ReferralEarning < ApplicationRecord
    # Your existing associations and validations...
  
    # ADD THESE NEW ASSOCIATIONS:
    has_many :payout_earnings, dependent: :destroy
    has_many :payouts, through: :payout_earnings
  
    # ADD THESE NEW VALIDATIONS:
    validates :payout_status, presence: true, inclusion: { in: %w[unpaid pending_payout paid] }
  
    # ADD THESE NEW SCOPES:
    scope :unpaid, -> { where(payout_status: 'unpaid') }
    scope :paid, -> { where(payout_status: 'paid') }
    scope :by_partner, ->(partner_id) { where(referral_partner_id: partner_id) }
    scope :by_date_range, ->(from_date, to_date) { where(earning_date: from_date..to_date) }
    scope :by_transaction_type, ->(type) { where(transaction_type: type) }
  
    # ADD THIS NEW CLASS METHOD:
    def self.pending_payout_amount(partner_id = nil)
      scope = unpaid
      scope = scope.by_partner(partner_id) if partner_id
      scope.sum(:commission_amount)
    end
  end
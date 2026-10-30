class ReferralPartner < ApplicationRecord
    has_secure_password

    before_validation :assign_referral_code, on: :create
    
    has_many :referral_shops, dependent: :destroy
    has_many :referral_earnings, dependent: :destroy
    has_many :approved_shops, -> { where(approved: true) }, class_name: 'ReferralShop'
    has_many :payouts, dependent: :destroy

    validates :name, presence: true
    validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :referral_code, uniqueness: true, allow_nil: true
    validates :referral_code, presence: true, on: :create
    validates :subscription_commission_rate, :usage_commission_rate, :onetime_commission_rate,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    
    validates :account_type, inclusion: { in: %w[bank paypal], allow_blank: true }
    
    # Bank account validations (when account_type is 'bank')
    validates :bank_account_number, :bank_ifsc_code, :bank_account_name, :bank_name,
              presence: true, if: -> { account_type == 'bank' }
    validates :bank_ifsc_code, format: { with: /\A[A-Z]{4}0[A-Z0-9]{6}\z/ }, 
              if: -> { account_type == 'bank' && bank_ifsc_code.present? }
    
    # PayPal validations (when account_type is 'paypal')
    validates :paypal_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP },
              if: -> { account_type == 'paypal' }
    
    scope :active, -> { where(active: true) }
    scope :with_verified_accounts, -> { where(account_verified: true) }
    
    def total_commission_earned(period = :all_time)
      earnings = case period
      when :last_30_days
        referral_earnings.joins(:referral_shop)
                        .where(referral_shops: { approved: true })
                        .where(earning_date: 30.days.ago.to_date..Date.current)
      when :current_month
        referral_earnings.joins(:referral_shop)
                        .where(referral_shops: { approved: true })
                        .where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
      else
        referral_earnings.joins(:referral_shop).where(referral_shops: { approved: true })
      end
      
      earnings.sum(:commission_amount)
    end
    
    def commission_breakdown(period = :all_time)
      earnings = case period
      when :last_30_days
        referral_earnings.joins(:referral_shop)
                        .where(referral_shops: { approved: true })
                        .where(earning_date: 30.days.ago.to_date..Date.current)
      when :current_month
        referral_earnings.joins(:referral_shop)
                        .where(referral_shops: { approved: true })
                        .where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
      else
        referral_earnings.joins(:referral_shop).where(referral_shops: { approved: true })
      end
      
      earnings.group(:transaction_type).sum(:commission_amount)
    end
    
    def active_approved_shops_count
      referral_shops.active.approved.count
    end
    
    def pending_approval_shops_count
      referral_shops.active.pending_approval.count
    end
    
    def has_account_details?
      account_type.present? && (has_bank_details? || has_paypal_details?)
    end
    
    def has_bank_details?
      account_type == 'bank' && bank_account_number.present? && bank_ifsc_code.present?
    end
    
    def has_paypal_details?
      account_type == 'paypal' && paypal_email.present?
    end
    
    def total_unpaid_earnings
        referral_earnings.where(payout_status: 'unpaid').sum(:commission_amount)
      end
    
      def total_paid_earnings
        referral_earnings.where(payout_status: 'paid').sum(:commission_amount)
      end
    
      def total_lifetime_earnings
        referral_earnings.sum(:commission_amount)
      end
    
      def last_payout
        payouts.where(status: 'completed').order(:earnings_to_date).last
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

    def assign_referral_code
      return if referral_code.present?

      20.times do
        candidate = "REF#{SecureRandom.alphanumeric(8).upcase}"
        unless ReferralPartner.exists?(referral_code: candidate)
          self.referral_code = candidate
          return
        end
      end

      errors.add(:referral_code, "could not be generated")
      throw :abort
    end

    def account_details_summary
      return "No account details" unless has_account_details?
      
      case account_type
      when 'bank'
        "Bank: #{bank_name} (****#{bank_account_number.last(4)})"
      when 'paypal'
        "PayPal: #{paypal_email}"
      end
    end
  end
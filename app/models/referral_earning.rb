# app/models/referral_earning.rb
class ReferralEarning < ApplicationRecord
  belongs_to :referral_partner
  belongs_to :referral_shop

  belongs_to :payout, optional: true


  has_many :payout_earnings, dependent: :destroy
  has_many :payouts, through: :payout_earnings
    
  # FIXED: Make transaction_type validation less strict during updates
  validates :transaction_type, presence: true, on: :create
  validates :revenue_amount, :commission_rate, :commission_amount, presence: true, 
            numericality: { greater_than: 0 }
  validates :earning_date, presence: true
  validates :shopify_transaction_id, uniqueness: true, allow_nil: true
  validates :payout_status, presence: true

  
  # FIXED: Updated enum syntax for Rails 8 compatibility
  enum :payout_status, {
    unpaid: 0,
    pending_payout: 1,
    paid: 2
  }
  
  enum :transaction_type, {
    subscription: 0,
    usage: 1,
    onetime: 2
  }
  
  # Scopes
  scope :recent, -> { order(earning_date: :desc, created_at: :desc) }
  scope :for_period, ->(start_date, end_date) { where(earning_date: start_date..end_date) }
  scope :by_type, ->(type) { where(transaction_type: type) }
  scope :by_partner, ->(partner_id) { where(referral_partner_id: partner_id) }
  scope :this_month, -> { where(earning_date: Date.current.beginning_of_month..Date.current.end_of_month) }
  scope :last_month, -> { where(earning_date: 1.month.ago.beginning_of_month..1.month.ago.end_of_month) }
  
  # Fixed scope with proper nil handling
  scope :by_date_range, ->(from_date, to_date) { 
    return all if from_date.blank? && to_date.blank?
    return where('earning_date <= ?', to_date) if from_date.blank?
    return where('earning_date >= ?', from_date) if to_date.blank?
    where(earning_date: from_date..to_date) 
  }
  
  scope :by_transaction_type, ->(type) { where(transaction_type: type) }

  # Class methods for calculations
  def self.breakdown_by_type_for_partner(partner_id)
    partner_earnings = where(referral_partner_id: partner_id)
    {
      'subscription' => partner_earnings.where(transaction_type: 'subscription').sum(:commission_amount),
      'usage' => partner_earnings.where(transaction_type: 'usage').sum(:commission_amount),
      'onetime' => partner_earnings.where(transaction_type: 'onetime').sum(:commission_amount)
    }
  end

  def self.breakdown_by_shop_for_partner(partner_id)
    breakdown = {}
    includes(:referral_shop)
      .where(referral_partner_id: partner_id)
      .each do |earning|
        shop_domain = earning.referral_shop.shop_domain
        breakdown[shop_domain] ||= 0
        breakdown[shop_domain] += earning.commission_amount
      end
    breakdown
  end

  def self.pending_payout_amount(partner_id = nil)
    scope = unpaid
    scope = scope.by_partner(partner_id) if partner_id
    scope.sum(:commission_amount)
  end

  def self.total_for_partner(partner_id, period = :all_time)
    earnings = case period
    when :last_30_days
      where(referral_partner_id: partner_id, earning_date: 30.days.ago.to_date..Date.current)
    when :current_month
      where(referral_partner_id: partner_id, 
            earning_date: Date.current.beginning_of_month..Date.current.end_of_month)
    else
      where(referral_partner_id: partner_id)
    end
    
    earnings.sum(:commission_amount)
  end

  def self.earnings_summary_for_partner(partner_id)
    partner_earnings = where(referral_partner_id: partner_id)
    
    {
      total_unpaid: partner_earnings.unpaid.sum(:commission_amount),
      total_paid: partner_earnings.paid.sum(:commission_amount),
      this_month: partner_earnings.this_month.sum(:commission_amount),
      last_month: partner_earnings.last_month.sum(:commission_amount),
      total_earnings: partner_earnings.sum(:commission_amount)
    }
  end

  # Instance methods
  def paid?
    payout_status == 'paid'
  end
  
  def unpaid?
    payout_status == 'unpaid'
  end
  
  def pending_payout?
    payout_status == 'pending_payout'
  end
  
  def mark_as_paid!(payout = nil)
    update!(payout_status: :paid)
    if payout
      payout.add_earning(self)
    end
  end
  
  def mark_as_pending_payout!
    update!(payout_status: :pending_payout)
  end

  def mark_as_unpaid!
    update!(payout_status: :unpaid)
  end
end
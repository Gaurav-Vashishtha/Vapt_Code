# app/models/payout_earning.rb
class PayoutEarning < ApplicationRecord
  belongs_to :payout
  belongs_to :referral_earning

  validates :payout_id, uniqueness: { scope: :referral_earning_id }

  # FIXED: Remove automatic callbacks that cause validation issues
  # The PayoutService will handle status updates manually
  
  # Optional: Add these callbacks back if needed, but with better error handling
  # after_create :mark_earning_as_pending_payout
  # after_destroy :mark_earning_as_unpaid

  private

  def mark_earning_as_pending_payout
    # Use update_column to bypass validations during the transaction
    referral_earning.update_column(:payout_status, 1) # 1 = pending_payout
  rescue => e
    Rails.logger.error "Failed to mark earning as pending payout: #{e.message}"
  end

  def mark_earning_as_unpaid
    if referral_earning.present?
      referral_earning.update_column(:payout_status, 0) # 0 = unpaid
    end
  rescue => e
    Rails.logger.error "Failed to mark earning as unpaid: #{e.message}"
  end
end
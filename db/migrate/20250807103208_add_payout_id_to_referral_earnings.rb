class AddPayoutIdToReferralEarnings < ActiveRecord::Migration[7.0]
  def change
    add_column :referral_earnings, :payout_id, :integer
    add_index :referral_earnings, :payout_id
    add_foreign_key :referral_earnings, :payouts, on_delete: :nullify
  end
end
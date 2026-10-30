class AddApprovalToReferralShops < ActiveRecord::Migration[7.0]
  def change
    add_column :referral_shops, :approved, :boolean, default: false
    add_column :referral_shops, :approved_at, :datetime
    add_column :referral_shops, :approved_by, :string
    add_column :referral_shops, :rejection_reason, :text
    
    add_index :referral_shops, :approved
  end
end
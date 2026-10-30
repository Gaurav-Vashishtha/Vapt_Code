class AddAccountDetailsToReferralPartners < ActiveRecord::Migration[7.0]
  def change
    # Account type: 'bank' or 'paypal'
    add_column :referral_partners, :account_type, :string
    
    # Bank account details (for Indian accounts)
    add_column :referral_partners, :bank_account_number, :string
    add_column :referral_partners, :bank_ifsc_code, :string
    add_column :referral_partners, :bank_account_name, :string
    add_column :referral_partners, :bank_name, :string
    
    # PayPal account details
    add_column :referral_partners, :paypal_email, :string
    
    # Additional details
    add_column :referral_partners, :account_verified, :boolean, default: false
    add_column :referral_partners, :account_verified_at, :datetime
    
    add_index :referral_partners, :account_type
    add_index :referral_partners, :account_verified
  end
end
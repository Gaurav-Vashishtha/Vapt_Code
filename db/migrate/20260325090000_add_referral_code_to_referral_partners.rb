class AddReferralCodeToReferralPartners < ActiveRecord::Migration[7.0]
  def change
    add_column :referral_partners, :referral_code, :string
    add_index :referral_partners, :referral_code, unique: true
  end
end

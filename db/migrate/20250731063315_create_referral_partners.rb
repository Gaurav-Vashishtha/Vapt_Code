class CreateReferralPartners < ActiveRecord::Migration[7.0]
  def change
    create_table :referral_partners do |t|
      t.string :name, null: false
      t.string :email, null: false, index: { unique: true }
      t.string :password_digest, null: false
      t.decimal :subscription_commission_rate, precision: 5, scale: 2, default: 0.0
      t.decimal :usage_commission_rate, precision: 5, scale: 2, default: 0.0
      t.decimal :onetime_commission_rate, precision: 5, scale: 2, default: 0.0
      t.boolean :active, default: true
      t.text :notes
      t.timestamps
    end
  end
end

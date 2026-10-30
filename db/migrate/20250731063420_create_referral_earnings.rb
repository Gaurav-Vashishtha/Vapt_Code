class CreateReferralEarnings < ActiveRecord::Migration[7.0]
  def change
    create_table :referral_earnings do |t|
      t.references :referral_partner, null: false, foreign_key: true
      t.references :referral_shop, null: false, foreign_key: true
      t.string :transaction_type, null: false # subscription, usage, onetime
      t.decimal :revenue_amount, precision: 10, scale: 2, null: false
      t.decimal :commission_rate, precision: 5, scale: 2, null: false
      t.decimal :commission_amount, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD'
      t.string :shopify_transaction_id
      t.date :earning_date, null: false
      t.datetime :processed_at, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps

      t.index [:referral_partner_id, :earning_date]
      t.index [:referral_shop_id, :earning_date]
      t.index :shopify_transaction_id, unique: true
    end
  end
end
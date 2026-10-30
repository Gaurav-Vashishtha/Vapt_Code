class CreatePayoutTables < ActiveRecord::Migration[7.0]
  def change
    # Create payouts table
    create_table "payouts", force: :cascade do |t|
      t.bigint "referral_partner_id", null: false
      t.decimal "total_amount", precision: 10, scale: 2, null: false
      t.string "currency", default: "USD", null: false
      t.string "status", default: "pending", null: false # pending, processing, completed, failed
      t.string "payment_method", null: false # bank_transfer, paypal
      t.text "payment_details" # JSON with bank/paypal details
      t.date "payout_date", null: false
      t.date "earnings_from_date", null: false
      t.date "earnings_to_date", null: false
      t.text "notes"
      t.string "transaction_reference"
      t.string "created_by" # admin user who initiated payout
      t.datetime "processed_at"
      t.datetime "completed_at"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      
      t.index ["referral_partner_id"], name: "index_payouts_on_referral_partner_id"
      t.index ["status"], name: "index_payouts_on_status"
      t.index ["payout_date"], name: "index_payouts_on_payout_date"
      t.index ["earnings_from_date", "earnings_to_date"], name: "index_payouts_on_earnings_date_range"
    end

    # Create payout_earnings junction table
    create_table "payout_earnings", force: :cascade do |t|
      t.bigint "payout_id", null: false
      t.bigint "referral_earning_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      
      t.index ["payout_id"], name: "index_payout_earnings_on_payout_id"
      t.index ["referral_earning_id"], name: "index_payout_earnings_on_referral_earning_id"
      t.index ["payout_id", "referral_earning_id"], name: "index_payout_earnings_unique", unique: true
    end

    # Add payout status to referral_earnings
    add_column :referral_earnings, :payout_status, :string, default: "unpaid", null: false
    add_index :referral_earnings, :payout_status, name: "index_referral_earnings_on_payout_status"

    # Add historical sync tracking to referral_shops
    add_column :referral_shops, :historical_sync_completed, :boolean, default: false
    add_column :referral_shops, :historical_sync_from_date, :date
    add_column :referral_shops, :last_sync_date, :date
    add_index :referral_shops, :historical_sync_completed, name: "index_referral_shops_on_historical_sync_completed"

    # Add foreign keys
    add_foreign_key "payouts", "referral_partners"
    add_foreign_key "payout_earnings", "payouts"
    add_foreign_key "payout_earnings", "referral_earnings"
  end

  def down
    drop_table "payout_earnings"
    drop_table "payouts"
    remove_column :referral_earnings, :payout_status
    remove_column :referral_shops, :historical_sync_completed
    remove_column :referral_shops, :historical_sync_from_date
    remove_column :referral_shops, :last_sync_date
  end
end
class CreateReferralShops < ActiveRecord::Migration[7.0]
  def change
    create_table :referral_shops do |t|
      t.references :referral_partner, null: false, foreign_key: true
      t.string :shop_domain, null: false
      t.string :shopify_shop_id
      t.boolean :active, default: true
      t.datetime :first_revenue_at
      t.decimal :total_lifetime_revenue, precision: 10, scale: 2, default: 0.0
      t.text :notes
      t.timestamps

      t.index [:referral_partner_id, :shop_domain], unique: true
    end
  end
end
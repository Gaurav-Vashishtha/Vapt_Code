# frozen_string_literal: true

# Country-wise plan offers: a different price and/or free trial for one plan in one country
# (e.g. Egypt founding merchants: Enterprise free for 90 days, first 25 stores). Read by
# PlansController#upgrade (the Shopify charge) and the plan cards. Managed at /admin/country_plan_offers.
class CreateCountryPlanOffers < ActiveRecord::Migration[7.2]
  def change
    create_table :country_plan_offers do |t|
      t.string :name, null: false                 # internal label, e.g. "EG founding merchants"
      t.string :country_code, null: false         # ISO-2, e.g. "EG"
      t.string :plan_name, null: false            # Plan.name, e.g. "Enterprise"
      t.decimal :price_usd, precision: 10, scale: 2 # monthly price charged instead of the plan's; nil = plan price
      t.integer :trial_days                       # free days before Shopify starts billing; nil = none
      t.integer :max_redemptions                  # nil = unlimited
      t.integer :redemptions_count, null: false, default: 0
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :active, null: false, default: false
      t.string :badge                             # short text on the plan card, e.g. "عرض المؤسسين"
      t.text :note
      t.timestamps
    end
    add_index :country_plan_offers, %i[country_code plan_name active]

    create_table :country_plan_offer_redemptions do |t|
      t.references :country_plan_offer, null: false, foreign_key: true
      t.bigint :shop_id, null: false
      t.string :charge_id                         # Shopify recurring charge created with the offer
      t.string :status, null: false, default: "pending" # pending -> activated
      t.datetime :activated_at
      t.timestamps
    end
    add_index :country_plan_offer_redemptions, %i[country_plan_offer_id shop_id], unique: true,
              name: "index_country_offer_redemptions_on_offer_and_shop"
    add_index :country_plan_offer_redemptions, :charge_id
  end
end

# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.5): quantity offers, bumps, upsells, downsells, threshold offers.
class CreateCodOffers < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_offers, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :offer_type, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.integer :priority, null: false, default: 0
      t.jsonb :targeting, null: false, default: {}
      t.jsonb :config, null: false, default: {}
      t.bigint :ab_test_id
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps null: false
    end

    add_index :cod_offers, %i[shop_id offer_type status priority],
              name: "index_cod_offers_on_shop_type_status_priority", if_not_exists: true
    add_index :cod_offers, :ab_test_id,
              name: "index_cod_offers_on_ab_test_id", if_not_exists: true
  end
end

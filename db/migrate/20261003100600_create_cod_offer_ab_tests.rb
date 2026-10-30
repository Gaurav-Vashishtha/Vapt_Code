# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.6): A/B tests between offers of one type.
class CreateCodOfferAbTests < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_offer_ab_tests, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :name, null: false
      t.string :offer_type, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :variants, null: false, default: []
      t.datetime :started_at
      t.datetime :stopped_at
      t.string :winner_key
      t.timestamps null: false
    end

    add_index :cod_offer_ab_tests, %i[shop_id status],
              name: "index_cod_offer_ab_tests_on_shop_id_and_status", if_not_exists: true
  end
end

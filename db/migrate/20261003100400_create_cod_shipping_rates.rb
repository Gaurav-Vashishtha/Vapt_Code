# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.4): merchant-defined shipping rates for form orders.
class CreateCodShippingRates < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_shipping_rates, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :name, null: false
      t.string :description
      t.bigint :price_cents, null: false, default: 0
      t.string :currency
      t.jsonb :conditions, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :source, null: false, default: "manual"
      t.timestamps null: false
    end

    add_index :cod_shipping_rates, %i[shop_id active position],
              name: "index_cod_shipping_rates_on_shop_id_and_active_and_position", if_not_exists: true
  end
end

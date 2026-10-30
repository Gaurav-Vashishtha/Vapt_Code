# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.3): button preset and styling, one row per shop.
class CreateCodButtonConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_button_configs, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :preset, null: false, default: "B"
      t.jsonb :config, null: false, default: {}
      t.timestamps null: false
    end

    add_index :cod_button_configs, :shop_id, unique: true,
              name: "index_cod_button_configs_on_shop_id", if_not_exists: true
  end
end

# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.1): one row per shop, created lazily by CodForm::ShopConfig.for(shop).
class CreateCodFormShopConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_shop_configs, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :storefront_mode, null: false, default: "legacy"
      t.string :module_access, null: false, default: "default"
      t.datetime :enabled_at
      t.jsonb :general, null: false, default: {}
      t.jsonb :fraud, null: false, default: {}
      t.jsonb :setup_state, null: false, default: {}
      t.jsonb :feature_overrides, null: false, default: {}
      t.jsonb :allowed_origins, null: false, default: []
      t.string :preview_token
      t.integer :config_version, null: false, default: 0
      t.integer :metafield_synced_version, null: false, default: 0
      t.datetime :metafield_synced_at
      t.string :asset_base
      t.timestamps null: false
    end

    add_index :cod_form_shop_configs, :shop_id, unique: true,
              name: "index_cod_form_shop_configs_on_shop_id", if_not_exists: true
    add_index :cod_form_shop_configs, :storefront_mode,
              name: "index_cod_form_shop_configs_on_storefront_mode", if_not_exists: true
  end
end

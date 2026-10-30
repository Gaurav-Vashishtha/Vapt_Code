# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.2): form definitions (draft + published config).
class CreateCodForms < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_forms, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :name, null: false, default: "Default form"
      t.boolean :is_default, null: false, default: false
      t.string :status, null: false, default: "active"
      t.integer :position, null: false, default: 0
      t.jsonb :targeting, null: false, default: {}
      t.string :template_key
      t.jsonb :draft_config, null: false, default: {}
      t.jsonb :published_config, null: false, default: {}
      t.integer :published_version, null: false, default: 0
      t.datetime :published_at
      t.timestamps null: false
    end

    add_index :cod_forms, %i[shop_id status position],
              name: "index_cod_forms_on_shop_id_and_status_and_position", if_not_exists: true
    add_index :cod_forms, :shop_id, unique: true, where: "is_default",
              name: "index_cod_forms_one_default", if_not_exists: true
  end
end

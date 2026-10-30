# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.7): phone / email / IP block list.
class CreateCodBlockEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_block_entries, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :kind, null: false
      t.string :value, null: false
      t.string :value_normalized, null: false
      t.string :note
      t.string :created_by
      t.timestamps null: false
    end

    add_index :cod_block_entries, %i[shop_id kind value_normalized], unique: true,
              name: "index_cod_block_entries_on_shop_kind_value", if_not_exists: true
  end
end

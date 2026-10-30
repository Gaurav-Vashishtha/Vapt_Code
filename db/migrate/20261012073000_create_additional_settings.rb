# frozen_string_literal: true

class CreateAdditionalSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :additional_settings, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.jsonb :third_party_payment_method_rules, default: {}, null: false
      t.timestamps
    end
    add_index :additional_settings, :shop_id, unique: true, if_not_exists: true
  end
end

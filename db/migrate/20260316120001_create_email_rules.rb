# frozen_string_literal: true

class CreateEmailRules < ActiveRecord::Migration[7.0]
  def change
    create_table :email_rules do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.references :email_template, null: false, foreign_key: true
      t.string :date_rule_type, null: false  # e.g. "days_after_installation"
      t.integer :date_rule_value, null: false  # e.g. 3 for 3 days
      t.json :conditions, default: []  # [{ "table"=>"settings", "column"=>"enable_pre_order_otp", "op"=>"eq", "value"=>false }]
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :email_rules, :slug, unique: true
    add_index :email_rules, :active
  end
end

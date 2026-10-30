# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.13): named groups of countries used by plan_limits overrides.
class CreateCodFormCountryGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_country_groups, if_not_exists: true do |t|
      t.string :name, null: false
      t.jsonb :country_codes, null: false, default: []
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps null: false
    end
  end
end

# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.14, J.1): minimum plan tier per feature key.
class CreateFeatureGates < ActiveRecord::Migration[7.2]
  def change
    create_table :feature_gates, if_not_exists: true do |t|
      t.string :feature_key, null: false
      t.string :min_tier, null: false, default: "free"
      t.boolean :enabled, null: false, default: true
      t.string :description
      t.timestamps null: false
    end

    add_index :feature_gates, :feature_key, unique: true,
              name: "index_feature_gates_on_feature_key", if_not_exists: true
  end
end

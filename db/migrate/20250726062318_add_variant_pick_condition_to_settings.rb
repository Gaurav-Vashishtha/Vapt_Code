class AddVariantPickConditionToSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :settings, :variant_pick_condition, :integer, default:0
  end
end
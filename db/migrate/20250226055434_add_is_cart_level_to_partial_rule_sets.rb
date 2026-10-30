class AddIsCartLevelToPartialRuleSets < ActiveRecord::Migration[6.0]
  def change
    add_column :partial_rule_sets, :is_cart_rule, :boolean, default:false
  end
end

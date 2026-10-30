class AddRuleRangePartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :min_cart_range, :decimal, default:0.0
    add_column :partial_rule_sets, :max_cart_range, :decimal, default:0.0
  end
end

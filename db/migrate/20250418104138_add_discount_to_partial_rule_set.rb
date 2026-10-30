class AddDiscountToPartialRuleSet < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :discount_code, :string, default: ''
    add_column :partial_rule_sets, :discount_value, :decimal, default: 0.0
    add_column :partial_rule_sets, :discount_type, :string, default: 'fixed'
  end
end

# frozen_string_literal: true

# NULL means "no shipping charge configured for this option" — the popup then
# shows nothing. A number is an explicit merchant-set charge.
class MakeShippingChargeNullableOnPartialRuleSets < ActiveRecord::Migration[7.2]
  def up
    change_column_null :partial_rule_sets, :shipping_charge, true
    change_column_default :partial_rule_sets, :shipping_charge, from: 0, to: nil
    execute "UPDATE partial_rule_sets SET shipping_charge = NULL WHERE shipping_charge = 0"
  end

  def down
    execute "UPDATE partial_rule_sets SET shipping_charge = 0 WHERE shipping_charge IS NULL"
    change_column_default :partial_rule_sets, :shipping_charge, from: nil, to: 0
    change_column_null :partial_rule_sets, :shipping_charge, false
  end
end

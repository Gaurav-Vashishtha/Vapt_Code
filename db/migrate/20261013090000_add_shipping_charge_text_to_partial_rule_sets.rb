class AddShippingChargeTextToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :shipping_charge_text, :string, default: nil
  end
end

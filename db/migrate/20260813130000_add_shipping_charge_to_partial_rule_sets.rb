# frozen_string_literal: true

class AddShippingChargeToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :shipping_charge, :decimal, default: 0, null: false
  end
end

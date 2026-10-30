# frozen_string_literal: true

class AddRepeatCustomerFieldsToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    # Both stay NULL until a merchant configures them; no defaults.
    add_column :partial_rule_sets, :repeat_customer_discount, :jsonb
    add_column :partial_rule_sets, :cod_cooling_period, :jsonb
  end
end

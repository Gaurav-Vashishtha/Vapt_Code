# frozen_string_literal: true

# Per-rule cart item count gate: { "min_cart_items" => 2, "max_cart_items" => 5 }.
# NULL means "not configured", so existing rules never wait on cart.js for it.
class AddCartItemsRangeToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :cart_items_range, :jsonb
  end
end

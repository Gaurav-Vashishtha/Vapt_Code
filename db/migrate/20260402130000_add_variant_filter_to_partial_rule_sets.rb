class AddVariantFilterToPartialRuleSets < ActiveRecord::Migration[7.0]
  def change
    add_column :partial_rule_sets, :variant_scope, :string, default: "all", null: false
    add_column :partial_rule_sets, :variant_ids, :string, array: true, default: [], null: false
  end
end

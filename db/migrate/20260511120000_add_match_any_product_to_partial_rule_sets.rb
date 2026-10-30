class AddMatchAnyProductToPartialRuleSets < ActiveRecord::Migration[7.0]
  def change
    return if column_exists?(:partial_rule_sets, :match_any_product)

    add_column :partial_rule_sets, :match_any_product, :boolean, default: false, null: false
  end
end

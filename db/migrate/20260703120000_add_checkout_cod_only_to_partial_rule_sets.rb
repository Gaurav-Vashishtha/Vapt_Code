class AddCheckoutCodOnlyToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :checkout_cod_only, :boolean, default: false, null: false, if_not_exists: true
  end
end

# frozen_string_literal: true

class AddProductScopeToPartialRuleSets < ActiveRecord::Migration[7.2]
  def up
    add_column :partial_rule_sets, :product_scope, :string, default: "all", null: false
    # Backfill: is_all true -> 'all', is_all false -> 'include'
    execute <<-SQL.squish
      UPDATE partial_rule_sets
      SET product_scope = CASE WHEN is_all = true THEN 'all' ELSE 'include' END
    SQL
  end

  def down
    remove_column :partial_rule_sets, :product_scope
  end
end

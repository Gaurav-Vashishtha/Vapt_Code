class AddCollectionFieldsToPartialRuleSets < ActiveRecord::Migration[7.0]
  def change
    return if column_exists?(:partial_rule_sets, :collection_scope) && column_exists?(:partial_rule_sets, :collection_ids)

    add_column :partial_rule_sets, :collection_scope, :string, default: 'all', null: false unless column_exists?(:partial_rule_sets, :collection_scope)
    add_column :partial_rule_sets, :collection_ids, :string, array: true, default: [], null: false unless column_exists?(:partial_rule_sets, :collection_ids)
  end
end

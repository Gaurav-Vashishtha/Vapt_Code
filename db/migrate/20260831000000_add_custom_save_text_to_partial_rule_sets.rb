class AddCustomSaveTextToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :custom_save_text, :string
  end
end

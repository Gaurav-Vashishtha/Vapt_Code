class AddZipcodeBlacklistToPartialRuleSets < ActiveRecord::Migration[7.0]
  def change
    add_column :partial_rule_sets, :zipcode_blacklist_enabled, :boolean, default: false, null: false
    add_column :partial_rule_sets, :zipcode_blacklist, :text, default: "", null: false
  end
end

# frozen_string_literal: true

class AddZipcodeWhitelistToPartialRuleSets < ActiveRecord::Migration[7.2]
  def up
    unless column_exists?(:partial_rule_sets, :zipcode_whitelist_enabled)
      add_column :partial_rule_sets, :zipcode_whitelist_enabled, :boolean, default: false, null: false
    end
    unless column_exists?(:partial_rule_sets, :zipcode_whitelist)
      add_column :partial_rule_sets, :zipcode_whitelist, :text, default: "", null: false
    end
  end

  def down
    remove_column :partial_rule_sets, :zipcode_whitelist if column_exists?(:partial_rule_sets, :zipcode_whitelist)
    remove_column :partial_rule_sets, :zipcode_whitelist_enabled if column_exists?(:partial_rule_sets, :zipcode_whitelist_enabled)
  end
end

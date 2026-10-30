# frozen_string_literal: true

class AddPreV2NoRuleQualifiedMessageToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :pre_v2_no_rule_qualified_message, :string, default: "", null: false
  end
end

# frozen_string_literal: true

class AddDateRuleColumnToEmailRules < ActiveRecord::Migration[7.0]
  def change
    add_column :email_rules, :date_rule_column, :string
  end
end

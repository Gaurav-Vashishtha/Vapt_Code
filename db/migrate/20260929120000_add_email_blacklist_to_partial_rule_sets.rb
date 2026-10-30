# frozen_string_literal: true

class AddEmailBlacklistToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :email_blacklist, :jsonb
  end
end

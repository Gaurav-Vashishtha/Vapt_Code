# frozen_string_literal: true

class AddPhoneBlacklistToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :phone_blacklist, :jsonb
  end
end

# frozen_string_literal: true

class AddDescriptionTemplateToPartialRuleSets < ActiveRecord::Migration[7.0]
  def change
    add_column :partial_rule_sets, :description_template, :string, default: ""
  end
end

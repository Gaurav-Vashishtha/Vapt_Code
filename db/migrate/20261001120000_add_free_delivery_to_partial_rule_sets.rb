# frozen_string_literal: true

class AddFreeDeliveryToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :free_delivery, :boolean
  end
end

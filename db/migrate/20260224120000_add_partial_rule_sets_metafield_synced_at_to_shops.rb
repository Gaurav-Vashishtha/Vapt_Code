# frozen_string_literal: true

class AddPartialRuleSetsMetafieldSyncedAtToShops < ActiveRecord::Migration[7.2]
  def change
    add_column :shops, :partial_rule_sets_metafield_synced_at, :datetime
  end
end

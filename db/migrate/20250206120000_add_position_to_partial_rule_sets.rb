# frozen_string_literal: true

class AddPositionToPartialRuleSets < ActiveRecord::Migration[7.0]
  def up
    add_column :partial_rule_sets, :position, :integer, default: 0, null: false
    add_index :partial_rule_sets, [:shop_id, :position]

    # Backfill positions for existing records (order by id within each shop)
    execute <<-SQL.squish
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY shop_id ORDER BY id) - 1 AS pos
        FROM partial_rule_sets
      )
      UPDATE partial_rule_sets SET position = ranked.pos
      FROM ranked WHERE partial_rule_sets.id = ranked.id
    SQL
  end

  def down
    remove_index :partial_rule_sets, [:shop_id, :position], if_exists: true
    remove_column :partial_rule_sets, :position
  end
end

# frozen_string_literal: true

# Per-rule RTO gate. NULL means "not configured" so every existing rule keeps
# its current behaviour; the engine only ever runs for rules that opt in.
class AddRtoEngineToPartialRuleSets < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_rule_sets, :rto_engine, :jsonb, default: nil
  end
end

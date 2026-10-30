# frozen_string_literal: true

# Precomputed risk fields on the RTO aggregate tables. The decision engine
# computes scores inline from counts (cheap), but persisting the smoothed rate
# and weighted log-odds contribution lets dashboards sort/segment by risk
# (e.g. "riskiest pincodes") without recomputing, and is the hook for an even
# faster read path later (read two floats instead of smoothing per request).
class AddRtoScoringColumns < ActiveRecord::Migration[7.2]
  def change
    add_column :global_customer_stats, :smoothed_rto_rate, :float
    add_column :global_customer_stats, :rto_logit_contribution, :float, null: false, default: 0.0
    add_column :global_customer_stats, :score_computed_at, :datetime

    add_column :global_zip_stats, :smoothed_rto_rate, :float
    add_column :global_zip_stats, :rto_logit_contribution, :float, null: false, default: 0.0
    add_column :global_zip_stats, :score_computed_at, :datetime

    add_index :global_customer_stats, :rto_logit_contribution
    add_index :global_zip_stats, :rto_logit_contribution
  end
end

class CreateOnboardingEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :onboarding_events do |t|
      t.references :shop, null: false, foreign_key: { on_delete: :cascade }

      # Semantic funnel event, e.g. 'onboarding_started', 'features_selected',
      # 'test_sent', 'theme_embed_skipped', 'billing_started', 'billing_approved'.
      t.string   :event,    null: false
      t.integer  :step                                 # wizard step 1..4 (nullable)
      t.string   :feature,  default: "quick-onboarding-v2", null: false
      t.jsonb    :metadata, default: {}, null: false   # arbitrary context (selected features, durations…)
      t.datetime :occurred_at, null: false             # client-reported event time
      t.timestamps
    end

    # Funnel aggregation queries group by event over a recent window and count distinct shops.
    add_index :onboarding_events, [:event, :occurred_at]
    add_index :onboarding_events, [:shop_id, :occurred_at]
  end
end

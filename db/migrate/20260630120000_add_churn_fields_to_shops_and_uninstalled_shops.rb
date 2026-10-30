class AddChurnFieldsToShopsAndUninstalledShops < ActiveRecord::Migration[7.2]
  def change
    change_table :shops, bulk: true do |t|
      t.datetime :first_order_at
      t.datetime :last_order_at
      t.datetime :last_active_at
      t.datetime :onboarding_completed_at
      t.string   :acquisition_source
      t.integer  :churn_risk_score
      t.string   :churn_risk_band
      t.string   :churn_risk_primary_factor
      t.string   :churn_risk_action
      t.jsonb    :churn_risk_reasons, default: []
      t.datetime :churn_risk_computed_at
    end
    add_index :shops, :last_active_at
    add_index :shops, %i[churn_risk_band churn_risk_score]

    change_table :uninstalled_shops, bulk: true do |t|
      t.string   :uninstall_reason
      t.text     :uninstall_feedback
      t.string   :survey_token
      t.datetime :first_order_at
      t.datetime :last_order_at
      t.datetime :last_active_at
      t.string   :plan_name_at_uninstall
      t.integer  :tenure_days
      t.integer  :orders_last_30d
      t.integer  :churn_risk_at_uninstall
      t.string   :churn_risk_band_at_uninstall
    end
    add_index :uninstalled_shops, :survey_token, unique: true
  end
end

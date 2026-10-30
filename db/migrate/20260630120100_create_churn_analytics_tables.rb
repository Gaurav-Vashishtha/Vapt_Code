class CreateChurnAnalyticsTables < ActiveRecord::Migration[7.2]
  def change
    create_table :billing_events do |t|
      t.bigint   :shop_id
      t.string   :shopify_domain
      t.string   :event_type, null: false
      t.string   :old_plan
      t.string   :new_plan
      t.decimal  :amount, precision: 12, scale: 2
      t.string   :currency
      t.datetime :occurred_at, null: false
      t.string   :source
      t.string   :external_id
      t.jsonb    :metadata, default: {}
      t.timestamps
    end
    add_index :billing_events, :shop_id
    add_index :billing_events, :occurred_at
    add_index :billing_events, %i[event_type occurred_at]
    add_index :billing_events, :external_id

    create_table :partner_sales do |t|
      t.string   :shopify_domain
      t.string   :sale_type, null: false
      t.string   :charge_id
      t.decimal  :gross_amount, precision: 12, scale: 2
      t.decimal  :net_amount, precision: 12, scale: 2
      t.string   :currency
      t.datetime :occurred_at, null: false
      t.string   :external_id, null: false
      t.string   :app_name
      t.jsonb    :metadata, default: {}
      t.timestamps
    end
    add_index :partner_sales, :external_id, unique: true
    add_index :partner_sales, :shopify_domain
    add_index :partner_sales, %i[sale_type occurred_at]

    create_table :mrr_snapshots do |t|
      t.bigint   :shop_id
      t.string   :shopify_domain
      t.date     :snapshot_date, null: false
      t.string   :plan_name
      t.decimal  :plan_price, precision: 10, scale: 2, default: 0
      t.decimal  :usage_trailing_30d, precision: 12, scale: 2, default: 0
      t.decimal  :mrr, precision: 12, scale: 2, default: 0
      t.string   :currency
      t.timestamps
    end
    add_index :mrr_snapshots, %i[snapshot_date shop_id], unique: true
    add_index :mrr_snapshots, :snapshot_date

    create_table :shop_activity_dailies do |t|
      t.bigint   :shop_id, null: false
      t.date     :activity_date, null: false
      t.integer  :orders, default: 0
      t.integer  :sms_sent, default: 0
      t.integer  :whatsapp_sent, default: 0
      t.integer  :otp_completions, default: 0
      t.integer  :partial_payments, default: 0
      t.datetime :last_order_at
      t.timestamps
    end
    add_index :shop_activity_dailies, %i[shop_id activity_date], unique: true
    add_index :shop_activity_dailies, :activity_date

    create_table :feature_adoption_events do |t|
      t.bigint   :shop_id, null: false
      t.string   :feature_key, null: false
      t.datetime :first_enabled_at
      t.datetime :first_used_at
      t.timestamps
    end
    add_index :feature_adoption_events, %i[shop_id feature_key], unique: true

    create_table :settings_change_audits do |t|
      t.bigint   :shop_id
      t.string   :field, null: false
      t.string   :old_value
      t.string   :new_value
      t.datetime :changed_at, null: false
      t.string   :changed_by
      t.timestamps
    end
    add_index :settings_change_audits, %i[shop_id changed_at]
    add_index :settings_change_audits, %i[field changed_at]

    create_table :churn_risk_snapshots do |t|
      t.bigint   :shop_id, null: false
      t.string   :shopify_domain
      t.date     :snapshot_date, null: false
      t.integer  :score, default: 0
      t.string   :band
      t.string   :primary_factor
      t.string   :recommended_action
      t.jsonb    :reasons, default: []
      t.decimal  :mrr, precision: 12, scale: 2, default: 0
      t.timestamps
    end
    add_index :churn_risk_snapshots, %i[shop_id snapshot_date], unique: true
    add_index :churn_risk_snapshots, %i[snapshot_date band]

    create_table :win_back_outreaches do |t|
      t.bigint   :shop_id
      t.string   :shopify_domain
      t.string   :trigger, null: false
      t.string   :channel
      t.string   :status, default: 'pending'
      t.datetime :sent_at
      t.jsonb    :metadata, default: {}
      t.timestamps
    end
    add_index :win_back_outreaches, %i[shop_id trigger]
    add_index :win_back_outreaches, :shopify_domain
  end
end

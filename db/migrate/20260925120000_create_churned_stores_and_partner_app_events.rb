# Churn dashboard v2.
#
# * partner_app_events — raw Partner API app events (installs, uninstalls,
#   subscription activations/cancellations) for the COD King app. Source of
#   truth for "subscription cancelled / downgraded to Free" churn and for the
#   merchant's Shopify uninstall reason.
# * churned_stores     — one row per churn event (uninstall, subscription
#   cancelled, downgraded to Free) with Partner-API LTV and return metrics.
#   Rebuilt by Churn::ChurnedStoresSyncJob; safe to truncate and resync.
#
# Also relabels billing_events that PartnerSalesSyncJob wrongly wrote as
# 'cancelled' (it mapped every negative subscription sale — i.e. refunds — to
# a cancellation, inflating the MRR waterfall's churn figure).
#
# Only new tables + an UPDATE on a small table, so no ACCESS EXCLUSIVE on hot
# tables. Every step is guarded, so a re-run in the release phase is a no-op.
class CreateChurnedStoresAndPartnerAppEvents < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    unless table_exists?(:partner_app_events)
      create_table :partner_app_events do |t|
        t.string :event_type, null: false
        t.string :shopify_domain, null: false
        t.string :shop_gid
        t.datetime :occurred_at, null: false
        t.string :charge_id
        t.string :charge_name
        t.decimal :charge_amount, precision: 12, scale: 2
        t.string :currency
        t.boolean :charge_test, default: false, null: false
        t.string :reason
        t.text :description
        t.string :external_key, null: false
        t.jsonb :metadata, default: {}, null: false
        t.timestamps
      end
    end
    add_index :partner_app_events, :external_key, unique: true unless index_exists?(:partner_app_events, :external_key)
    add_index :partner_app_events, %i[shopify_domain occurred_at] unless index_exists?(:partner_app_events, %i[shopify_domain occurred_at])
    add_index :partner_app_events, %i[event_type occurred_at] unless index_exists?(:partner_app_events, %i[event_type occurred_at])

    unless table_exists?(:churned_stores)
      create_table :churned_stores do |t|
        t.string :source_key, null: false
        t.string :churn_type, null: false # uninstalled | subscription_cancelled | downgraded_to_free
        t.string :shopify_domain, null: false
        t.datetime :churned_at, null: false
        t.bigint :uninstalled_shop_id
        t.bigint :shop_id

        # Store profile (from the uninstall snapshot, or the live shop for subscription churn)
        t.string :owner_name
        t.string :email
        t.string :phone
        t.string :country
        t.date :store_created_on
        t.datetime :installed_at
        t.integer :tenure_days
        t.integer :orders_processed
        t.jsonb :features, default: [], null: false
        t.string :plan_name
        t.decimal :plan_amount, precision: 12, scale: 2
        t.string :uninstall_reason
        t.text :uninstall_feedback

        # Revenue (Shopify Partner API, net of Shopify's share, USD)
        t.string :currency, default: 'USD'
        t.decimal :ltv_net, precision: 12, scale: 2, default: 0, null: false
        t.decimal :subscription_net, precision: 12, scale: 2, default: 0, null: false
        t.decimal :usage_net, precision: 12, scale: 2, default: 0, null: false
        t.decimal :adjustment_net, precision: 12, scale: 2, default: 0, null: false
        t.decimal :last_30d_net, precision: 12, scale: 2, default: 0, null: false
        t.datetime :first_charge_at
        t.datetime :last_charge_at

        # Came back (reinstalled after an uninstall / resubscribed after a cancellation)
        t.boolean :returned, default: false, null: false
        t.datetime :returned_at
        t.integer :return_gap_days
        t.boolean :still_installed, default: false, null: false
        t.string :current_plan_name
        t.integer :orders_since_return
        t.decimal :net_since_return, precision: 12, scale: 2, default: 0, null: false
        t.integer :prior_churn_count, default: 0, null: false

        t.datetime :partner_synced_at
        t.text :sync_error
        t.timestamps
      end
    end
    add_index :churned_stores, :source_key, unique: true unless index_exists?(:churned_stores, :source_key)
    add_index :churned_stores, :churned_at unless index_exists?(:churned_stores, :churned_at)
    add_index :churned_stores, %i[churn_type churned_at] unless index_exists?(:churned_stores, %i[churn_type churned_at])
    add_index :churned_stores, :shopify_domain unless index_exists?(:churned_stores, :shopify_domain)
    add_index :churned_stores, :ltv_net unless index_exists?(:churned_stores, :ltv_net)

    if table_exists?(:billing_events)
      execute <<~SQL
        UPDATE billing_events
           SET event_type = 'refund', updated_at = NOW()
         WHERE source = 'partner_api' AND event_type = 'cancelled'
      SQL
    end
  end

  def down
    drop_table :churned_stores if table_exists?(:churned_stores)
    drop_table :partner_app_events if table_exists?(:partner_app_events)
  end
end

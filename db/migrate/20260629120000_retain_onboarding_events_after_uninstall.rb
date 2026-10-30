class RetainOnboardingEventsAfterUninstall < ActiveRecord::Migration[7.2]
  def up
    # Denormalize the shop attributes the onboarding funnel needs, so events
    # survive the shop being destroyed on uninstall (the funnel can then count
    # by shopify_domain and read country/age from these columns, no shops join).
    add_column :onboarding_events, :shopify_domain, :string
    add_column :onboarding_events, :country_code, :string
    add_column :onboarding_events, :shop_created_date, :string

    # Backfill from shops for existing rows.
    execute <<~SQL.squish
      UPDATE onboarding_events oe
      SET shopify_domain = s.shopify_domain,
          country_code = s.country_code,
          shop_created_date = s.shop_created_date
      FROM shops s
      WHERE s.id = oe.shop_id
    SQL

    # Stop cascade-deleting events on shop destroy: null the FK and keep the row.
    # Requires shop_id to be nullable.
    change_column_null :onboarding_events, :shop_id, true
    remove_foreign_key :onboarding_events, :shops
    add_foreign_key :onboarding_events, :shops, on_delete: :nullify

    add_index :onboarding_events, [:event, :shopify_domain]
    add_index :onboarding_events, :country_code
  end

  def down
    remove_index :onboarding_events, :country_code
    remove_index :onboarding_events, [:event, :shopify_domain]
    remove_foreign_key :onboarding_events, :shops
    add_foreign_key :onboarding_events, :shops, on_delete: :cascade
    # Note: may fail if any rows already have a null shop_id (orphaned by an
    # uninstall) — clean those up first if rolling back.
    change_column_null :onboarding_events, :shop_id, false
    remove_column :onboarding_events, :shop_created_date
    remove_column :onboarding_events, :country_code
    remove_column :onboarding_events, :shopify_domain
  end
end

# Follow-ups on uninstalled stores used to force a placeholder `shops` row
# (shopify_token "uninstalled_<hex>") because FollowUp required a shop. That
# row fired Shop callbacks against a dead token, counted as a live/reinstalled
# store everywhere, and polluted churn metrics. Follow-ups can now hang off the
# uninstalled_shops snapshot instead.
#
# Also adds uninstalled_shops.feature_snapshot (jsonb) so UninstallNewJob can
# record the wider feature set (WhatsApp confirmation/fulfilment, COD form…)
# without a column per flag; an index on uninstalled_shops.shop_domain (the
# churn sync looks snapshots up by domain); and partner_sales.app_id so the
# churn revenue baseline only counts COD King (the org holds other apps, and
# older rows were synced without an app filter — they stay NULL and are ignored).
#
# Written per the heroku-release-migrations rule: per-statement guards,
# short lock_timeout + retries on every ACCESS EXCLUSIVE step, CONCURRENTLY
# for indexes, FK added NOT VALID.
class AddUninstalledShopToFollowUps < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'.freeze
  LOCK_ATTEMPTS = 12
  LOCK_BACKOFF_SECONDS = 10

  def up
    unless column_exists?(:follow_ups, :uninstalled_shop_id)
      with_lock_retries('add follow_ups.uninstalled_shop_id') do
        add_column :follow_ups, :uninstalled_shop_id, :bigint
      end
    end

    if shop_id_not_null?
      with_lock_retries('drop NOT NULL on follow_ups.shop_id') do
        change_column_null :follow_ups, :shop_id, true
      end
    end

    unless index_exists?(:follow_ups, :uninstalled_shop_id, name: 'index_follow_ups_on_uninstalled_shop_id')
      add_index :follow_ups, :uninstalled_shop_id,
                name: 'index_follow_ups_on_uninstalled_shop_id',
                algorithm: :concurrently
    end

    unless foreign_key_exists?(:follow_ups, :uninstalled_shops, column: :uninstalled_shop_id)
      with_lock_retries('add FK follow_ups -> uninstalled_shops') do
        add_foreign_key :follow_ups, :uninstalled_shops,
                        column: :uninstalled_shop_id, on_delete: :cascade, validate: false
      end
    end

    unless column_exists?(:uninstalled_shops, :feature_snapshot)
      with_lock_retries('add uninstalled_shops.feature_snapshot') do
        add_column :uninstalled_shops, :feature_snapshot, :jsonb, default: {}, null: false
      end
    end

    unless index_exists?(:uninstalled_shops, :shop_domain, name: 'index_uninstalled_shops_on_shop_domain')
      add_index :uninstalled_shops, :shop_domain,
                name: 'index_uninstalled_shops_on_shop_domain',
                algorithm: :concurrently
    end

    unless column_exists?(:partner_sales, :app_id)
      with_lock_retries('add partner_sales.app_id') do
        add_column :partner_sales, :app_id, :string
      end
    end

    unless index_exists?(:partner_sales, %i[app_id occurred_at], name: 'index_partner_sales_on_app_id_and_occurred_at')
      add_index :partner_sales, %i[app_id occurred_at],
                name: 'index_partner_sales_on_app_id_and_occurred_at',
                algorithm: :concurrently
    end
  ensure
    execute "SET lock_timeout = DEFAULT"
  end

  def down
    if index_exists?(:partner_sales, %i[app_id occurred_at], name: 'index_partner_sales_on_app_id_and_occurred_at')
      remove_index :partner_sales, name: 'index_partner_sales_on_app_id_and_occurred_at'
    end
    if column_exists?(:partner_sales, :app_id)
      with_lock_retries('remove partner_sales.app_id') do
        remove_column :partner_sales, :app_id
      end
    end
    if index_exists?(:uninstalled_shops, :shop_domain, name: 'index_uninstalled_shops_on_shop_domain')
      remove_index :uninstalled_shops, name: 'index_uninstalled_shops_on_shop_domain'
    end

    if column_exists?(:uninstalled_shops, :feature_snapshot)
      with_lock_retries('remove uninstalled_shops.feature_snapshot') do
        remove_column :uninstalled_shops, :feature_snapshot
      end
    end

    if foreign_key_exists?(:follow_ups, :uninstalled_shops, column: :uninstalled_shop_id)
      with_lock_retries('remove FK follow_ups -> uninstalled_shops') do
        remove_foreign_key :follow_ups, column: :uninstalled_shop_id
      end
    end

    if column_exists?(:follow_ups, :uninstalled_shop_id)
      with_lock_retries('remove follow_ups.uninstalled_shop_id') do
        remove_column :follow_ups, :uninstalled_shop_id
      end
    end
    # shop_id is intentionally left nullable: rows attached only to an
    # uninstalled_shop would violate NOT NULL.
  ensure
    execute "SET lock_timeout = DEFAULT"
  end

  private

  def shop_id_not_null?
    col = columns(:follow_ups).find { |c| c.name == 'shop_id' }
    col && !col.null
  end

  def with_lock_retries(label)
    attempt = 0
    begin
      attempt += 1
      execute "SET lock_timeout = '#{LOCK_TIMEOUT}'"
      yield
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled => e
      raise if attempt >= LOCK_ATTEMPTS

      say "#{label}: lock not available (attempt #{attempt}/#{LOCK_ATTEMPTS}) — #{e.class}; retrying in #{LOCK_BACKOFF_SECONDS}s", true
      sleep LOCK_BACKOFF_SECONDS
      retry
    ensure
      execute "SET lock_timeout = DEFAULT"
    end
  end
end

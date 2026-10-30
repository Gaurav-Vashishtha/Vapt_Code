class AddCustomBrandedClientToWhatsappTables < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TABLES = %i[whatsapp_accounts whatsapp_message_logs whatsapp_inbound_messages].freeze

  # Each ALTER needs ACCESS EXCLUSIVE on a hot table. We keep the lock wait
  # short so a queued ALTER never stalls every other query on the table, but
  # instead of dying on the first timeout (which is what killed the
  # 2026-09-03 release — a long-running query held the lock for >5s) we back
  # off and try again a few times. Every step is individually guarded, so a
  # re-run of the whole migration is a no-op for whatever already landed.
  LOCK_TIMEOUT = '5s'.freeze
  LOCK_ATTEMPTS = 12
  LOCK_BACKOFF_SECONDS = 10

  def up
    TABLES.each do |table|
      unless column_exists?(table, :custom_branded_client_id)
        with_lock_retries("add #{table}.custom_branded_client_id") do
          add_column table, :custom_branded_client_id, :bigint
        end
      end

      # Guarded separately from the add_column: a previous run may have added
      # the column and then timed out here, and the column_exists? guard alone
      # would have skipped this forever.
      if shop_id_not_null?(table)
        with_lock_retries("drop NOT NULL on #{table}.shop_id") do
          change_column_null table, :shop_id, true
        end
      end

      unless index_exists?(table, :custom_branded_client_id, name: "index_#{table}_on_cb_client_id")
        add_index table, :custom_branded_client_id,
                  name: "index_#{table}_on_cb_client_id",
                  algorithm: :concurrently
      end

      unless foreign_key_exists?(table, :custom_branded_clients, column: :custom_branded_client_id)
        # validate: false skips the full-table scan (whatsapp_message_logs is
        # large); every existing row has NULL here so validation is moot.
        with_lock_retries("add FK #{table} -> custom_branded_clients") do
          add_foreign_key table, :custom_branded_clients,
                          column: :custom_branded_client_id, validate: false
        end
      end
    end

    # Client-side twin of idx_whatsapp_logs_unique_per_send: that index keys on
    # shop_id, and Postgres treats NULLs as distinct, so it enforces nothing
    # for client-owned rows (shop_id NULL). This one gives API sends the same
    # DB-level idempotency on their idempotency_key (source_external_id).
    unless index_name_exists?(:whatsapp_message_logs, 'idx_whatsapp_logs_unique_per_send_cb')
      add_index :whatsapp_message_logs,
                %i[custom_branded_client_id event_type_key source_external_id stage_index],
                name: 'idx_whatsapp_logs_unique_per_send_cb',
                unique: true,
                where: 'custom_branded_client_id IS NOT NULL AND source_external_id IS NOT NULL AND status <> 4',
                algorithm: :concurrently
    end
  ensure
    execute "SET lock_timeout = DEFAULT"
  end

  def down
    if index_name_exists?(:whatsapp_message_logs, 'idx_whatsapp_logs_unique_per_send_cb')
      remove_index :whatsapp_message_logs, name: 'idx_whatsapp_logs_unique_per_send_cb'
    end

    TABLES.each do |table|
      next unless column_exists?(table, :custom_branded_client_id)

      with_lock_retries("remove #{table}.custom_branded_client_id") do
        remove_column table, :custom_branded_client_id
      end
      with_lock_retries("restore NOT NULL on #{table}.shop_id") do
        change_column_null table, :shop_id, false
      end
    end
  ensure
    execute "SET lock_timeout = DEFAULT"
  end

  private

  def shop_id_not_null?(table)
    col = columns(table).find { |c| c.name == 'shop_id' }
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

# frozen_string_literal: true

module MigrationLockRetries
  ATTEMPTS = Integer(ENV.fetch('MIGRATION_LOCK_ATTEMPTS', 10))
  LOCK_TIMEOUT = '3s'
  MAX_SLEEP = 10

  # ALTER/CREATE ... REFERENCES need an ACCESS EXCLUSIVE lock; while one waits,
  # Postgres queues every later query on that table behind it. Each attempt
  # therefore waits at most LOCK_TIMEOUT, then backs off so live traffic drains,
  # and retries — the deploy succeeds at the first quiet moment instead of
  # freezing the table or failing outright. Requires disable_ddl_transaction!.
  def invalid_index?(name)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{connection.quote(name)} AND NOT i.indisvalid
    SQL
  end

  def with_lock_retries(attempts: ATTEMPTS, lock_timeout: LOCK_TIMEOUT)
    return yield if reverting?

    attempt = 0
    begin
      attempt += 1
      transaction do
        execute("SET LOCAL lock_timeout = '#{lock_timeout}'")
        yield
      end
    rescue ActiveRecord::LockWaitTimeout => e
      raise if attempt >= attempts

      wait = [attempt, MAX_SLEEP].min
      say "lock busy (attempt #{attempt}/#{attempts}): #{e.message.lines.first&.strip}; retrying in #{wait}s"
      sleep(wait)
      retry
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.include(MigrationLockRetries)
end

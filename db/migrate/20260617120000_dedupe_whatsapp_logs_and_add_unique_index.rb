class DedupeWhatsappLogsAndAddUniqueIndex < ActiveRecord::Migration[7.2]
  # The application-level dedup check inside DispatchEventJob has a small
  # race window: when two Sidekiq processes pick up the same cron tick (or
  # two fan-out paths converge), both can pass the WhatsappMessageLog.exists?
  # check before either commits a log row. Both then enqueue
  # SendTemplateMessageJob → both make Meta API calls → two messages to the
  # customer with sequential meta_message_ids.
  #
  # This migration eliminates the race at the DB level: a partial unique
  # index on (shop_id, event_type_key, source_external_id, stage_index)
  # restricted to non-failed rows so that retries-after-failure still work.
  # SendTemplateMessageService rescues the resulting RecordNotUnique and
  # aborts without hitting Meta — the rare loser-of-the-race simply no-ops.

  # status = 4 is the `failed` enum value in WhatsappMessageLog.
  STATUS_FAILED = 4

  def up
    # 1) Collapse existing duplicates so the unique index can be created.
    # For each (shop, event, source_external_id, stage_index) tuple that
    # currently has >1 non-failed rows, keep the OLDEST row and delete the
    # rest. We pick "oldest" because it's typically the one that actually
    # delivered first; the later rows are the race-condition victims.
    cleanup_sql = <<~SQL
      DELETE FROM whatsapp_message_logs
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY shop_id, event_type_key, source_external_id, COALESCE(stage_index, 0)
                   ORDER BY id ASC
                 ) AS rn
          FROM whatsapp_message_logs
          WHERE source_external_id IS NOT NULL
            AND status != #{STATUS_FAILED}
        ) dup
        WHERE dup.rn > 1
      )
    SQL
    deleted = connection.execute(cleanup_sql).cmd_tuples
    say "Removed #{deleted} duplicate WhatsappMessageLog row(s) before adding unique index", true

    # 2) Add the partial unique index. NULLs in source_external_id are not
    # constrained (legacy logs and events with no stable source — e.g.
    # campaign_broadcast — continue to coexist without restriction).
    add_index :whatsapp_message_logs,
              [:shop_id, :event_type_key, :source_external_id, :stage_index],
              unique: true,
              where: "source_external_id IS NOT NULL AND status != #{STATUS_FAILED}",
              name: 'idx_whatsapp_logs_unique_per_send',
              algorithm: :concurrently
  end

  def down
    remove_index :whatsapp_message_logs, name: 'idx_whatsapp_logs_unique_per_send', algorithm: :concurrently
  end

  # add_index :concurrently can't run inside a transaction.
  disable_ddl_transaction!
end

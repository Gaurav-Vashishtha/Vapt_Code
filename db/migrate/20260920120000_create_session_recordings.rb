# frozen_string_literal: true

# rrweb session recordings for the first hours after install (onboarding +
# first session). Retention is short by design — AdminJobs::PurgeSessionRecordingsJob
# deletes anything older than SESSION_RECORDING_RETENTION_HOURS (default 48).
class CreateSessionRecordings < ActiveRecord::Migration[7.2]
  def change
    create_table :session_recordings do |t|
      # Deliberately no FK to shops: uninstall destroys the Shop row and the
      # recording must survive long enough to be watched (same trade-off
      # onboarding_events made). shopify_domain is what support searches by.
      t.bigint   :shop_id
      t.string   :shopify_domain, null: false
      t.string   :session_key,    null: false # client-generated, one per tab session

      t.datetime :started_at,    null: false
      t.datetime :last_event_at, null: false
      t.integer  :duration_ms,      default: 0, null: false
      t.integer  :event_count,      default: 0, null: false
      t.integer  :chunk_count,      default: 0, null: false
      t.bigint   :compressed_bytes, default: 0, null: false

      t.string   :entry_path
      t.string   :last_path
      t.string   :user_agent
      t.integer  :viewport_width
      t.integer  :viewport_height
      t.jsonb    :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :session_recordings, :session_key, unique: true
    add_index :session_recordings, %i[shopify_domain started_at]
    add_index :session_recordings, :started_at
    add_index :session_recordings, :last_event_at # purge job scans this

    create_table :session_recording_chunks do |t|
      t.references :session_recording, null: false, index: false,
                                       foreign_key: { on_delete: :cascade }
      t.integer  :seq,         null: false
      t.integer  :event_count, default: 0, null: false
      t.datetime :first_event_at
      t.datetime :last_event_at
      # gzipped JSON array of raw rrweb events. Gzip is applied server-side on
      # ingest; the player inflates it again. Typically 10-20x smaller.
      t.binary   :payload, null: false
      t.datetime :created_at, null: false
    end

    # Unique so a retried/duplicated beacon can't append the same chunk twice.
    add_index :session_recording_chunks, %i[session_recording_id seq], unique: true
  end
end

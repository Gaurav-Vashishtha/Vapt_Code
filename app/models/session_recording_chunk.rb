# frozen_string_literal: true

# A batch of rrweb events flushed by the browser, stored gzipped.
#
# The raw JSON is never queried — it is only ever written once and read back
# whole by the player — so it lives as a compressed bytea blob rather than
# jsonb. At ~15x compression a 30-minute session costs a few hundred KB.
class SessionRecordingChunk < ApplicationRecord
  belongs_to :session_recording

  validates :seq, presence: true

  # Accepts the parsed event array, stores it gzipped.
  def events=(array)
    json = Array(array).to_json
    self.payload = ActiveSupport::Gzip.compress(json)
  end

  def events
    raw = payload
    return [] if raw.blank?

    # PG::Connection returns bytea as a binary String; unescape defensively for
    # adapters that hand back the escaped form.
    raw = raw.to_s
    JSON.parse(ActiveSupport::Gzip.decompress(raw))
  rescue StandardError => e
    Rails.logger.warn("[SessionRecording] chunk #{id} unreadable: #{e.class}: #{e.message}")
    []
  end
end

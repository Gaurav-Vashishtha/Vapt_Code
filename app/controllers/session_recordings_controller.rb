# frozen_string_literal: true

# Append-only ingest for rrweb session recordings emitted by the embedded app
# (see app/views/shared/_session_recorder.html.erb).
#
# @shop comes from AuthenticatedController#set_shop, so a chunk can only ever be
# written against the shop whose embedded session made the request — the client
# never names the shop. CSRF is skipped because the last flush of a session goes
# out through navigator.sendBeacon, which cannot set headers.
#
# Like every analytics ingest in this app it always answers 204: a recorder
# failure must never surface to the merchant.
class SessionRecordingsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: [:ingest]

  MAX_BODY_BYTES    = 6.megabytes
  MAX_EVENTS_CHUNK  = 2_000
  MAX_CHUNKS        = 400   # ~ a very long session; past this we stop appending

  def ingest
    return head :no_content if @shop.blank?
    return head :no_content unless SessionRecordingPolicy.new(@shop).record?
    return head :no_content if request.content_length.to_i > MAX_BODY_BYTES

    payload = parse_body
    return head :no_content if payload.blank?

    session_key = payload["session_key"].to_s.strip
    events = payload["events"]
    return head :no_content if session_key.blank? || !events.is_a?(Array) || events.empty?
    return head :no_content if events.size > MAX_EVENTS_CHUNK

    store(session_key, payload, events)
    head :no_content
  rescue StandardError => e
    Rails.logger.warn("[SessionRecording] ingest failed shop=#{@shop&.shopify_domain} #{e.class}: #{e.message}")
    head :no_content
  end

  private

  # The event array is arbitrary nested rrweb JSON — strong params would mangle
  # it, so the body is read raw. The recorder gzips chunks in the browser
  # (?enc=gzip) to stay under the 64KB keepalive/sendBeacon limit; the unload
  # path can't compress synchronously and sends plain JSON (?enc=json).
  def parse_body
    raw = request.raw_post.to_s
    raw = gunzip_capped(raw) if params[:enc].to_s == "gzip"
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError, Zlib::Error
    nil
  end

  MAX_INFLATED_BYTES = 40.megabytes

  # Inflate with a ceiling so a hostile body can't balloon in memory.
  def gunzip_capped(raw)
    reader = Zlib::GzipReader.new(StringIO.new(raw))
    out = +""
    while (piece = reader.read(64.kilobytes))
      out << piece
      return nil if out.bytesize > MAX_INFLATED_BYTES
    end
    out.force_encoding(Encoding::UTF_8)
  ensure
    reader&.close
  end

  def store(session_key, payload, events)
    meta = payload["meta"].is_a?(Hash) ? payload["meta"] : {}
    seq  = payload["seq"].to_i
    first_at = event_time(events.first)
    last_at  = event_time(events.last)

    recording = find_or_create_recording(session_key, meta, first_at)
    return if recording.blank?
    return if recording.chunk_count >= MAX_CHUNKS

    chunk = recording.chunks.new(
      seq: seq,
      event_count: events.size,
      first_event_at: first_at,
      last_event_at: last_at,
      created_at: Time.current
    )
    chunk.events = events

    begin
      chunk.save!
    rescue ActiveRecord::RecordNotUnique
      # Duplicate beacon (sendBeacon can fire twice on some mobile browsers).
      return
    end

    # Counters are bumped in SQL so concurrent flushes from two tabs can't lose
    # an increment to a read-modify-write race.
    sql = SessionRecording.sanitize_sql_array([
      <<~SQL.squish,
        event_count      = event_count + ?,
        chunk_count      = chunk_count + 1,
        compressed_bytes = compressed_bytes + ?,
        last_event_at    = GREATEST(last_event_at, ?),
        duration_ms      = GREATEST(duration_ms, ?),
        last_path        = ?,
        updated_at       = NOW()
      SQL
      events.size,
      chunk.payload.to_s.bytesize,
      last_at,
      duration_for(recording, last_at),
      meta["path"].to_s.first(255).presence || recording.last_path
    ])
    SessionRecording.where(id: recording.id).update_all(sql)
  end

  def find_or_create_recording(session_key, meta, first_at)
    recording = SessionRecording.find_by(session_key: session_key)
    return recording if recording

    SessionRecording.create!(
      shop_id: @shop.id,
      shopify_domain: @shop.shopify_domain,
      session_key: session_key,
      started_at: first_at,
      last_event_at: first_at,
      entry_path: meta["path"].to_s.first(255).presence,
      last_path: meta["path"].to_s.first(255).presence,
      user_agent: meta["ua"].to_s.first(255).presence,
      viewport_width: meta["w"].to_i.positive? ? meta["w"].to_i : nil,
      viewport_height: meta["h"].to_i.positive? ? meta["h"].to_i : nil,
      metadata: {
        "plan" => @shop.plan&.name,
        "country" => @shop.country_code,
        "installed_at" => @shop.created_at&.iso8601,
        "referrer" => meta["referrer"].to_s.first(255).presence
      }.compact
    )
  rescue ActiveRecord::RecordNotUnique
    # Two chunks raced on the first flush.
    SessionRecording.find_by(session_key: session_key)
  end

  def duration_for(recording, last_at)
    ((last_at - recording.started_at) * 1000).to_i.clamp(0, 12.hours.to_i * 1000)
  end

  # rrweb timestamps are epoch milliseconds.
  def event_time(event)
    ms = event.is_a?(Hash) ? event["timestamp"].to_i : 0
    return Time.current if ms <= 0

    Time.zone.at(ms / 1000.0)
  end
end

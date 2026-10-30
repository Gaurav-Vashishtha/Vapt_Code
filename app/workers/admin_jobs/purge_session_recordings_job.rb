# frozen_string_literal: true

module AdminJobs
  # Session recordings are deliberately short-lived: they exist to answer "where
  # did this merchant get stuck yesterday", not to build an archive. Anything
  # past SESSION_RECORDING_RETENTION_HOURS (default 48) goes.
  #
  # Chunks carry the bytes, so they are deleted first and in batches — a single
  # DELETE over a day of recordings would hold a long transaction on the largest
  # table in this feature.
  class PurgeSessionRecordingsJob < ApplicationJob
    sidekiq_options queue: "low", retry: false

    BATCH_SIZE = 200

    def perform
      hours = SessionRecordingPolicy.retention_hours
      return if hours <= 0

      cutoff = hours.hours.ago
      recordings = 0
      chunks = 0

      loop do
        ids = SessionRecording.where("last_event_at < ?", cutoff).limit(BATCH_SIZE).pluck(:id)
        break if ids.empty?

        chunks += SessionRecordingChunk.where(session_recording_id: ids).delete_all
        recordings += SessionRecording.where(id: ids).delete_all
        break if ids.size < BATCH_SIZE

        sleep 0.1
      end

      Rails.logger.info(
        "[session-recording/purge] removed #{recordings} recordings / #{chunks} chunks older than #{hours}h"
      )
    end
  end
end

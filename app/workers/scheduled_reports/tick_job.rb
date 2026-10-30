# frozen_string_literal: true

module ScheduledReports
  class TickJob
    include Sidekiq::Job
    sidekiq_options queue: :default

    def perform
      if JobLock.locked?(DrainDueScheduledReportsJob::DRAIN_LOCK)
        Rails.logger.info("[TickJob] skip — scheduled report drain already running")
        return
      end

      DrainDueScheduledReportsJob.perform_async
    end
  end
end

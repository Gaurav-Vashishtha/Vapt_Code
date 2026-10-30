# frozen_string_literal: true

module ScheduledReports
  # Single active instance (DRAIN_LOCK): if a run is already in progress, this job returns immediately.
  # Does not enqueue one Sidekiq job per shop — it walks due rows and runs DeliverReportJob inline
  # (each send still takes MAIL_LOCK so only one email is sent at a time app-wide).
  class DrainDueScheduledReportsJob
    include Sidekiq::Job
    sidekiq_options queue: :default, retry: 2

    DRAIN_LOCK = "scheduled_reports_drain_due"
    STALE_AFTER = 4.hours
    HEARTBEAT_INTERVAL = 2.minutes

    def perform
      lock_acquired = JobLock.lock!(DRAIN_LOCK, stale_after: STALE_AFTER)
      unless lock_acquired
        Rails.logger.info("[DrainDueScheduledReportsJob] skip — another drain is already running")
        return
      end

      stop = Concurrent::AtomicBoolean.new(false)
      heartbeat = Thread.new do
        loop do
          break if stop.true?

          sleep(HEARTBEAT_INTERVAL)
          break if stop.true?

          JobLock.touch!(DRAIN_LOCK)
        end
      end

      n = 0
      begin
        ScheduledShopReport
          .includes(:shop, :scheduled_report_definition)
          .effective_for_delivery
          .find_each do |report|
            next unless report.deliver_enqueue_for_tick(Time.current)

            DeliverReportJob.new.perform(report.id, { "from_drain" => true })
            n += 1
          end
        Rails.logger.info("[DrainDueScheduledReportsJob] finished inline delivers count=#{n}")
      ensure
        stop.make_true
        heartbeat.join(5)
        JobLock.unlock!(DRAIN_LOCK)
      end
    end
  end
end

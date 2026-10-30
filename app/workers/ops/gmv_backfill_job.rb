# frozen_string_literal: true

module Ops
  # One-time history fill for ops_gmv_dailies, built for a primary-only database
  # (no read replica): newest -> oldest, a few days per run, pause between days,
  # only inside an off-peak IST window, resumable via a Redis cursor.
  #
  #   Ops::GmvBackfillJob.perform_async            # starts/continues; waits for the window
  #   Ops::GmvBackfillJob.perform_async(true)      # ignore the window (use deliberately)
  #
  # ENV: OPS_BACKFILL_WINDOW="1-7" (IST hours, start inclusive, end exclusive),
  #      OPS_GMV_BACKFILL_FROM="2025-01-01" (optional earliest date).
  class GmvBackfillJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 0

    CURSOR_KEY = 'ops:gmv_backfill:next_date'
    DAYS_PER_RUN = 3
    PAUSE_SECONDS = 3
    NEXT_RUN_DELAY = 30.seconds
    WAIT_FOR_WINDOW = 20.minutes

    def perform(force = false)
      return reschedule(WAIT_FOR_WINDOW) unless force || in_window?
      return Rails.logger.warn('[Ops::GmvBackfillJob] BRIN index missing, not starting') unless Ops::GmvRollup.index_ready?

      zone = ActiveSupport::TimeZone[Ops::GmvRollup::TZ]
      cursor = read_cursor || (zone.today - 1)
      earliest = earliest_date(zone)

      DAYS_PER_RUN.times do
        if cursor < earliest
          Sidekiq.redis { |r| r.del(CURSOR_KEY) }
          Rails.logger.info('[Ops::GmvBackfillJob] complete')
          return
        end
        Ops::GmvRollup.call(cursor)
        cursor -= 1
        write_cursor(cursor)
        sleep PAUSE_SECONDS
      end

      reschedule(NEXT_RUN_DELAY, force)
    rescue => e
      Rails.logger.error("[Ops::GmvBackfillJob] #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async("Ops::GmvBackfillJob (#{Rails.env}) stopped: #{e.class}: #{e.message}") rescue nil
      raise
    end

    private

    def reschedule(delay, force = false)
      self.class.perform_in(delay, force)
    end

    def in_window?
      from, to = ENV.fetch('OPS_BACKFILL_WINDOW', '1-7').split('-').map(&:to_i)
      hour = Time.current.in_time_zone(Ops::GmvRollup::TZ).hour
      from <= to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    end

    def earliest_date(zone)
      configured = ENV['OPS_GMV_BACKFILL_FROM'].presence && Date.parse(ENV['OPS_GMV_BACKFILL_FROM'])
      return configured if configured

      first = OrderConfirmation.order(:id).limit(1).pick(:created_at)
      first ? first.in_time_zone(zone).to_date : zone.today
    end

    def read_cursor
      raw = Sidekiq.redis { |r| r.get(CURSOR_KEY) }
      raw.present? ? Date.parse(raw) : nil
    end

    def write_cursor(date)
      Sidekiq.redis { |r| r.set(CURSOR_KEY, date.to_s) }
    end
  end
end

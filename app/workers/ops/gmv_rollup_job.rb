# frozen_string_literal: true

module Ops
  # Hourly: recompute today + yesterday (IST) so late orders and status edits are picked up.
  class GmvRollupJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    def perform(days = 2)
      return Rails.logger.warn('[Ops::GmvRollupJob] BRIN index missing, skipping') unless Ops::GmvRollup.index_ready?

      today = ActiveSupport::TimeZone[Ops::GmvRollup::TZ].today
      days.to_i.times { |i| Ops::GmvRollup.call(today - i) }
    rescue => e
      Rails.logger.error("[Ops::GmvRollupJob] #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async("Ops::GmvRollupJob (#{Rails.env}) failed: #{e.class}: #{e.message}") rescue nil
      raise
    end
  end
end

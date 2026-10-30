# frozen_string_literal: true

module CodForm
  module Analytics
    # ANL-5: raw cf_* funnel events are kept 90 days; daily rollups are kept indefinitely.
    # sidekiq-cron: daily, queue low. Deletes in batches of 5 000.
    # Express's own events (form_view, checkout_initiated) are never touched.
    class PurgeJob < ApplicationJob
      sidekiq_options queue: "low", retry: 1

      RETENTION_DAYS = 90
      BATCH_SIZE = 5_000
      MAX_BATCHES = 400 # 2M rows per run; a backlog continues in a follow-up job

      def perform
        cutoff = RETENTION_DAYS.days.ago
        scope = FormFunnelEvent.where(event_type: EventMeta::EVENT_TYPES).where("occurred_at < ?", cutoff)
        deleted = 0
        batches = 0

        loop do
          ids = scope.limit(BATCH_SIZE).pluck(:id)
          break if ids.empty?

          deleted += FormFunnelEvent.where(id: ids).delete_all
          batches += 1
          if batches >= MAX_BATCHES
            self.class.perform_in(5.minutes)
            break
          end
        end

        Rails.logger.info("[codf/purge] deleted=#{deleted} cutoff=#{cutoff.to_date}")
      end
    end
  end
end

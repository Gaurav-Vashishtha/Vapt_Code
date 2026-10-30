# frozen_string_literal: true

module Webhooks
  class PurgeInboundEventsJob < ApplicationJob
    sidekiq_options queue: 'low', retry: false

    BATCH_SIZE = 5_000

    def perform
      days = ENV.fetch('WEBHOOK_EVENT_RETENTION_DAYS', 30).to_i
      return if days <= 0

      cutoff = days.days.ago
      total = 0

      loop do
        # Deleted by id rather than delete_all-with-limit, which Postgres does
        # not support on a DELETE.
        ids = InboundWebhookEvent.older_than(cutoff).limit(BATCH_SIZE).pluck(:id)
        break if ids.empty?

        total += InboundWebhookEvent.where(id: ids).delete_all
        break if ids.size < BATCH_SIZE

        sleep 0.1
      end

      Rails.logger.info("[webhook/purge] removed #{total} inbound events older than #{days}d")
    end
  end
end

# frozen_string_literal: true

module ShopifyJobs
  # Hourly janitor for customer_pull_job_queues.
  #
  # The processor (CustomerPullQueueProcessorJob) only takes `pending` rows, one shop at a time.
  # A killed dyno leaves a row `processing` forever and failed rows are never retried, so:
  #
  #   1. failed rows whose only error was a Slack rate limit -> `done` (the pull had finished)
  #   2. orphaned `processing` rows whose shop was flagged complete afterwards -> `done`
  #   3. top up the queue with orphaned / network-failed rows, VALUABLE SHOPS ONLY
  #      (Shop.pull_worthy, IN/PH, 1..MAX_AUTO_CUSTOMERS customers), paying shops first,
  #      in small batches and only while the processor queue is nearly empty.
  #
  # Each row is retried at most MAX_ATTEMPTS times. Big shops (> MAX_AUTO_CUSTOMERS) are never
  # auto-queued: run them by hand in a quiet window.
  #
  # Kill switch: heroku config:set CUSTOMER_PULL_REAPER_ENABLED=false
  class CustomerPullReaperJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 0

    LOCK_KEY = 'customer_pull_lock' # held by CustomerPullQueueProcessorJob
    ORPHAN_AFTER = 6.hours
    LOCK_ALIVE_WITHIN = 10.minutes # processor heartbeats every 2 minutes
    TARGET_QUEUE_DEPTH = 25
    MAX_PER_RUN = 25
    MAX_AUTO_CUSTOMERS = 200_000
    MAX_ATTEMPTS = 3
    ATTEMPT_KEY = 'customer_pull_reaper:attempts:%d'
    SLACK_ERROR = /slack API returned an error/i
    RETRIABLE = /execution expired|Failed to open TCP|SSL_connect|timed? ?out|Connection reset|EOFError|\b50[234]\b/i
    COUNTRIES = %w[IN PH].freeze

    def perform
      return unless enabled?

      slack_fixed = close_slack_false_failures
      finished = close_finished_orphans
      requeued = requeue_valuable

      Rails.logger.info("[CustomerPullReaperJob] slack_fixed=#{slack_fixed} finished=#{finished} requeued=#{requeued}")
      if (slack_fixed + finished + requeued).positive?
        SlackNotifyJob.perform_async("CustomerPullReaperJob (#{Rails.env}): closed #{slack_fixed + finished} finished pulls, re-queued #{requeued} valuable shops")
      end
    rescue => e
      Rails.logger.error("[CustomerPullReaperJob] #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async("CustomerPullReaperJob (#{Rails.env}) failed: #{e.class}: #{e.message}") rescue nil
    end

    private

    def enabled?
      ENV.fetch('CUSTOMER_PULL_REAPER_ENABLED', 'true').to_s.downcase != 'false'
    end

    # 1. The pull finished (shop flagged complete) but the Slack ping raised and flipped the row to failed.
    def close_slack_false_failures
      CustomerPullJobQueue.where(status: 'failed')
                          .where('customer_pull_job_queues.error_message ILIKE ?', '%slack API returned an error%')
                          .joins(:shop)
                          .where(%q(shops.initial_customer_pull_completed >= customer_pull_job_queues.updated_at - interval '10 minutes'))
                          .update_all(status: 'done', error_message: nil)
    end

    # 2. Orphaned `processing` rows whose shop was completed after the row started.
    def close_finished_orphans
      orphan_scope.joins(:shop)
                  .where('shops.initial_customer_pull_completed > customer_pull_job_queues.updated_at')
                  .update_all(status: 'done')
    end

    def orphan_scope
      scope = CustomerPullJobQueue.where(status: 'processing')
                                  .where('customer_pull_job_queues.updated_at < ?', ORPHAN_AFTER.ago)
      if processor_alive?
        newest = CustomerPullJobQueue.where(status: 'processing').order(:updated_at).last
        scope = scope.where.not(id: newest.id) if newest
      end
      scope
    end

    # The processor holds a DB lock and refreshes it every 2 minutes while a pull runs.
    def processor_alive?
      JobLock.where(job_name: LOCK_KEY).where('locked_at > ?', LOCK_ALIVE_WITHIN.ago).exists?
    end

    # 3. Top up the processor queue, valuable shops only.
    def requeue_valuable
      capacity = [TARGET_QUEUE_DEPTH - processable_pending_count, MAX_PER_RUN].min
      return 0 if capacity <= 0

      failed_retriable = CustomerPullJobQueue.where(status: 'failed').pluck(:id, :error_message)
                                             .select { |_, msg| msg.to_s !~ SLACK_ERROR && msg.to_s =~ RETRIABLE }
                                             .map(&:first)
      ids = orphan_scope.pluck(:id) + failed_retriable
      return 0 if ids.empty?

      candidates = CustomerPullJobQueue.where(id: ids).joins(:shop)
                                       .merge(Shop.pull_worthy)
                                       .where(shops: { country_code: COUNTRIES })
                                       .where('shops.customer_count BETWEEN 1 AND ?', MAX_AUTO_CUSTOMERS)
                                       .order(Arel.sql(<<~SQL.squish))
                                         CASE WHEN shops.charge_id IS NOT NULL AND shops.charge_id <> '' THEN 0 ELSE 1 END,
                                         shops.last_order_at DESC NULLS LAST,
                                         shops.customer_count ASC
                                       SQL
                                       .limit(capacity * 3)
                                       .pluck('customer_pull_job_queues.id')

      picked = []
      candidates.each do |id|
        break if picked.size >= capacity
        picked << id if bump_attempts(id) <= MAX_ATTEMPTS
      end
      return 0 if picked.empty?

      CustomerPullJobQueue.where(id: picked).update_all(status: 'pending', error_message: nil, updated_at: Time.current)
      ShopifyJobs::CustomerPullQueueProcessorJob.perform_async
      picked.size
    end

    def processable_pending_count
      CustomerPullJobQueue.processable.joins(:shop)
                          .merge(ShopifyJobs::CustomerPullQueueProcessorJob.shop_scope)
                          .where(shops: { country_code: COUNTRIES })
                          .where('shops.customer_count > 0')
                          .count
    end

    def bump_attempts(id)
      key = format(ATTEMPT_KEY, id)
      Sidekiq.redis do |r|
        count = r.incr(key)
        r.expire(key, 30.days.to_i)
        count.to_i
      end
    end
  end
end

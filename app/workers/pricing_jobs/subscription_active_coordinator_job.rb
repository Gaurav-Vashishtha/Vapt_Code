# frozen_string_literal: true

module PricingJobs
  # Fans out SubscriptionActiveJob across shop id windows of SHOP_ID_CHUNK_SIZE
  # (same shape as DynamicChargeCoordinatorJob). Each shard writes its partial
  # totals to Redis under a run id; the shard that finishes last merges every
  # partial and posts the combined Slack report, so the output is identical to
  # the old single-pass job.
  class SubscriptionActiveCoordinatorJob < ApplicationJob
    sidekiq_options queue: "administration"

    SHOP_ID_CHUNK_SIZE = 10_000
    STAGGER = 10.minutes

    def perform
      min_id = Shop.minimum(:id)
      max_id = Shop.maximum(:id)
      return if min_id.blank? || max_id.blank?

      ranges = []
      start_id = min_id
      while start_id <= max_id
        end_id = [start_id + SHOP_ID_CHUNK_SIZE - 1, max_id].min
        ranges << [start_id, end_id]
        start_id = end_id + 1
      end

      run_id = "#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
      SubscriptionActiveJob.start_run(run_id, ranges.size)

      ranges.each_with_index do |(a, b), index|
        SubscriptionActiveJob.perform_in(index * STAGGER, a, b, run_id, index)
      end

      SlackNotifier::CLIENT.ping(
        text: <<~MSG.strip
          SubscriptionActiveCoordinatorJob (#{Rails.env}): scheduled #{ranges.size} SubscriptionActiveJob shard(s), #{STAGGER.in_minutes.to_i} minutes apart, chunk size #{SHOP_ID_CHUNK_SIZE}. Run #{run_id}.
          ID ranges: #{ranges.map { |a, b| "#{a}-#{b}" }.join(", ")}
        MSG
      )
    end
  end
end

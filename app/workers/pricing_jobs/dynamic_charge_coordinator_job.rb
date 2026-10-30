# frozen_string_literal: true

module PricingJobs
  # Fans out DynamicChargeJob across shop id windows so each run handles at most
  # SHOP_ID_CHUNK_SIZE shops; children are staggered on the administration queue.
  class DynamicChargeCoordinatorJob < ApplicationJob
    sidekiq_options queue: "administration"

    SHOP_ID_CHUNK_SIZE = 10_000
    STAGGER = 10.minutes

    def perform
      min_id = Shop.minimum(:id)
      max_id = Shop.maximum(:id)
      return if min_id.blank? || max_id.blank?

      ranges = []
      start_id = min_id
      index = 0
      while start_id <= max_id
        end_id = [start_id + SHOP_ID_CHUNK_SIZE - 1, max_id].min
        ranges << [start_id, end_id]
        DynamicChargeJob.perform_in(index * STAGGER, start_id, end_id, false)
        start_id = end_id + 1
        index += 1
      end

      SlackNotifier::CLIENT.ping(
        text: <<~MSG.strip
          DynamicChargeCoordinatorJob (#{Rails.env}): scheduled #{ranges.size} DynamicChargeJob shard(s), #{STAGGER.in_minutes.to_i} minutes apart, chunk size #{SHOP_ID_CHUNK_SIZE}.
          ID ranges: #{ranges.map { |a, b| "#{a}-#{b}" }.join(", ")}
        MSG
      )
    end
  end
end

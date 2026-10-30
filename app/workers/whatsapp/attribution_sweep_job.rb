# frozen_string_literal: true

module Whatsapp
  # Every 15 minutes with a 2-hour window; once a day with 72 hours so
  # delivered/read webhooks that arrived late still earn their orders, and
  # orders cancelled since are dropped.
  class AttributionSweepJob < ApplicationJob
    sidekiq_options queue: 'low', retry: 1

    PRUNE_FROM_HOURS = 72
    PRUNE_DAYS = 14

    def perform(hours = 2)
      hours = [hours.to_i, 1].max
      to = Time.current
      from = to - hours.hours

      shop_ids = WhatsappAccount.shop_owned.distinct.pluck(:shop_id)
      Shop.where(id: shop_ids).find_each do |shop|
        sweep(shop, from: from, to: to, prune: hours >= PRUNE_FROM_HOURS)
      end
    end

    private

    def sweep(shop, from:, to:, prune:)
      RevenueAttribution.with_statement_timeout do
        RevenueAttribution.attribute_orders!(shop, from: from, to: to)
        RevenueAttribution.attribute_conversions!(shop, from: from, to: to)
        RevenueAttribution.prune_cancelled!(shop, since: PRUNE_DAYS.days.ago) if prune
      end
    rescue StandardError => e
      Rails.logger.error("[Whatsapp::AttributionSweepJob] shop=#{shop.id} #{e.class}: #{e.message}")
    end
  end
end

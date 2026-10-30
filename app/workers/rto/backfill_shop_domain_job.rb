# frozen_string_literal: true

module Rto
  class BackfillShopDomainJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    PAGE_SIZE = 50
    RETRY_AFTER = 5.days
    LOCK_NAME = "rto_backfill_coordinator"

    def perform(shop_domain_id)
      sd = ShopDomain.find_by(id: shop_domain_id)
      return if sd.blank?

      # Backoff after failures
      if sd.backfill_next_retry_at.present? && sd.backfill_next_retry_at > Time.current
        self.class.perform_in(sd.backfill_next_retry_at - Time.current, sd.id)
        return
      end

      lease = BackfillLeaseManager.acquire_for!(sd.id)
      unless lease
        # Concurrency cap reached; try again later.
        self.class.perform_in(2.minutes, sd.id)
        return
      end

      begin
        sd.update!(backfill_last_attempt_at: Time.current, backfill_last_error: "", backfill_next_retry_at: nil)
        sd.update!(backfill_started_at: Time.current) if sd.backfill_started_at.blank?

        # We rely on existing Shop record for an active token/session.
        shop = Shop.find_by(shopify_domain: sd.shopify_domain)
        if shop.blank?
          sd.update!(
            backfill_state: (sd.backfill_state || {}).merge("last_error" => "no_shop_installation"),
            backfill_last_error: "no_shop_installation",
            backfill_next_retry_at: RETRY_AFTER.from_now
          )
          return
        end

        shop.init_session

        state = sd.backfill_state || {}
        since_id = (state["since_id"].presence || "0").to_i

        # One page per job so long backfills are spread across domains and Sidekiq workers.
        orders = ShopifyAPI::Order.find(
          :all,
          params: {
            limit: PAGE_SIZE,
            since_id: since_id,
            status: "any",
            order: "id asc"
          }
        )

        if orders.blank?
          sd.update!(backfill_state: state.merge("since_id" => since_id.to_s, "updated_at" => Time.current.iso8601))
          complete_backfill!(sd, 0)
          return
        end

        orders.each do |o|
          Rto::OrderUpsertService.call(
            shopify_domain: sd.shopify_domain,
            order_payload: o,
            source: "backfill",
            event_type: "orders/backfill",
            occurred_at: Time.current
          )
        end

        new_since_id = orders.last.id.to_i
        fetched_count = orders.size
        sd.update!(
          backfill_state: state.merge("since_id" => new_since_id, "updated_at" => Time.current.iso8601)
        )

        complete_backfill!(sd, fetched_count) if orders.size < PAGE_SIZE
      rescue => e
        sd.update!(
          backfill_last_error: "#{e.class}: #{e.message}",
          backfill_next_retry_at: RETRY_AFTER.from_now
        ) rescue nil
        # SlackNotifyJob.perform_async(
        #   ":warning: (#{Rails.env})\nRTO backfill failed\nShop: #{sd&.shopify_domain}\nRetryAfter: #{RETRY_AFTER.inspect}\n#{e.class}: #{e.message}"
        # )
        nil
      ensure
        BackfillLeaseManager.release!(lease)
        # Keep draining the queue quickly when concurrency drops to zero.
        if BackfillLease.where("expires_at >= ?", Time.current).count.zero?
          BackfillCoordinatorJob.perform_async
          JobLock.unlock!(LOCK_NAME)
        end
      end
    end

    private

    # When historical `since_id` backfill finishes, seed incremental sync so
    # `ReconcileShopDomainJob` uses `updated_at_min` from (roughly) backfill start
    # and picks up any order updated on Shopify after we started.
    def complete_backfill!(sd, fetched_count)
      started = sd.backfill_started_at || Time.current
      sd.update!(
        backfill_completed_at: Time.current,
        incremental_sync_cursor_at: [started - 1.hour, 1.year.ago].max
      )
      send_completion_report(sd, fetched_count)
    end

    def send_completion_report(sd, fetched_count)
      orders_count = RtoOrder.where(shop_domain_id: sd.id).count
      events_count = RtoOrderEvent.where(shop_domain_id: sd.id).count
      distinct_phones = RtoOrder.where(shop_domain_id: sd.id).where.not(phone_normalized: [nil, ""]).distinct.count(:phone_normalized)

      SlackNotifyJob.perform_async(
        ":white_check_mark: (#{Rails.env})\nRTO backfill completed\nShop: #{sd.shopify_domain}\nLastBatchSize: #{fetched_count}\nRtoOrders: #{orders_count}\nRtoEvents: #{events_count}\nDistinctPhonesInOrders: #{distinct_phones}"
      )
    rescue
      nil
    end
  end
end


module PricingJobs
  # Daily paid-subscription report. Normally fanned out by
  # SubscriptionActiveCoordinatorJob in shop-id shards; each shard stores its
  # partial totals in Redis and the last shard to finish posts the merged report.
  # Calling perform with no arguments still runs every shop in one pass and
  # posts immediately (handy from the console).
  class SubscriptionActiveJob < ApplicationJob
    sidekiq_options queue: "administration"

    REDIS_TTL = 2.days.to_i
    LOG_BATCH_SIZE = 200

    def self.redis_key(run_id, suffix)
      "subscription_active_report:#{run_id}:#{suffix}"
    end

    def self.start_run(run_id, shard_count)
      Sidekiq.redis do |r|
        r.set(redis_key(run_id, "expected"), shard_count, ex: REDIS_TTL)
        r.set(redis_key(run_id, "done"), 0, ex: REDIS_TTL)
      end
    end

    # shop_id_min / shop_id_max: optional inclusive range (coordinator shards).
    # run_id / shard_index: identify this shard's slot in the Redis aggregate.
    def perform(shop_id_min = nil, shop_id_max = nil, run_id = nil, shard_index = nil)
      sharded = shop_id_min.present? && shop_id_max.present? && run_id.present?
      label = sharded ? "shard #{shard_index} (#{shop_id_min}-#{shop_id_max}, run #{run_id})" : "single pass"
      Rails.logger.info "[SubscriptionActiveJob] Starting combined subscription report — #{label}"

      stats = blank_stats

      shops = Shop.order(:id)
      shops = shops.where(id: shop_id_min.to_i..shop_id_max.to_i) if shop_id_min.present? && shop_id_max.present?

      shops.find_each(batch_size: LOG_BATCH_SIZE) do |shop|
        stats[:shop_count] += 1

        begin
          shop.init_session
          # Avoid loading all charges (memory-heavy). Current returns the active charge when present.
          plan = ShopifyAPI::RecurringApplicationCharge.current

          if plan
            price = plan.price.to_f
            plan_name = plan.name

            # Skip free plans (price = 0)
            if price > 0
              stats[:active_shops] += 1
              stats[:overall_total] += price
              stats[:overall_plan_counts][plan_name] += 1
              stats[:overall_plan_revenue][plan_name] += price

              if shop.created_at >= 30.days.ago
                stats[:recent_total] += price
                stats[:recent_plan_counts][plan_name] += 1
                stats[:recent_plan_revenue][plan_name] += price
              end

              Rails.logger.info "[Shop: #{shop.shopify_domain}] Plan: #{plan_name}, Price: $#{price}"
            end
          else
            Rails.logger.warn "[Shop: #{shop.shopify_domain}] No active subscription found"
          end
        rescue => e
          Rails.logger.error "[Shop: #{shop.shopify_domain}] Error: #{e.message}"
        ensure
          # Clear per-shop session to avoid retaining state across thousands of shops.
          ShopifyAPI::Base.clear_session
        end

        if (stats[:shop_count] % 250).zero?
          Rails.logger.info "[SubscriptionActiveJob] Progress #{label} processed=#{stats[:shop_count]} active=#{stats[:active_shops]} total=$#{stats[:overall_total].round(2)}"
        end
      end

      if sharded
        finish_shard(run_id, shard_index, stats)
      else
        post_report(stats)
      end

      Rails.logger.info "[SubscriptionActiveJob] Completed #{label}. Processed #{stats[:shop_count]} shops, #{stats[:active_shops]} with active paid subscriptions."
    end

    private

    def blank_stats
      {
        shop_count: 0,
        active_shops: 0,
        overall_total: 0.0,
        recent_total: 0.0,
        overall_plan_counts: Hash.new(0),
        recent_plan_counts: Hash.new(0),
        overall_plan_revenue: Hash.new(0.0),
        recent_plan_revenue: Hash.new(0.0)
      }
    end

    # Store this shard's partial totals, bump the done counter, and let whichever
    # shard lands last (INCR is atomic) merge and post the report.
    def finish_shard(run_id, shard_index, stats)
      expected = nil
      done = nil
      Sidekiq.redis do |r|
        r.set(self.class.redis_key(run_id, "shard:#{shard_index}"), stats.to_json, ex: REDIS_TTL)
        expected = r.get(self.class.redis_key(run_id, "expected")).to_i
        done = r.incr(self.class.redis_key(run_id, "done"))
      end

      Rails.logger.info "[SubscriptionActiveJob] Shard #{shard_index} of run #{run_id} stored (#{done}/#{expected} done)"
      return unless expected.positive? && done >= expected

      merged = blank_stats
      missing = []
      Sidekiq.redis do |r|
        expected.times do |i|
          raw = r.get(self.class.redis_key(run_id, "shard:#{i}"))
          if raw.blank?
            missing << i
            next
          end
          merge_stats!(merged, JSON.parse(raw))
        end
      end

      post_report(merged, run_id: run_id, shard_count: expected, missing_shards: missing)
    end

    def merge_stats!(into, partial)
      partial = partial.with_indifferent_access
      into[:shop_count] += partial[:shop_count].to_i
      into[:active_shops] += partial[:active_shops].to_i
      into[:overall_total] += partial[:overall_total].to_f
      into[:recent_total] += partial[:recent_total].to_f
      %i[overall_plan_counts recent_plan_counts].each do |key|
        (partial[key] || {}).each { |plan, count| into[key][plan] += count.to_i }
      end
      %i[overall_plan_revenue recent_plan_revenue].each do |key|
        (partial[key] || {}).each { |plan, revenue| into[key][plan] += revenue.to_f }
      end
      into
    end

    def post_report(stats, run_id: nil, shard_count: nil, missing_shards: [])
      run_note = run_id ? " _(run #{run_id}, #{shard_count} shards)_" : ""
      overall_message = ":bar_chart: *COD King Subscription Report (#{Rails.env}) — All Shops*#{run_note}\n" \
                        "*Total Revenue:* $#{stats[:overall_total].round(2)} from #{stats[:active_shops]} active subscriptions\n" \
                        "*Plan Breakdown:*\n" \
                        "#{format_plan_breakdown(stats[:overall_plan_counts], stats[:overall_plan_revenue])}"

      recent_message = ":calendar: *COD King Subscription Report — Shops Created in Last 30 Days*\n" \
                       "*Total Revenue:* $#{stats[:recent_total].round(2)} from #{stats[:recent_plan_counts].values.sum} active subscriptions\n" \
                       "*Plan Breakdown:*\n" \
                       "#{format_plan_breakdown(stats[:recent_plan_counts], stats[:recent_plan_revenue])}"

      if missing_shards.any?
        overall_message << "\n:warning: Shards #{missing_shards.join(', ')} had no stored result — totals above are incomplete."
      end

      SlackNotifier::CLIENT.ping(text: overall_message)
      SlackNotifier::CLIENT.ping(text: recent_message)

      begin
        Ops::SubscriptionSnapshot.record!(stats, complete: missing_shards.empty?)
      rescue => e
        Rails.logger.error "[SubscriptionActiveJob] ops snapshot failed: #{e.class}: #{e.message}"
      end
    end

    def format_plan_breakdown(plan_counts, plan_revenue)
      return "_No active paid plans found._" if plan_counts.empty?

      plan_counts.map do |plan, count|
        revenue = plan_revenue[plan]
        "• *#{plan}*: #{count} shop#{count == 1 ? '' : 's'} - $#{revenue.round(2)}"
      end.join("\n")
    end
  end
end

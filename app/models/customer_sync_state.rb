# frozen_string_literal: true

class CustomerSyncState < ApplicationRecord
  belongs_to :shop

  BACKOFF = [5.minutes, 15.minutes, 1.hour, 4.hours, 12.hours].freeze
  ATTENTION_AFTER = 8
  UNREACHABLE_PREFIX = 'Shopify returned 401:'

  scope :due, -> { where(status: %w[idle backoff]).where('customer_sync_states.next_attempt_at IS NULL OR customer_sync_states.next_attempt_at <= ?', Time.current) }
  scope :with_backlog, -> { where('customer_sync_states.unloaded_count >= ?', min_unloaded) }
  scope :by_priority, lambda {
    order(Arel.sql(
      '(customer_sync_states.unloaded_count + ' \
      'GREATEST(EXTRACT(EPOCH FROM (now() - COALESCE(customer_sync_states.last_success_at, customer_sync_states.created_at))), 0) / 3600.0 * ' \
      "#{aging_per_hour.to_f}) DESC, customer_sync_states.id ASC"
    ))
  }

  class << self
    def min_unloaded = ENV.fetch('CUSTOMER_SYNC_MIN_UNLOADED', 1).to_i

    def aging_per_hour = ENV.fetch('CUSTOMER_SYNC_AGING_PER_HOUR', 1).to_f

    def big_shop_threshold = ENV.fetch('CUSTOMER_SYNC_BIG_SHOP', 200_000).to_i

    def max_concurrent_big = ENV.fetch('CUSTOMER_SYNC_MAX_BIG_INFLIGHT', 1).to_i

    def countries = ENV.fetch('CUSTOMER_BULK_COUNTRIES', 'IN,PH').split(',').map(&:strip)

    def max_customers = ENV.fetch('CUSTOMER_BULK_MAX_CUSTOMERS', 1_000_000).to_i

    def shop_scope
      ENV.fetch('CUSTOMER_PULL_VALUE_FILTER', 'true').to_s.downcase == 'false' ? Shop.real_installs : Shop.pull_worthy
    end

    def sync_scope
      shop_scope.where(country_code: countries)
    end

    def for_shop(shop_id)
      find_or_create_by!(shop_id: shop_id)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def record_count!(shop, count)
      state = find_by(shop_id: shop.id)
      if state.nil? || unseeded?(state)
        baseline = initial_baseline(shop, count)
        return nil if baseline.nil?

        state ||= new(shop_id: shop.id)
        state.baseline_count = baseline
      end
      state.shopify_customer_count = count
      state.baseline_count = [state.baseline_count, count].min
      state.count_synced_at = Time.current
      if state.status == 'disabled'
        state.status = 'idle'
        state.consecutive_failures = 0
      end
      state.save!
      state
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def reseed!(state)
      baseline = initial_baseline(state.shop, state.shopify_customer_count)
      return false if baseline.nil?

      state.update!(baseline_count: baseline)
      true
    end

    def unseeded?(state)
      state.count_synced_at.nil? && state.last_success_at.nil?
    end

    def initial_baseline(shop, count)
      pulled_at = shop.initial_customer_pull_completed
      return 0 if pulled_at.blank?

      created_since = ShopifyServices::CustomerCountFetchService.call(shop, pulled_at)
      return nil unless created_since.is_a?(Integer)

      (count - created_since).clamp(0, count)
    end

    def unauthorized_message?(message)
      message.to_s.match?(/\b401\b|unauthorized/i)
    end

    def mark_unreachable!(shop, message)
      for_shop(shop.id).update!(status: 'disabled', last_error: "#{UNREACHABLE_PREFIX} #{message}".truncate(250))
    end

    def schedule_recheck(shop_id)
      return unless where(shop_id: shop_id, status: 'disabled').where('last_error LIKE ?', "#{UNREACHABLE_PREFIX}%").exists?

      ShopifyJobs::CustomerCountShopJob.perform_in(30.seconds, shop_id)
    end

    def mark_running!(shop_id)
      for_shop(shop_id).update!(status: 'running', last_attempt_at: Time.current)
    end

    def record_success!(shop_id, baseline: nil)
      state = for_shop(shop_id)
      state.update!(
        status: 'idle',
        baseline_count: [baseline || state.shopify_customer_count, state.shopify_customer_count].min,
        last_success_at: Time.current,
        consecutive_failures: 0,
        next_attempt_at: nil,
        last_error: nil
      )
    end

    def record_failure!(shop_id, message, count_failure: true)
      state = for_shop(shop_id)
      failures = state.consecutive_failures + (count_failure ? 1 : 0)
      wait = count_failure ? BACKOFF[[failures - 1, BACKOFF.size - 1].min.clamp(0, BACKOFF.size - 1)] : 2.minutes
      state.update!(
        status: failures >= ATTENTION_AFTER ? 'needs_attention' : 'backoff',
        consecutive_failures: failures,
        last_error: message.to_s.truncate(250),
        next_attempt_at: Time.current + wait
      )
    end

    def plannable(limit)
      inflight_big = CustomerBulkExport.active.where('expected_count >= ?', big_shop_threshold).count
      rows = due.with_backlog.joins(:shop)
                .merge(sync_scope)
                .where('customer_sync_states.shopify_customer_count <= ?', max_customers)
                .where.not(shop_id: CustomerBulkExport.active.select(:shop_id))
                .by_priority
                .preload(:shop)
                .limit(limit * 10 + 20)
      picked = []
      rows.each do |state|
        break if picked.size >= limit

        if state.unloaded_count >= big_shop_threshold
          next if inflight_big + picked.count { |s| s.unloaded_count >= big_shop_threshold } >= max_concurrent_big
        end
        picked << state
      end
      picked
    end
  end
end

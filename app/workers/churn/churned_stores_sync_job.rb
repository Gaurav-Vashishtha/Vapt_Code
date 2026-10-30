# frozen_string_literal: true

module Churn
  # Rebuilds churned_stores for churn events in the last N days.
  #
  #   1. Partner app events (installs/uninstalls/charge activations+cancellations)
  #   2. Revenue baseline — COD King transactions for N + 30 days (churn-rate denominator)
  #   3. Detect churn (Churn::ChurnDetector)
  #   4. Per churned domain: full Partner transaction history -> LTV, subscription vs
  #      usage, last-30-day revenue, revenue since they came back
  #   5. Upsert churned_stores; drop rows in the window that no longer qualify
  #   6. Refresh older churn rows whose store came back (reinstalled / resubscribed)
  #      during the window, so "came back" stays current for any date range
  #
  # Triggered from the churn page ("Sync", default 7 days) and daily for 30 days
  # (config/schedule.yml). Single-flight via Churn::SyncStatus; progress is
  # written there for the page to poll.
  class ChurnedStoresSyncJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 0

    MAX_DAYS = 90
    BASELINE_DAYS = 30
    MAX_RETURN_REFRESH = 200

    def perform(days = 7, triggered_by = 'schedule')
      days = days.to_i.clamp(1, MAX_DAYS)
      run_id = SecureRandom.hex(8)
      unless SyncStatus.acquire_lock(run_id)
        Rails.logger.info('[Churn::ChurnedStoresSyncJob] another sync is running; skipping')
        return
      end
      @lock_run_id = run_id

      now = Time.current
      since = (Date.current - days).beginning_of_day
      errors = []
      counts = Hash.new(0)
      status(state: 'running', run_id: run_id, days: days, triggered_by: triggered_by,
             started_at: now.iso8601, finished_at: nil, step: 'Fetching Partner app events',
             processed: 0, total_stores: 0, failed: 0, errors: [], message: nil)

      client = PartnerApi::GraphqlClient.new

      events_ok = begin
        n = PartnerAppEventsSync.new(since: since - 2.days, until_time: now, client: client).call
        counts[:events] = n
        true
      rescue => e
        errors << "Partner app events: #{brief(e)}"
        false
      end

      status(step: 'Refreshing revenue baseline')
      begin
        baseline = PartnerSalesSyncJob.new.sync!(days + BASELINE_DAYS + 1, client: client)
        errors << "Revenue baseline stopped at the page limit (#{baseline[:fetched]} transactions) — rates may be understated" if baseline[:truncated]
      rescue => e
        errors << "Revenue baseline: #{brief(e)}"
      end

      candidates = ChurnDetector.new(since: since, until_time: now).call
      by_domain = candidates.group_by(&:domain)
      status(step: "Syncing stores (0/#{by_domain.size})", total_stores: by_domain.size)

      by_domain.each_with_index do |(domain, list), index|
        revenue = nil
        begin
          revenue = StoreRevenue.fetch(domain, client: client)
        rescue => e
          counts[:revenue_failed] += 1
          errors << "#{domain}: #{brief(e)}" if errors.size < 20
        end

        list.each do |candidate|
          upsert(ChurnedStoreBuilder.new(candidate, revenue: revenue).attributes)
          counts[:synced] += 1
        rescue => e
          counts[:failed] += 1
          errors << "#{domain} (#{candidate.churn_type}): #{brief(e)}" if errors.size < 20
          Rails.logger.error("[Churn::ChurnedStoresSyncJob] #{domain}: #{brief(e)} #{Array(e.backtrace).first(3).join(' | ')}")
        end

        if ((index + 1) % 5).zero? || index + 1 == by_domain.size
          status(step: "Syncing stores (#{index + 1}/#{by_domain.size})", processed: counts[:synced], failed: counts[:failed])
          SyncStatus.refresh_lock(run_id)
        end
      end

      counts[:pruned] = prune!(since, now, candidates.map(&:source_key), events_ok)

      if events_ok
        status(step: 'Refreshing stores that came back')
        counts[:refreshed] = refresh_returners(since, client, errors)
      end

      state = counts[:synced].zero? && errors.any? ? 'failed' : 'completed'
      message = "#{counts[:synced]} churn rows synced across #{by_domain.size} stores" \
                "#{", #{counts[:pruned]} removed" if counts[:pruned].positive?}" \
                "#{", #{counts[:refreshed]} older rows refreshed" if counts[:refreshed].positive?}" \
                "#{", #{counts[:revenue_failed]} without Partner revenue" if counts[:revenue_failed].positive?}" \
                "#{" — #{errors.size} warning(s): #{errors.first(3).join('; ')}" if errors.any?}"
      status(state: state, step: nil, finished_at: Time.current.iso8601, processed: counts[:synced],
             failed: counts[:failed], errors: errors.first(20), message: message)
    rescue => e
      Rails.logger.error("[Churn::ChurnedStoresSyncJob] #{brief(e)}")
      status(state: 'failed', step: nil, finished_at: Time.current.iso8601, message: brief(e))
      SlackNotifyJob.perform_async("Churn::ChurnedStoresSyncJob (#{Rails.env}) failed: #{brief(e)}") rescue nil
    ensure
      SyncStatus.release_lock(@lock_run_id) if @lock_run_id
    end

    private

    # Error text that is safe and short enough for the dashboard/Redis: Ruby 3.2's
    # NoMethodError message embeds the receiver's #inspect (for a Shop that is
    # every column, including access tokens), so strip any #<...> dump.
    def brief(e)
      msg = e.message.to_s
      if (i = msg.index('#<'))
        msg = "#{msg[0...i]}#{msg[i..][/\A#<[\w:]+/]}>" # drop the record dump entirely
      end
      "#{e.class}: #{msg}".squish.truncate(200)
    end

    # Churn rows from before the window whose store reinstalled or took a paid
    # plan again inside it: rebuild them so returned / returned_at / revenue
    # since return are current.
    def refresh_returners(since, client, errors)
      domains = PartnerAppEvent.where(occurred_at: (since - 2.days)..Time.current)
                               .where(event_type: PartnerAppEvent::INSTALLED)
                               .or(PartnerAppEvent.where(occurred_at: (since - 2.days)..Time.current,
                                                         event_type: PartnerAppEvent::CHARGE_ACTIVATED,
                                                         charge_test: false)
                                                  .where('charge_amount > 0'))
                               .distinct.pluck(:shopify_domain)
      return 0 if domains.empty?

      rows = ChurnedStore.where(shopify_domain: domains).where('churned_at < ?', since)
                         .order(churned_at: :desc).limit(MAX_RETURN_REFRESH).to_a
      refreshed = 0
      rows.group_by(&:shopify_domain).each do |domain, list|
        revenue = (StoreRevenue.fetch(domain, client: client) rescue nil)
        SyncStatus.refresh_lock(@lock_run_id)
        list.each do |row|
          candidate = ChurnDetector::Candidate.new(
            source_key: row.source_key, churn_type: row.churn_type, domain: domain,
            churned_at: row.churned_at, uninstalled_shop: row.uninstalled_shop,
            event: (PartnerAppEvent.find_by(id: row.source_key[/:pe:(\d+)\z/, 1]) if row.source_key.include?(':pe:'))
          )
          upsert(ChurnedStoreBuilder.new(candidate, revenue: revenue).attributes)
          refreshed += 1
        rescue => e
          errors << "refresh #{domain}: #{brief(e)}" if errors.size < 20
        end
      end
      refreshed
    end

    def upsert(attrs)
      row = ChurnedStore.find_or_initialize_by(source_key: attrs[:source_key])
      row.assign_attributes(attrs)
      row.save!
    end

    # Rows in the window whose churn no longer qualifies (e.g. the snapshot row
    # arrived and replaced a Partner-only uninstall, or a "cancellation" turned
    # out to precede an uninstall). Without Partner events we can't re-judge
    # event-based rows, so only snapshot-based rows are pruned then.
    def prune!(since, now, keys, events_ok)
      scope = ChurnedStore.in_period(since, now)
      scope = scope.where.not(source_key: keys) if keys.any?
      scope = scope.where("source_key LIKE 'uninstalled:us:%'") unless events_ok
      scope.delete_all
    end

    def status(attrs)
      SyncStatus.write(attrs)
    end
  end
end

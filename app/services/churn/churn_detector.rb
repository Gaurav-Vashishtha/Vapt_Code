# frozen_string_literal: true

module Churn
  # Finds churn events in a window and classifies them.
  #
  #   uninstalled            — an uninstalled_shops snapshot (UninstallNewJob), or a
  #                            Partner RELATIONSHIP_UNINSTALLED event with no snapshot
  #                            (e.g. the uninstall job failed).
  #   subscription_cancelled — SUBSCRIPTION_CHARGE_CANCELED with no replacement charge
  #                            and no uninstall around it.
  #   downgraded_to_free     — a paid charge cancelled and replaced by a $0 (Free) charge.
  #
  # Shopify cancels the old charge whenever a merchant switches plans, so a
  # cancellation next to a paid activation is a plan change, not churn; and it
  # cancels charges on uninstall, so a cancellation next to an uninstall is
  # already counted as an uninstall.
  class ChurnDetector
    Candidate = Struct.new(:source_key, :churn_type, :domain, :churned_at,
                           :uninstalled_shop, :event, keyword_init: true)

    SNAPSHOT_DEDUPE_WINDOW = 1.hour   # UninstallJob + UninstallNewJob double rows
    UNINSTALL_MATCH_WINDOW = 1.day    # snapshot <-> Partner uninstall event
    PLAN_SWITCH_WINDOW = 1.hour
    UNINSTALL_BEFORE_CANCEL = 1.hour
    UNINSTALL_AFTER_CANCEL = 24.hours

    def initialize(since:, until_time: Time.current)
      @since = since
      @until = until_time
    end

    def call
      uninstall_candidates + subscription_candidates
    end

    def uninstall_candidates
      rows = UninstalledShop.where(created_at: @since..@until)
                            .where.not(shop_domain: [nil, ''])
                            .order(:created_at).to_a
      partner_uninstalls = PartnerAppEvent.of_type(PartnerAppEvent::UNINSTALLED)
                                          .between(@since - UNINSTALL_MATCH_WINDOW, @until + UNINSTALL_MATCH_WINDOW)
                                          .to_a.group_by(&:shopify_domain)

      from_snapshots = dedupe(rows).map do |row|
        domain = normalize(row.shop_domain)
        Candidate.new(
          source_key: "uninstalled:us:#{row.id}",
          churn_type: 'uninstalled',
          domain: domain,
          churned_at: row.created_at,
          uninstalled_shop: row,
          event: closest(partner_uninstalls[domain], row.created_at, UNINSTALL_MATCH_WINDOW)
        )
      end

      from_partner = partner_uninstalls.values.flatten.select { |e| e.occurred_at.between?(@since, @until) }
      snapshot_times = UninstalledShop.where(shop_domain: from_partner.map(&:shopify_domain).uniq)
                                      .pluck(:shop_domain, :created_at)
                                      .group_by { |d, _| normalize(d) }
                                      .transform_values { |pairs| pairs.map(&:last) }
      partner_only = from_partner.reject do |e|
        Array(snapshot_times[e.shopify_domain]).any? { |t| (t - e.occurred_at).abs <= UNINSTALL_MATCH_WINDOW }
      end.map do |e|
        Candidate.new(source_key: "uninstalled:pe:#{e.id}", churn_type: 'uninstalled',
                      domain: e.shopify_domain, churned_at: e.occurred_at, event: e)
      end

      from_snapshots + partner_only
    end

    def subscription_candidates
      cancels = PartnerAppEvent.of_type(PartnerAppEvent::CHARGE_CANCELED).live_charges
                               .between(@since, @until).order(:occurred_at).to_a
      return [] if cancels.empty?

      domains = cancels.map(&:shopify_domain).uniq
      related = PartnerAppEvent.where(shopify_domain: domains)
                               .where(event_type: [PartnerAppEvent::UNINSTALLED, PartnerAppEvent::CHARGE_ACTIVATED])
                               .live_charges
                               .between(@since - 2.days, @until + 2.days)
                               .to_a.group_by(&:shopify_domain)
      snapshot_times = UninstalledShop.where(shop_domain: domains)
                                      .where(created_at: (@since - 2.days)..(@until + 2.days))
                                      .pluck(:shop_domain, :created_at)
                                      .group_by { |d, _| normalize(d) }
                                      .transform_values { |pairs| pairs.map(&:last) }

      cancels.filter_map do |cancel|
        t = cancel.occurred_at
        events = related[cancel.shopify_domain] || []
        uninstall_times = events.select { |e| e.event_type == PartnerAppEvent::UNINSTALLED }.map(&:occurred_at) +
                          Array(snapshot_times[cancel.shopify_domain])
        next if uninstall_times.any? { |u| u >= t - UNINSTALL_BEFORE_CANCEL && u <= t + UNINSTALL_AFTER_CANCEL }

        replacements = events.select do |e|
          e.event_type == PartnerAppEvent::CHARGE_ACTIVATED &&
            e.charge_id != cancel.charge_id &&
            (e.occurred_at - t).abs <= PLAN_SWITCH_WINDOW
        end

        type =
          if replacements.empty?
            'subscription_cancelled'
          elsif replacements.none?(&:paid_charge?) && cancel.paid_charge?
            'downgraded_to_free'
          end
        next unless type # paid→paid plan change, or Free re-approval

        Candidate.new(source_key: "#{type}:pe:#{cancel.id}", churn_type: type,
                      domain: cancel.shopify_domain, churned_at: t, event: cancel)
      end
    end

    private

    def dedupe(rows)
      rows.group_by { |r| normalize(r.shop_domain) }.flat_map do |_, list|
        list.each_with_index.reject do |row, i|
          nxt = list[i + 1]
          nxt && (nxt.created_at - row.created_at) < SNAPSHOT_DEDUPE_WINDOW
        end.map(&:first)
      end
    end

    def closest(events, time, window)
      Array(events).select { |e| (e.occurred_at - time).abs <= window }
                   .min_by { |e| (e.occurred_at - time).abs }
    end

    def normalize(domain)
      domain.to_s.strip.downcase
    end
  end
end

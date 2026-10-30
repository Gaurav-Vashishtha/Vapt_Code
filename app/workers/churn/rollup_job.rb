module Churn
  # Nightly engine. Builds per-shop activity/MRR/risk rollups from existing data,
  # denormalizes activity onto shops, writes churn_risk_snapshots, and fires the
  # actionable layer (Slack alerts + win-back) for newly high-value at-risk shops.
  class RollupJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    HIGH_VALUE_MRR = (ENV['CHURN_HIGH_VALUE_MRR'] || '15').to_f

    def perform(as_of = nil)
      today = (as_of ? Date.parse(as_of.to_s) : Date.current)
      yesterday = today - 1

      first_orders = OrderConfirmation.group(:shop_id).minimum(:created_at)
      last_orders  = OrderConfirmation.group(:shop_id).maximum(:created_at)
      orders_7d    = OrderConfirmation.where(created_at: (today - 7).beginning_of_day..today.end_of_day).group(:shop_id).count
      orders_prev  = OrderConfirmation.where(created_at: (today - 14).beginning_of_day..(today - 7).end_of_day).group(:shop_id).count
      orders_yday  = OrderConfirmation.where(created_at: yesterday.all_day).group(:shop_id).count
      sms_yday     = safe_group(TwilioLog, yesterday)
      wa_yday      = safe_group(WhatsappMessageLog, yesterday)
      otp_yday     = safe_group(PreOrderOtp, yesterday)
      onboarded    = OnboardingEvent.where(event: 'billing_approved').where.not(shop_id: nil).distinct.pluck(:shop_id).to_set
      disables     = recent_disables
      prev_bands   = ChurnRiskSnapshot.on_date(yesterday).pluck(:shop_id, :band).to_h

      scanned = 0
      counts = Hash.new(0)
      alerts = []

      Shop.find_each(batch_size: 500) do |shop|
        begin
          sid = shop.id
          first_at = first_orders[sid]
          last_at = last_orders[sid]
          installed_days = ((Time.current - shop.created_at) / 1.day).floor
          dso = last_at ? ((Time.current - last_at) / 1.day).floor : nil
          mrr = mrr_for(shop)

          features = {
            installed_days: installed_days,
            first_order_at: first_at,
            days_since_order: dso,
            orders_7d: orders_7d[sid].to_i,
            orders_prev_7d: orders_prev[sid].to_i,
            onboarding_complete: onboarded.include?(sid),
            paying_recently: mrr.positive?,
            currently_paying: shop.charge_id.present?,
            recent_feature_disable: disables[sid]
          }

          risk = Churn::RiskScorer.score(features)
          counts[risk[:band]] += 1
          scanned += 1

          shop.update_columns(
            first_order_at: first_at,
            last_order_at: last_at,
            last_active_at: last_at,
            onboarding_completed_at: shop.onboarding_completed_at,
            churn_risk_score: risk[:score],
            churn_risk_band: risk[:band],
            churn_risk_primary_factor: risk[:primary_factor],
            churn_risk_action: risk[:recommended_action],
            churn_risk_reasons: risk[:reasons],
            churn_risk_computed_at: Time.current
          )

          upsert_activity(sid, yesterday, orders_yday[sid].to_i, sms_yday[sid].to_i, wa_yday[sid].to_i, otp_yday[sid].to_i, last_at)
          upsert_mrr(shop, today, mrr)
          snap = upsert_risk_snapshot(shop, today, risk, mrr)

          if actionable?(risk[:band]) && mrr >= HIGH_VALUE_MRR && !actionable?(prev_bands[sid])
            alerts << snap
            enqueue_win_back(shop, 'at_risk')
          end
        rescue => e
          Rails.logger.error("[Churn::RollupJob] shop=#{shop.id} failed: #{e.class}: #{e.message}")
        end
      end

      notify(scanned, counts, alerts)
    end

    private

    def actionable?(band)
      %w[at_risk critical].include?(band)
    end

    def safe_group(klass, day)
      klass.where(created_at: day.all_day).group(:shop_id).count
    rescue
      {}
    end

    def recent_disables
      map = {}
      SettingsChangeAudit.disables.since(14.days.ago).order(:changed_at).each do |a|
        map[a.shop_id] = humanize_field(a.field)
      end
      map
    rescue
      {}
    end

    def humanize_field(field)
      field.to_s.sub(/_enabled\z/, '').tr('_', ' ').strip.titleize
    end

    def mrr_for(shop)
      price = shop.plan&.price.to_s.gsub(/[^0-9.]/, '').to_f
      usage = PartnerSale.of_type('usage').for_domain(shop.shopify_domain)
                         .where('occurred_at >= ?', 30.days.ago).sum(:net_amount).to_f rescue 0.0
      (price + usage).round(2)
    rescue
      0.0
    end

    def upsert_activity(shop_id, date, orders, sms, wa, otp, last_at)
      row = ShopActivityDaily.find_or_initialize_by(shop_id: shop_id, activity_date: date)
      row.assign_attributes(orders: orders, sms_sent: sms, whatsapp_sent: wa, otp_completions: otp, last_order_at: last_at)
      row.save!
    rescue => e
      Rails.logger.warn("[Churn::RollupJob] activity upsert failed shop=#{shop_id}: #{e.message}")
    end

    def upsert_mrr(shop, date, mrr)
      row = MrrSnapshot.find_or_initialize_by(shop_id: shop.id, snapshot_date: date)
      row.assign_attributes(
        shopify_domain: shop.shopify_domain,
        plan_name: shop.plan&.name,
        plan_price: shop.plan&.price.to_s.gsub(/[^0-9.]/, '').to_f,
        usage_trailing_30d: [mrr - shop.plan&.price.to_s.gsub(/[^0-9.]/, '').to_f, 0].max,
        mrr: mrr,
        currency: shop.currency
      )
      row.save!
    rescue => e
      Rails.logger.warn("[Churn::RollupJob] mrr upsert failed shop=#{shop.id}: #{e.message}")
    end

    def upsert_risk_snapshot(shop, date, risk, mrr)
      row = ChurnRiskSnapshot.find_or_initialize_by(shop_id: shop.id, snapshot_date: date)
      row.assign_attributes(
        shopify_domain: shop.shopify_domain,
        score: risk[:score],
        band: risk[:band],
        primary_factor: risk[:primary_factor],
        recommended_action: risk[:recommended_action],
        reasons: risk[:reasons],
        mrr: mrr
      )
      row.save!
      row
    end

    def enqueue_win_back(shop, trigger)
      return if WinBackOutreach.recent_for(shop.id, trigger).exists?
      WinBackOutreach.create!(shop_id: shop.id, shopify_domain: shop.shopify_domain, trigger: trigger, status: 'pending')
      Churn::WinBackJob.perform_async(shop.id, trigger)
    rescue => e
      Rails.logger.warn("[Churn::RollupJob] win-back enqueue failed shop=#{shop.id}: #{e.message}")
    end

    def notify(scanned, counts, alerts)
      summary = ":bar_chart: Churn rollup (#{Rails.env}) — scanned #{scanned} shops | " \
                "healthy #{counts['healthy']} · watch #{counts['watch']} · at_risk #{counts['at_risk']} · critical #{counts['critical']}"
      if alerts.any?
        lines = alerts.first(15).map { |s| "• #{s.shopify_domain} — #{s.band} (#{s.score}), MRR $#{s.mrr} — #{s.recommended_action}" }
        summary += "\n:rotating_light: #{alerts.size} high-value shop(s) newly at-risk:\n#{lines.join("\n")}"
      end
      SlackNotifyJob.perform_async(summary)
    rescue => e
      Rails.logger.error("[Churn::RollupJob] notify failed: #{e.message}")
    end
  end
end

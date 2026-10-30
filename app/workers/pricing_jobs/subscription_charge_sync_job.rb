# frozen_string_literal: true

module PricingJobs
  # Fallback job: scans shops with id > 40000, syncs charge_id and plan from Shopify.
  # Two cases: (1) Free plan with billing activated — charge_id must match active charge.
  # (2) Free plan with no active charge — charge_id must be nil. Sends report to Slack.
  # Shops whose domain is in SKIP_DOMAINS are not synced.
  class SubscriptionChargeSyncJob < ApplicationJob
    sidekiq_options queue: "administration"

    SKIP_DOMAINS = %w[
      codkingdemo.myshopify.com
      democodking.myshopify.com
      c-store24.myshopify.com
      kingcodtest.myshopify.com
      6df069.myshopify.com
    ].freeze

    def perform(*_args)
      Rails.logger.info "[SubscriptionChargeSyncJob] Starting sync for shops with id > 40000..."

      free_plan = Plan.find_by(name: "Free")
      unless free_plan
        Rails.logger.error "[SubscriptionChargeSyncJob] Free plan not found. Aborting."
        SlackNotifier::CLIENT.ping(text: ":x: *SubscriptionChargeSyncJob* (#{Rails.env}) — Free plan not found in DB. Job aborted.")
        return
      end

      scope = Shop.where("id > ?", 1_000).order(:id)
      total = scope.count
      synced_charge = 0
      synced_plan = 0
      reset_to_free = 0
      skipped_ok = 0
      skipped_domain = 0
      errors = []

      scope.find_each do |shop|
        if SKIP_DOMAINS.include?(shop.shopify_domain)
          skipped_domain += 1
          next
        end
        begin
          shop.init_session
          all_charges = ShopifyAPI::RecurringApplicationCharge.all
          active_charge = all_charges.find { |c| c.status == "active" }

          if active_charge
            # Case 1: Active charge (Free or paid) — keep charge_id and plan in sync.
            charge_id_str = active_charge.id.to_s
            plan_from_charge = Plan.find_by(name: active_charge.name)

            updated_charge = false
            updated_plan = false

            if shop.charge_id.to_s != charge_id_str
              shop.update_column(:charge_id, charge_id_str)
              synced_charge += 1
              updated_charge = true
            end

            if plan_from_charge && (shop.plan_id != plan_from_charge.id)
              shop.update_column(:plan_id, plan_from_charge.id)
              synced_plan += 1
              updated_plan = true
            end

            skipped_ok += 1 unless updated_charge || updated_plan
          else
            # Case 2: No active charge — Free plan, charge_id must be nil.
            if shop.charge_id.present? || (shop.plan_id != free_plan.id)
              shop.update_columns(charge_id: nil, plan_id: free_plan.id)
              reset_to_free += 1
            else
              skipped_ok += 1
            end
          end
        rescue => e
          errors << "Shop #{shop.id} (#{shop.shopify_domain}): #{e.message}"
          Rails.logger.warn "[SubscriptionChargeSyncJob] Shop #{shop.id} #{shop.shopify_domain}: #{e.message}"
        end
      end

      report = build_slack_report(
        total: total,
        synced_charge: synced_charge,
        synced_plan: synced_plan,
        reset_to_free: reset_to_free,
        skipped_ok: skipped_ok,
        skipped_domain: skipped_domain,
        errors: errors
      )
      SlackNotifier::CLIENT.ping(text: report)
      Rails.logger.info "[SubscriptionChargeSyncJob] Completed. #{report.gsub("\n", " ")}"
    end

    private

    def build_slack_report(total:, synced_charge:, synced_plan:, reset_to_free:, skipped_ok:, skipped_domain:, errors:)
      lines = [
        ":wrench: *Subscription Charge Sync Report* (#{Rails.env})",
        "*Scope:* Shops with ID > 1000",
        "*Total processed:* #{total}",
        "*Charge ID updated:* #{synced_charge}",
        "*Plan updated:* #{synced_plan}",
        "*Reset to Free (no active subscription):* #{reset_to_free}",
        "*Skipped (already in sync):* #{skipped_ok}",
        "*Skipped (domain in skip list):* #{skipped_domain}"
      ]
      if errors.any?
        lines << "*Errors (#{errors.size}):*"
        errors.first(10).each { |msg| lines << "  • #{msg}" }
        lines << "  ... and #{errors.size - 10} more" if errors.size > 10
      end
      lines.join("\n")
    end
  end
end

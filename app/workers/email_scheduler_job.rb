# frozen_string_literal: true

# Runs every 6 hours. For each active email rule, finds candidate shops, creates pending scheduled_emails
# (no duplicate: unique on rule+shop). For each pending delivery:
# - If scheduled_at is in the past: send now (after re-checking criteria).
# - If scheduled_at is within the next 12 hours: enqueue SendScheduledEmailJob.perform_at(scheduled_at)
#   so it sends at the exact time without waiting for the next cron.
# - If scheduled_at is beyond 12 hours: do nothing (next cron run will enqueue or send).
# Rescheduled items are moved back to pending when scheduled_at has passed.
class EmailSchedulerJob < ApplicationJob
  queue_as :default

  WINDOW_HOURS = 12

  def perform
    # Move rescheduled items whose scheduled_at has passed back to pending
    ScheduledEmail.rescheduled.where("scheduled_at <= ?", Time.current).update_all(status: "pending")

    EmailRule.active.find_each do |rule|
      process_rule(rule)
    end
  end

  private

  def process_rule(rule)
    if EmailRuleEvaluatorService.rule_target(rule) == "uninstalled_shops"
      candidate_ids = EmailRuleEvaluatorService.candidate_uninstalled_shop_ids_for_rule(rule)
      candidate_ids.each { |uninstalled_shop_id| create_pending_uninstalled_if_missing(rule.id, uninstalled_shop_id) }
    else
      candidate_ids = EmailRuleEvaluatorService.candidate_shop_ids_for_rule(rule)
      candidate_ids.each { |shop_id| create_pending_shop_if_missing(rule.id, shop_id) }
    end

    # Use UTC explicitly so comparison is independent of config.time_zone
    now_utc = Time.current.utc
    window_end_utc = WINDOW_HOURS.hours.from_now.utc

    ScheduledEmail.pending.where(email_rule: rule).find_each do |scheduled_email|
      next if scheduled_email.scheduled_at.blank?
      scheduled_at_utc = scheduled_email.scheduled_at.utc

      # If scheduled time (UTC) has already passed, reschedule for next occurrence (e.g. tomorrow 11:20 local)
      if scheduled_at_utc < now_utc
        refresh_scheduled_at(scheduled_email)
        scheduled_email.reload
        next if scheduled_email.scheduled_at.blank?
        scheduled_at_utc = scheduled_email.scheduled_at.utc
      end

      # If it's time (or past) send immediately (no Sidekiq schedule needed)
      if scheduled_at_utc <= now_utc
        send_or_skip(scheduled_email)
        next
      end

      # Only schedule once per scheduled_at value. If we've already enqueued a job for this
      # exact timestamp, do nothing so the job is idempotent across multiple runs.
      if scheduled_at_utc <= window_end_utc
        if scheduled_email.send_job_enqueued_for != scheduled_email.scheduled_at
          SendScheduledEmailJob.perform_at(scheduled_email.scheduled_at, scheduled_email.id)
          scheduled_email.update_column(:send_job_enqueued_for, scheduled_email.scheduled_at)
        end
      end
    end
  rescue => e
    Rails.logger.error "[EmailSchedulerJob] Rule #{rule.id} (#{rule.slug}): #{e.message}"
  end

  def create_pending_shop_if_missing(rule_id, shop_id)
    rule = EmailRule.find_by(id: rule_id)
    shop = Shop.find_by(id: shop_id)
    return if rule.nil? || shop.nil?
    recipient = shop.owner_email.presence || shop.customer_email
    return if recipient.blank? || UnsubscribedEmail.for_email(recipient).exists?
    scheduled_at = EmailRuleScheduledAtService.call(rule, shop: shop)
    ScheduledEmail.find_or_create_by!(email_rule_id: rule_id, shop_id: shop_id) do |se|
      se.status = "pending"
      se.scheduled_at = scheduled_at
    end
  rescue ActiveRecord::RecordNotUnique
    # Already exists (race), ignore
  end

  def create_pending_uninstalled_if_missing(rule_id, uninstalled_shop_id)
    rule = EmailRule.find_by(id: rule_id)
    uninstalled_shop = UninstalledShop.find_by(id: uninstalled_shop_id)
    return if rule.nil? || uninstalled_shop.nil?
    recipient = uninstalled_shop.email
    return if recipient.blank? || UnsubscribedEmail.for_email(recipient).exists?
    scheduled_at = EmailRuleScheduledAtService.call(rule, uninstalled_shop: uninstalled_shop)
    ScheduledEmail.find_or_create_by!(email_rule_id: rule_id, uninstalled_shop_id: uninstalled_shop_id) do |se|
      se.status = "pending"
      se.scheduled_at = scheduled_at
    end
  rescue ActiveRecord::RecordNotUnique
    # Already exists (race), ignore
  end

  # When scheduled_at is in the past, recompute next occurrence (tomorrow at same local time) and update record.
  # For hours_after_installation there is no "next" occurrence — leave scheduled_at so send runs once.
  def refresh_scheduled_at(scheduled_email)
    rule = scheduled_email.email_rule
    if rule.date_rule_type == "hours_after_installation"
      # One-shot: do not change scheduled_at; scheduler will send on next check
      return
    end
    new_at = if scheduled_email.shop_id?
      shop = scheduled_email.shop
      EmailRuleScheduledAtService.call(
        rule,
        shop: shop,
        exclude_scheduled_email_id: scheduled_email.id
      )
    else
      uninstalled_shop = scheduled_email.uninstalled_shop
      EmailRuleScheduledAtService.call(
        rule,
        uninstalled_shop: uninstalled_shop,
        exclude_scheduled_email_id: scheduled_email.id
      )
    end
    scheduled_email.update_column(:scheduled_at, new_at)
  end

  def send_or_skip(scheduled_email)
    # Caller ensures scheduled_at <= now; service re-checks criteria and sends (or skips)
    ScheduledEmailSendService.call(scheduled_email)
  end
end

# frozen_string_literal: true

# Single place for sending (or skipping) a scheduled email. Re-checks rule criteria before sending,
# enforces one-email-per-recipient-per-day, then sends and updates status.
# Used by EmailSchedulerJob (immediate send) and SendScheduledEmailJob (scheduled send).
class ScheduledEmailSendService
  class << self
    # @param scheduled_email [ScheduledEmail]
    # @return [void]
    def call(scheduled_email)
      scheduled_email.reload
      return unless scheduled_email.pending?

      # Never send if scheduled time (UTC) has not been reached — guard against timezone/clock bugs
      if scheduled_email.scheduled_at.present? && scheduled_email.scheduled_at.utc > Time.current.utc
        Rails.logger.warn "[ScheduledEmailSendService] Skipping send #{scheduled_email.id}: scheduled_at #{scheduled_email.scheduled_at.utc} is in the future (now #{Time.current.utc})"
        return
      end

      rule = scheduled_email.email_rule

      # Re-check criteria: if rule no longer satisfied (e.g. preorder OTP became true), skip
      if scheduled_email.shop_id?
        unless EmailRuleEvaluatorService.rule_satisfied_for_shop?(rule, scheduled_email.shop)
          scheduled_email.update!(status: "skipped", error_message: "Skipped: criteria not valid anymore")
          return
        end
      else
        unless EmailRuleEvaluatorService.rule_satisfied_for_uninstalled_shop?(rule, scheduled_email.uninstalled_shop)
          scheduled_email.update!(status: "skipped", error_message: "Skipped: criteria not valid anymore")
          return
        end
      end

      to_email = scheduled_email.recipient_email
      if to_email.blank?
        scheduled_email.update!(status: "skipped", error_message: "No recipient email")
        return
      end

      if UnsubscribedEmail.for_email(to_email).exists?
        scheduled_email.update!(status: "skipped", error_message: "Recipient has unsubscribed")
        return
      end

      # At most one email per recipient per day: if we already sent another rule to this recipient today, reschedule (test emails bypass this)
      if !test_email?(to_email) && already_sent_to_recipient_today?(scheduled_email)
        scheduled_email.update!(
          status: "rescheduled",
          scheduled_at: 2.days.from_now,
          send_job_enqueued_for: nil,
          error_message: "Rescheduled: recipient already received an email today"
        )
        return
      end

      scheduled_email.update_column(:open_tracking_token, SecureRandom.urlsafe_base64(32)) if scheduled_email.open_tracking_token.blank?

      ScheduledEmailMailer.rule_email(scheduled_email).deliver_now
      scheduled_email.update!(status: "sent", sent_at: Time.current, send_job_enqueued_for: nil, error_message: nil)
    rescue => e
      scheduled_email.update!(status: "failed", send_job_enqueued_for: nil, error_message: e.message)
      Rails.logger.error "[ScheduledEmailSendService] Send failed #{scheduled_email.id}: #{e.message}"
    end

    TEST_EMAILS = %w[support@notifiktech.com adbhatia1989@gmail.com].freeze

    private

    def test_email?(email)
      return false if email.blank?
      TEST_EMAILS.include?(email.to_s.downcase.strip)
    end

    def already_sent_to_recipient_today?(scheduled_email)
      today_start = Time.current.beginning_of_day
      scope = ScheduledEmail.sent.where("sent_at >= ?", today_start)
      if scheduled_email.shop_id?
        scope.where(shop_id: scheduled_email.shop_id).where.not(id: scheduled_email.id).exists?
      else
        scope.where(uninstalled_shop_id: scheduled_email.uninstalled_shop_id).where.not(id: scheduled_email.id).exists?
      end
    end
  end
end

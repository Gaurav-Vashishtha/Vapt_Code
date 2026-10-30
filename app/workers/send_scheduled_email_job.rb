# frozen_string_literal: true

# One-off job enqueued for a specific scheduled_at time. Runs at that time and sends the email
# (after re-checking criteria). Only used for deliveries within the next 12 hours to avoid
# scheduling thousands of future jobs in Redis.
# Uses sidekiq-unique-jobs so that multiple perform_at calls with the same scheduled_email_id
# coalesce into a single scheduled job (idempotent with respect to EmailSchedulerJob reruns).
class SendScheduledEmailJob < ApplicationJob
  sidekiq_options lock: :until_executed,
                  lock_args: ->(args) { [args.first] }

  def perform(scheduled_email_id)
    scheduled_email = ScheduledEmail.find_by(id: scheduled_email_id)
    return unless scheduled_email
    ScheduledEmailSendService.call(scheduled_email)
  end
end

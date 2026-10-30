# frozen_string_literal: true

module CodForm
  # Retention of cod_form_sessions (ARCHITECTURE.md B.8, NFR-8). Daily.
  #   - rows older than 90 days are deleted
  #   - ordered rows older than 30 days lose contact, address, ip and the other buyer data
  #   - open rows past their token expiry by a day are marked expired
  class SessionPurgeJob < ApplicationJob
    sidekiq_options queue: "low", retry: 1

    DELETE_AFTER = 90.days
    BLANK_AFTER = 30.days
    BATCH = 5_000
    MAX_BATCHES = 200

    def perform
      deleted = in_batches(CodForm::Session.where("created_at < ?", DELETE_AFTER.ago)) { |ids| CodForm::Session.where(id: ids).delete_all }

      blanked = in_batches(
        CodForm::Session.where(status: CodForm::Session::STATUS_ORDERED)
                        .where("ordered_at < ?", BLANK_AFTER.ago)
                        .where("contact <> '{}'::jsonb OR address <> '{}'::jsonb OR ip IS NOT NULL")
      ) do |ids|
        CodForm::Session.where(id: ids).update_all(
          [
            "contact = '{}'::jsonb, address = '{}'::jsonb, custom_fields = '{}'::jsonb, ip = NULL, user_agent = NULL, " \
            "phone_normalized = NULL, email_normalized = NULL, " \
            "quote_snapshot = quote_snapshot - 'order_response', updated_at = ?",
            Time.current
          ]
        )
      end

      expired = CodForm::Session
                .where(status: [CodForm::Session::STATUS_OPEN, CodForm::Session::STATUS_OTP_PENDING, CodForm::Session::STATUS_BLOCKED])
                .where(order_id: nil).where("expires_at < ?", 1.day.ago)
                .where("contact = '{}'::jsonb")
                .limit(BATCH * 10)
                .update_all(status: CodForm::Session::STATUS_EXPIRED, updated_at: Time.current)

      Rails.logger.info("[CodForm::SessionPurgeJob] deleted=#{deleted} blanked=#{blanked} expired=#{expired}")
    end

    private

    def in_batches(scope)
      total = 0
      MAX_BATCHES.times do
        ids = scope.limit(BATCH).pluck(:id)
        break if ids.empty?

        yield ids
        total += ids.size
        break if ids.size < BATCH
      end
      total
    end
  end
end

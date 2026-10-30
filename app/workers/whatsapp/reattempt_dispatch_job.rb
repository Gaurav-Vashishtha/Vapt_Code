# frozen_string_literal: true

module Whatsapp
  # Cron (every 5 min): resends WhatsApp messages whose retry is due.
  #
  # Each due WhatsappReattempt is claimed (pending → sending) so overlapping
  # runs never send twice, checked for relevance (verified / recovered /
  # superseded → cancelled), then resent on its original row. A resend that is
  # refused straight away counts as an attempt and is rescheduled or dropped;
  # one that is accepted waits for the delivery webhook.
  class ReattemptDispatchJob < ApplicationJob
    sidekiq_options queue: 'default', retry: false

    BATCH = 200

    def perform
      ids = WhatsappReattempt.due.order(:next_retry_at).limit(BATCH).pluck(:id)
      ids.each { |id| process(id) }
    end

    private

    def process(id)
      claimed = WhatsappReattempt.where(id: id)
                                 .merge(WhatsappReattempt.due)
                                 .update_all(status: 'sending', updated_at: Time.current)
      return unless claimed == 1

      reattempt = WhatsappReattempt.find(id)
      return ReattemptRecorder.finish(reattempt, 'dropped', 'flow_disabled') unless ReattemptPolicy.for(reattempt.flow).enabled?

      if (reason = ReattemptRelevance.skip_reason(reattempt))
        return ReattemptRecorder.finish(reattempt, 'cancelled', reason)
      end

      result = ReattemptSender.call(reattempt)
      reattempt.attempts += 1

      if result.ok
        reattempt.update!(status: 'sent', provider_message_id: result.provider_message_id, next_retry_at: nil)
        ReattemptRecorder.mark_source(reattempt, :sent)
      else
        reattempt.error_code = ReattemptPolicy.normalize_code(result.error_code).presence || result.error_code.to_s
        reattempt.error_message = result.error_message.to_s.truncate(1000)
        ReattemptRecorder.schedule_or_drop(reattempt)
      end
    rescue StandardError => e
      Rails.logger.error("[whatsapp/reattempt] #{id} failed: #{e.class}: #{e.message}")
      # Back to pending so the next run picks it up; the stale-sending guard
      # covers the case where even this update fails.
      WhatsappReattempt.where(id: id, status: 'sending').update_all(status: 'pending', updated_at: Time.current)
    end
  end
end

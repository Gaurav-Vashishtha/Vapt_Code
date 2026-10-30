# frozen_string_literal: true

module Whatsapp
  # Turns a delivery failure into retry state (or ignores it).
  #
  # Called by the MSG91 delivery webhook and the Meta (BSP) webhook. The first
  # retryable failure of a message creates its WhatsappReattempt; a failure of a
  # later resend schedules the next attempt. Each attempt is timed from the
  # first failure; when the schedule runs out the message is dropped.
  #
  # The original row keeps one status the whole way through:
  #   MSG91 (TwilioLog / AbandonedCart): RETRY_PENDING → SUCCESS (resend accepted) | DROPPED
  #   BSP (WhatsappMessageLog):          retry_pending → sent (resend accepted)    | dropped
  # Rows in RETRY_PENDING / DROPPED are not billed.
  module ReattemptRecorder
    MSG91_RETRY_PENDING = 'RETRY_PENDING'
    MSG91_DROPPED = 'DROPPED'
    MSG91_SUCCESS = 'SUCCESS'

    module_function

    # capture: what Msg91SendCapture.fetch returned for the event's ids.
    def record_msg91_failure(capture:, error_code:, error_message:, at: Time.current)
      policy = ReattemptPolicy.for('msg91')
      return unless policy.retryable?(error_code)

      source = capture['source_type'].safe_constantize&.find_by(id: capture['source_id'])
      return unless source

      record(
        flow: 'msg91', source: source, shop_id: capture['shop_id'], provider_id: capture['provider_id'],
        request: { 'url' => capture['url'], 'body' => capture['body'] },
        error_code: error_code, error_message: error_message, at: at, policy: policy
      )
    end

    def record_bsp_failure(log:, error_code:, error_message:, at: Time.current)
      policy = ReattemptPolicy.for('bsp')
      return unless policy.retryable?(error_code)
      return if log.shop_id.blank? # partner (custom-branded) sends are out of scope
      return if log.whatsapp_campaign_id.present? # campaigns keep their own per-campaign retry

      record(
        flow: 'bsp', source: log, shop_id: log.shop_id, provider_id: log.meta_message_id,
        request: {}, error_code: error_code, error_message: error_message, at: at, policy: policy
      )
    end

    # A resend we made was delivered (or read).
    def record_delivered(reattempt)
      return unless reattempt&.status == 'sent'

      reattempt.update!(status: 'delivered', finished_at: Time.current)
    end

    # Shared by both flows. Returns the WhatsappReattempt, or nil when ignored.
    def record(flow:, source:, shop_id:, provider_id:, request:, error_code:, error_message:, at:, policy:)
      reattempt = WhatsappReattempt.find_by(source_type: source.class.name, source_id: source.id)

      if reattempt
        # Only a failure of the attempt currently in flight moves the schedule
        # on; duplicates and stale webhooks for older attempts are ignored.
        return nil unless reattempt.status == 'sent' && reattempt.provider_message_id.to_s == provider_id.to_s
      else
        reattempt = WhatsappReattempt.new(
          flow: flow, source: source, shop_id: shop_id, request: request,
          provider_message_id: provider_id, first_failed_at: at, attempts: 0
        )
      end

      reattempt.error_code = ReattemptPolicy.normalize_code(error_code).presence || error_code.to_s
      reattempt.error_message = error_message.to_s.truncate(1000)
      schedule_or_drop(reattempt, policy)
      reattempt
    rescue ActiveRecord::RecordNotUnique
      nil # a concurrent webhook for the same message already created it
    end

    # After a failed attempt (webhook or synchronous): next slot, or drop.
    def schedule_or_drop(reattempt, policy = ReattemptPolicy.for(reattempt.flow))
      next_at = policy.next_retry_at(reattempt.first_failed_at, reattempt.attempts)
      if next_at
        reattempt.assign_attributes(status: 'pending', next_retry_at: [next_at, Time.current].max)
        reattempt.save!
        mark_source(reattempt, :retry_pending)
      else
        finish(reattempt, 'dropped', 'retries_exhausted')
      end
    end

    # status: 'dropped' (gave up) or 'cancelled' (no longer worth sending).
    def finish(reattempt, status, reason)
      reattempt.assign_attributes(status: status, drop_reason: reason, next_retry_at: nil, finished_at: Time.current)
      reattempt.save!
      mark_source(reattempt, :dropped)
    end

    # Updates only the existing status column of the original row (no new
    # columns on the big tables). update_columns skips callbacks on purpose:
    # this is bookkeeping, not a new send.
    def mark_source(reattempt, state)
      source = reattempt.source
      return unless source

      if reattempt.bsp?
        value = { retry_pending: :retry_pending, dropped: :dropped, sent: :sent }.fetch(state)
        source.update_columns(status: WhatsappMessageLog.statuses[value.to_s], updated_at: Time.current)
      else
        value = { retry_pending: MSG91_RETRY_PENDING, dropped: MSG91_DROPPED, sent: MSG91_SUCCESS }.fetch(state)
        # updated_at left alone: billing reports bucket abandoned carts by it.
        attrs = { status: value }
        attrs[:sid] = reattempt.provider_message_id if state == :sent && reattempt.provider_message_id.present?
        source.update_columns(attrs)
      end
    end
  end
end

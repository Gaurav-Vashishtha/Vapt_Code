module Whatsapp
  # Mirrors a Meta delivery-status webhook onto the campaign recipient and moves
  # the campaign's denormalized counters between buckets (sent → delivered → read,
  # or → failed). Forward-only, matching WhatsappMessageLog#advance_status!.
  module CampaignStatusUpdater
    ORDER = %w[pending queued sent delivered read].freeze
    COLS = { 'sent' => 'sent_count', 'delivered' => 'delivered_count',
             'read' => 'read_count', 'failed' => 'failed_count' }.freeze

    module_function

    def apply(log, status, at)
      mapped = %w[delivered read failed].include?(status) ? status : nil
      return unless mapped

      recipient = WhatsappCampaignRecipient.find_by(id: log.whatsapp_campaign_recipient_id) ||
                  WhatsappCampaignRecipient.find_by(meta_message_id: log.meta_message_id)
      return unless recipient

      old = recipient.status
      if mapped == 'failed'
        return if %w[failed retry_pending].include?(old)
        campaign = WhatsappCampaign.find_by(id: log.whatsapp_campaign_id)
        if campaign && CampaignRetryPolicy.schedule_retry!(recipient, campaign, error_code: log.error_code,
                                                          error_message: log.error_message, at: at)
          adjust(campaign.id, old, 'retry_pending')
          reopen_for_retry(campaign, recipient)
          return
        end
        recipient.update_columns(status: 'failed', failed_at: at, error_code: log.error_code,
                                 error_message: log.error_message, updated_at: Time.current)
        adjust(log.whatsapp_campaign_id, old, 'failed')
        Whatsapp::SendPolicy.release!(campaign, recipient) if campaign
      else
        return if ORDER.index(old).to_i >= ORDER.index(mapped).to_i
        recipient.update_columns({ status: mapped, "#{mapped}_at" => at, updated_at: Time.current })
        adjust(log.whatsapp_campaign_id, old, mapped)
      end
    end

    # A delivery-failed webhook can land after the dispatch loop already
    # completed the campaign; the retry would otherwise never be picked up.
    # Parking the campaign back as retry_waiting puts it on the scheduler's
    # radar exactly like a dispatcher-parked retry.
    def reopen_for_retry(campaign, recipient)
      next_at = recipient.next_retry_at
      return if next_at.blank?

      case campaign.status
      when 'completed'
        campaign.update_columns(status: 'retry_waiting', scheduled_at: next_at, completed_at: nil, updated_at: Time.current)
      when 'retry_waiting'
        if campaign.scheduled_at.blank? || next_at < campaign.scheduled_at
          campaign.update_columns(scheduled_at: next_at, updated_at: Time.current)
        end
      end
    end

    def adjust(campaign_id, old, new)
      inc = COLS[new]
      dec = COLS[old]
      parts = []
      parts << "#{inc} = #{inc} + 1" if inc
      parts << "#{dec} = GREATEST(#{dec} - 1, 0)" if dec && dec != inc
      WhatsappCampaign.where(id: campaign_id).update_all(parts.join(', ')) if parts.any?
    end
  end
end

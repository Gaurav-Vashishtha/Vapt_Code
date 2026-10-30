module Whatsapp
  # Last-mile opt-out re-check guards against an opt-out that landed after the
  # audience snapshot.
  class SendCampaignMessageJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: false

    HOLD_STATUSES = %w[paused scheduled].freeze

    def perform(recipient_id)
      recipient = WhatsappCampaignRecipient.find_by(id: recipient_id)
      return unless recipient
      return unless recipient.status == 'queued'
      campaign = recipient.whatsapp_campaign
      unless campaign&.status.in?(%w[sending testing])
        recipient.return_to_pending! if campaign && HOLD_STATUSES.include?(campaign.status)
        return
      end
      return recipient.return_to_pending! if campaign.status == 'sending' && Whatsapp::SendPolicy.in_quiet_hours?(campaign)

      account = campaign.whatsapp_account || campaign.shop.whatsapp_account
      template = campaign.whatsapp_template
      return mark_failed(recipient, 'no_account_or_template') unless account&.ready_to_send? && template&.approved?

      if WhatsappOptOut.opted_out?(campaign.shop_id, recipient.phone)
        recipient.suppress!('opted_out')
        WhatsappCampaign.where(id: campaign.id).update_all('suppressed_count = suppressed_count + 1')
        return
      end

      missing = Whatsapp::CampaignMessageBuilder.missing_values(campaign, recipient)
      if missing.any?
        # Sending anyway would fail at Meta with #131008; a suppression with a
        # readable reason is more actionable in the report than a Meta error.
        recipient.suppress!("missing_variable: #{missing.join(', ')}")
        WhatsappCampaign.where(id: campaign.id).update_all('suppressed_count = suppressed_count + 1')
        return
      end

      if recipient.attempt_count.to_i.zero? && campaign.status == 'sending' &&
         Whatsapp::SendPolicy.frequency_capped?(campaign, recipient)
        recipient.suppress!('frequency_cap')
        WhatsappCampaign.where(id: campaign.id).update_all('suppressed_count = suppressed_count + 1')
        return
      end

      attempt = recipient.attempt_count.to_i + 1
      recipient.update_columns(attempt_count: attempt, last_attempt_at: Time.current, updated_at: Time.current)

      source_id = attempt == 1 ? "wac:#{campaign.id}:#{recipient.id}" : "wac:#{campaign.id}:#{recipient.id}:a#{attempt}"
      log = ::Meta::SendTemplateMessageService.call(
        account: account,
        template: template,
        recipient: recipient.phone,
        body_parameters: Whatsapp::CampaignMessageBuilder.body_parameters(campaign, recipient),
        header_parameters: Whatsapp::CampaignMessageBuilder.header_parameters(campaign, template, recipient),
        event_type_key: 'campaign_broadcast',
        payload_snapshot: { 'campaign_id' => campaign.id, 'fields' => recipient.fields, 'attempt' => attempt },
        button_slug: Whatsapp::CampaignMessageBuilder.button_slug(campaign, recipient),
        source_external_id: source_id
      )

      apply_log(recipient, campaign, log)
    rescue ::Meta::SendTemplateMessageService::Error => e
      mark_failed(recipient, e.message, error_code: failed_log_code(campaign, source_id))
      if campaign
        Whatsapp::SendPolicy.release!(campaign, recipient)
        Whatsapp::CampaignGuardrails.on_send_failure(campaign, recipient.error_code)
      end
    rescue => e
      Rails.logger.error("[Whatsapp::SendCampaignMessageJob] recipient=#{recipient_id} #{e.class}: #{e.message}")
      mark_failed(recipient, "#{e.class}: #{e.message}") if recipient
      Whatsapp::SendPolicy.release!(campaign, recipient) if campaign && recipient
    end

    private

    def apply_log(recipient, campaign, log)
      return mark_failed(recipient, 'no log returned') unless log

      log.update_columns(
        whatsapp_campaign_id: campaign.id,
        whatsapp_campaign_recipient_id: recipient.id,
        updated_at: Time.current
      )

      if log.status.to_s == 'failed'
        recipient.update_columns(meta_message_id: log.meta_message_id, whatsapp_message_log_id: log.id, updated_at: Time.current)
        if Whatsapp::CampaignRetryPolicy.schedule_retry!(recipient, campaign, error_code: log.error_code, error_message: log.error_message)
          Whatsapp::CampaignGuardrails.on_send_failure(campaign, log.error_code)
          return
        end
        recipient.update_columns(status: 'failed', error_code: log.error_code,
                                 error_message: log.error_message, failed_at: Time.current, updated_at: Time.current)
        WhatsappCampaign.where(id: campaign.id).update_all('failed_count = failed_count + 1')
        Whatsapp::SendPolicy.release!(campaign, recipient)
        Whatsapp::CampaignGuardrails.on_send_failure(campaign, log.error_code)
      else
        recipient.update_columns(status: 'sent', meta_message_id: log.meta_message_id,
                                 whatsapp_message_log_id: log.id, sent_at: Time.current, updated_at: Time.current)
        WhatsappCampaign.where(id: campaign.id).update_all('sent_count = sent_count + 1')
        Whatsapp::SendPolicy.record_send!(campaign, recipient)
      end
    end

    def mark_failed(recipient, reason, error_code: nil)
      columns = { status: 'failed', error_message: reason.to_s, failed_at: Time.current, updated_at: Time.current }
      columns[:error_code] = error_code if error_code.present?
      recipient.update_columns(columns)
      WhatsappCampaign.where(id: recipient.whatsapp_campaign_id).update_all('failed_count = failed_count + 1')
    end

    # The send service raises on a synchronous Meta error after stamping the
    # code on its log row, which isn't linked to the campaign yet.
    def failed_log_code(campaign, source_id)
      return nil if campaign.nil? || source_id.blank?

      WhatsappMessageLog.where(shop_id: campaign.shop_id, event_type_key: 'campaign_broadcast', source_external_id: source_id)
                        .order(id: :desc).pick(:error_code).presence
    rescue StandardError
      nil
    end
  end
end

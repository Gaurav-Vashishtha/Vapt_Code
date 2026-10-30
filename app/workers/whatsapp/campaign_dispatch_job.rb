module Whatsapp
  # Waiting states (future retries, quiet hours) park the campaign with a
  # scheduled_at for CampaignSchedulerJob to pick up, so no dispatch loop sits
  # idle for hours holding a concurrency slot.
  class CampaignDispatchJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1

    def perform(campaign_id)
      campaign = WhatsappCampaign.find_by(id: campaign_id)
      return unless campaign
      return unless campaign.status == 'sending'

      now = Time.current
      return if hold_for_quiet_hours(campaign, now)
      return if Whatsapp::CampaignGuardrails.enforce_quality!(campaign)
      return if Whatsapp::CampaignGuardrails.check_failure_spike!(campaign)

      rate = [campaign.rate_per_minute.to_i, 1].max
      batch = campaign.recipients.due_for_send(now).limit(rate).to_a

      if batch.empty?
        if campaign.recipients.where(status: 'queued').exists?
          self.class.perform_in(1.minute, campaign.id)
        elsif (next_at = campaign.recipients.awaiting_retry.minimum(:next_retry_at))
          campaign.update_columns(status: 'retry_waiting', scheduled_at: next_at, updated_at: Time.current)
          campaign.recompute_counts!
        else
          campaign.update_columns(status: 'completed', completed_at: Time.current, updated_at: Time.current)
          campaign.recompute_counts!
        end
        return
      end

      ids = batch.map(&:id)
      WhatsappCampaignRecipient.where(id: ids).update_all(status: 'queued', queued_at: now, next_retry_at: nil, updated_at: now)
      ids.each { |rid| Whatsapp::SendCampaignMessageJob.perform_async(rid) }

      self.class.perform_in(1.minute, campaign.id)
    rescue => e
      Rails.logger.error("[Whatsapp::CampaignDispatchJob] campaign=#{campaign_id} #{e.class}: #{e.message}")
    end

    private

    def hold_for_quiet_hours(campaign, now)
      return false unless Whatsapp::SendPolicy.in_quiet_hours?(campaign, now)
      return false unless campaign.recipients.due_for_send(now).exists?

      resume_at = Whatsapp::SendPolicy.next_window_start(campaign, now)
      WhatsappCampaign.where(id: campaign.id, status: 'sending')
                      .update_all(status: 'scheduled', scheduled_at: resume_at, pause_reason: 'quiet_hours',
                                  updated_at: Time.current)
      true
    end
  end
end

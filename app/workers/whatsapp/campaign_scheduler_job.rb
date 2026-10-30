module Whatsapp
  class CampaignSchedulerJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1

    def perform
      # Only promote as many campaigns as there are free concurrency slots.
      # Oldest-due first; the rest stay `scheduled` and get picked up on a later
      # tick once a sending campaign completes and frees a slot.
      slots = WhatsappCampaign.sending_slots_available
      return if slots <= 0

      now = Time.current
      WhatsappCampaign.due.order(:scheduled_at).limit(slots).each do |c|
        next if Whatsapp::CampaignGuardrails.enforce_quality!(c)

        if Whatsapp::SendPolicy.in_quiet_hours?(c, now)
          c.update_columns(scheduled_at: Whatsapp::SendPolicy.next_window_start(c, now), pause_reason: 'quiet_hours',
                           updated_at: now)
          next
        end

        columns = { status: 'sending', started_at: c.started_at || now, updated_at: now }
        columns[:pause_reason] = nil if c.pause_reason == 'quiet_hours'
        c.update_columns(columns)
        Whatsapp::CampaignDispatchJob.perform_async(c.id)
      rescue StandardError => e
        Rails.logger.error("[Whatsapp::CampaignSchedulerJob] campaign=#{c.id} #{e.class}: #{e.message}")
      end
    rescue => e
      Rails.logger.error("[Whatsapp::CampaignSchedulerJob] #{e.message}")
    end
  end
end

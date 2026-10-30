module Whatsapp
  # Reconciles denormalized campaign counters against recipient statuses (the
  # authoritative bucket), catching any webhook the increment path missed.
  class CampaignStatsReconcileJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1

    def perform
      WhatsappCampaign.where(status: %w[sending paused retry_waiting completed])
                      .where('updated_at > ?', 3.days.ago)
                      .find_each { |c| c.recompute_counts! rescue nil }
    rescue => e
      Rails.logger.error("[Whatsapp::CampaignStatsReconcileJob] #{e.message}")
    end
  end
end

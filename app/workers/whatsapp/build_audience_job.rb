module Whatsapp
  # Snapshots a campaign's audience source into whatsapp_campaign_recipients:
  # normalize phone, dedup within the audience, suppress opted-out numbers. Then
  # either schedules the campaign or kicks off immediate dispatch.
  class BuildAudienceJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1
    BATCH = 1000

    def perform(campaign_id)
      campaign = WhatsappCampaign.find_by(id: campaign_id)
      return unless campaign
      campaign.update_columns(status: 'building', updated_at: Time.current)

      opt_outs = WhatsappOptOut.opted_out_set(campaign.shop_id)
      seen = {}
      rows = []
      now = Time.current

      AudienceBuilder.each_recipient(campaign) do |r|
        phone = r[:phone]
        next if phone.blank?
        next if seen[phone]
        seen[phone] = true

        suppressed = opt_outs.include?(phone)
        rows << {
          whatsapp_campaign_id: campaign.id, shop_id: campaign.shop_id, phone: phone,
          name: r[:name], email: r[:email], source_ref: r[:source_ref], fields: r[:fields],
          status: suppressed ? 'suppressed' : 'pending',
          suppression_reason: suppressed ? 'opted_out' : nil,
          created_at: now, updated_at: now
        }
        flush(rows) if rows.size >= BATCH
      end
      flush(rows)

      campaign.recompute_counts!
      campaign.estimate_cost!

      if campaign.scheduled_at.present? && campaign.scheduled_at > Time.current
        campaign.update_columns(status: 'scheduled', updated_at: Time.current)
      elsif WhatsappCampaign.sending_slots_available.positive?
        campaign.update_columns(status: 'sending', started_at: Time.current, updated_at: Time.current)
        Whatsapp::CampaignDispatchJob.perform_async(campaign.id)
      else
        # At the concurrency cap — park as due-now `scheduled` so the scheduler
        # promotes it the moment a slot frees, instead of sending immediately.
        campaign.update_columns(status: 'scheduled', scheduled_at: Time.current, updated_at: Time.current)
      end

      SlackNotifyJob.perform_async(
        ":mega: Campaign audience built (#{Rails.env}) — #{campaign.shop.shopify_domain} \"#{campaign.name}\": " \
        "#{campaign.audience_count} recipients, #{campaign.suppressed_count} suppressed, status=#{campaign.reload.status}"
      ) rescue nil
    rescue => e
      Rails.logger.error("[Whatsapp::BuildAudienceJob] campaign=#{campaign_id} #{e.class}: #{e.message}")
      WhatsappCampaign.where(id: campaign_id).update_all(
        status: 'failed', last_error: "#{e.class}: #{e.message}".truncate(1000), updated_at: Time.current
      )
    end

    private

    def flush(rows)
      return if rows.empty?
      WhatsappCampaignRecipient.insert_all(rows, unique_by: %i[whatsapp_campaign_id phone])
      rows.clear
    end
  end
end

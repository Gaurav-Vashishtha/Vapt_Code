module Whatsapp
  # Not on any schedule — sync is merchant-initiated per shop via the
  # Contacts page. This is a console/ops utility for backfilling every shop
  # that uses the contact book or campaigns.
  class SyncAllContactsJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1

    def perform
      shop_ids = WhatsappContact.distinct.pluck(:shop_id) | WhatsappCampaign.distinct.pluck(:shop_id)
      shop_ids.each { |sid| SyncContactsJob.perform_async(sid) }
    rescue => e
      Rails.logger.error("[Whatsapp::SyncAllContactsJob] #{e.message}")
    end
  end
end

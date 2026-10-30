# frozen_string_literal: true

module Whatsapp
  # Cron (every 30 min): refreshes Meta's review status of every default-number template
  # translation that has a version on MSG91 (see Whatsapp::TemplateTranslationSync).
  class TemplateTranslationStatusSyncJob < ApplicationJob
    sidekiq_options queue: "default", retry: false

    def perform
      Whatsapp::TemplateTranslationSync.new.sync_statuses!
    rescue Msg91::WhatsappTemplateClient::Error => e
      Rails.logger.error("[TemplateTranslationStatusSyncJob] #{e.message} #{e.response.inspect.first(500)}")
    end
  end
end

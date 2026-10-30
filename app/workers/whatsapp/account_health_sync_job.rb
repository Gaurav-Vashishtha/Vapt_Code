# frozen_string_literal: true

module Whatsapp
  # Meta's phone_number_quality_update webhook carries no quality value, so the
  # rating is pulled from the phone-number API instead.
  class AccountHealthSyncJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    BUSY_STATUSES = %w[building scheduled sending retry_waiting].freeze
    STALE_AFTER = 24.hours

    def perform(account_id = nil)
      if account_id.present?
        account = WhatsappAccount.find_by(id: account_id)
        sync(account) if account
        return
      end

      ids = (accounts_with_busy_campaigns + stale_active_accounts).uniq
      WhatsappAccount.where(id: ids).find_each { |account| sync(account) }
    end

    private

    def accounts_with_busy_campaigns
      WhatsappCampaign.where(status: BUSY_STATUSES).where.not(whatsapp_account_id: nil)
                      .distinct.pluck(:whatsapp_account_id)
    end

    def stale_active_accounts
      WhatsappAccount.active.shop_owned.where.not(phone_number_id: [nil, ''])
                     .where('quality_updated_at IS NULL OR quality_updated_at < ?', STALE_AFTER.ago)
                     .pluck(:id)
    end

    def sync(account)
      return if account.phone_number_id.blank?

      begin
        Meta::PhoneNumberService.call(account: account, operation: :status)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::AccountHealthSyncJob] status account=#{account.id} #{e.class}: #{e.message}")
      end
      ::Whatsapp::CampaignGuardrails.check_account!(account.reload)
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::AccountHealthSyncJob] account=#{account&.id} #{e.class}: #{e.message}")
    end
  end
end

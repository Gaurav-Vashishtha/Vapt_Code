module Churn
  # Sends win-back outreach to an at-risk or just-churned shop. Disabled by
  # default (records the intent as 'skipped') so no merchant is contacted until
  # the team approves copy and flips CHURN_WINBACK_ENABLED=true.
  class WinBackJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    def perform(shop_id, trigger)
      outreach = WinBackOutreach.where(shop_id: shop_id, trigger: trigger).order(:created_at).last
      outreach ||= WinBackOutreach.create!(shop_id: shop_id, trigger: trigger, status: 'pending')

      shop = Shop.find_by(id: shop_id)
      domain = shop&.shopify_domain || UninstalledShop.find_by(shop_id: shop_id)&.shop_domain
      email = shop&.owner_email || UninstalledShop.find_by(shop_id: shop_id)&.email
      outreach.update_columns(shopify_domain: domain)

      unless ENV.fetch("CHURN_WINBACK_ENABLED", nil) == 'true'
        outreach.update_columns(status: 'skipped', metadata: { reason: 'winback disabled (dry-run)' }, updated_at: Time.current)
        return
      end

      if email.blank?
        outreach.update_columns(status: 'failed', metadata: { reason: 'no email' }, updated_at: Time.current)
        return
      end

      ChurnMailer.win_back(email, trigger: trigger, domain: domain, owner: shop&.owner_name).deliver_later
      outreach.update_columns(status: 'sent', channel: 'email', sent_at: Time.current, updated_at: Time.current)
    rescue => e
      Rails.logger.error("[Churn::WinBackJob] shop=#{shop_id} failed: #{e.class}: #{e.message}")
    end
  end
end

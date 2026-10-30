# frozen_string_literal: true

module Rto
  # One-time bootstrap to create ShopDomain/ShopInstallation records
  # for all existing Shop rows (survives uninstall/reinstall).
  #
  # Usage:
  #   Rto::BootstrapShopDomainsFromShopsJob.perform_async(true)  # also enqueue backfill per shop
  #   Rto::BootstrapShopDomainsFromShopsJob.perform_async(false) # only create domains/installations
  class BootstrapShopDomainsFromShopsJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    BATCH = 500

    def perform(enqueue_backfill = false, after_shop_id = 0)
      ids = Shop.where("shops.id > ?", after_shop_id).order(:id).limit(BATCH).pluck(:id)
      return if ids.empty?

      ids.each do |sid|
        shop = Shop.find_by(id: sid)
        next if shop.blank? || shop.shopify_domain.blank?

        sd = ShopDomain.find_or_create_by_domain!(shop.shopify_domain)
        sd.update_column(:last_seen_at, Time.current) rescue nil

        inst = ShopInstallation.active.find_by(shop_domain: sd)
        if inst.present?
          inst.update!(
            shop: shop,
            access_token: shop.shopify_token,
            installed_at: inst.installed_at || Time.current,
            status: "installed"
          )
        else
          ShopInstallation.create!(
            shop_domain: sd,
            shop: shop,
            status: "installed",
            access_token: shop.shopify_token,
            installed_at: Time.current
          )
        end

        Rto::BackfillShopDomainJob.perform_async(sd.id) if enqueue_backfill
      rescue => e
        SlackNotifyJob.perform_async(
          ":warning: (#{Rails.env})\nRTO bootstrap failed\nShopID: #{sid}\nDomain: #{shop&.shopify_domain}\n#{e.class}: #{e.message}"
        )
      end

      self.class.perform_async(enqueue_backfill, ids.last) if ids.size == BATCH
    end
  end
end


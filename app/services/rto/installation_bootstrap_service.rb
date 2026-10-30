# frozen_string_literal: true

module Rto
  class InstallationBootstrapService < ApplicationService
    def initialize(shop:)
      @shop = shop
    end

    def call
      return if @shop.blank? || @shop.shopify_domain.blank?

      sd = ShopDomain.find_or_create_by_domain!(@shop.shopify_domain)
      sd.update_column(:last_seen_at, Time.current) rescue nil

      inst = ShopInstallation.active.find_by(shop_domain: sd)
      if inst.present?
        inst.update!(
          shop: @shop,
          access_token: @shop.shopify_token,
          installed_at: inst.installed_at || Time.current,
          status: "installed"
        )
      else
        ShopInstallation.create!(
          shop_domain: sd,
          shop: @shop,
          status: "installed",
          access_token: @shop.shopify_token,
          installed_at: Time.current
        )
      end

      # Kick off backfill asynchronously (incremental; resumes via backfill_state).
      Rto::BackfillShopDomainJob.perform_async(sd.id)
      true
    end
  end
end


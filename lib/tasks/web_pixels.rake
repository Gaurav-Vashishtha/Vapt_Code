# frozen_string_literal: true

# Backfill / management for the Shopify Web Pixel created by WebPixels::SyncShopPixelService.
#
# The Setting model enqueues SyncShopPixelJob via `after_commit :on: :create`, so
# only NEW shops get a pixel automatically. Existing shops (already onboarded
# before the web pixel feature shipped) need a one-time backfill — that's this task.
# SyncShopPixelService is idempotent (queries `webPixel { id }` first, then
# webPixelUpdate vs webPixelCreate), so re-running this task is safe.
namespace :web_pixels do
  desc "Enqueue SyncShopPixelJob for every installed shop with a Setting (idempotent)"
  task backfill: :environment do
    scope = Shop.joins(:setting).where.not(shopify_token: nil)
    total = scope.count
    enqueued = 0
    skipped = 0

    scope.find_each(batch_size: 200) do |shop|
      ShopifyJobs::SyncShopPixelJob.perform_async(shop.id)
      enqueued += 1
    rescue StandardError => e
      skipped += 1
      Rails.logger.warn("[WebPixels:backfill] enqueue failed shop=#{shop.shopify_domain} #{e.class}: #{e.message}")
    end

    puts "[WebPixels:backfill] enqueued=#{enqueued} skipped=#{skipped} total=#{total}"
  end

  desc "Sync the web pixel for a single shop by domain (DOMAIN=foo.myshopify.com)"
  task sync: :environment do
    domain = ENV["DOMAIN"].to_s.strip
    abort "DOMAIN env var required (e.g. DOMAIN=foo.myshopify.com)" if domain.blank?

    shop = Shop.find_by(shopify_domain: domain)
    abort "Shop not found: #{domain}" unless shop

    ShopifyJobs::SyncShopPixelJob.perform_async(shop.id)
    puts "[WebPixels:sync] enqueued for #{domain} (shop_id=#{shop.id})"
  end
end

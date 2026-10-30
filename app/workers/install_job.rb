class InstallJob < ActiveJob::Base

  def perform(shop_id)
    shop = Shop.find(shop_id)
    is_bl = BlackListShop.find_by(domain: shop.shopify_domain)
    if is_bl
      shop.setting.update({ locked: true, sms: false, ivr: false, status: false})
    end
    wallet = Wallet.find_or_initialize_by(shopify_domain:shop.shopify_domain)
    wallet.save
    # Fetch and store customer count at install time
    count = ShopifyServices::CustomerCountFetchService.call(shop)
    shop.update_column(:customer_count, count) if count.is_a?(Integer)
    #ShopifyJobs::InitialCustomerPullJob.perform_async(shop.id)

    # Create the cart transform (partial payment) here in the background so it's
    # ready well before checkout and doesn't depend on the merchant re-opening
    # the app. Idempotent (no-op once cart_transform_id is set), self-establishes
    # a Shopify session via GraphqlService, and gets Sidekiq's automatic retries
    # if the first attempt fails. The inline call in HomeController#index stays as
    # a per-load fallback. Rescued so it never fails the rest of install.
    begin
      ShopifyServices::CartTransformService.call(shop) if shop.setting.present?
    rescue => e
      Rails.logger.warn("[InstallJob] cart transform setup failed shop=#{shop.shopify_domain}: #{e.class}: #{e.message}")
    end
    shopify_shop = ShopifyAPI::Shop.current
    client = Slack::Notifier.new  'https://hooks.slack.com/services/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'
    client.ping(
      text: ":sunglasses: App *Installed* (#{Rails.env}) \n*Store*: #{shop.primary_domain.presence || shop.shopify_domain}\n*country code* #{shop.country_code}\n*Customer count* #{shop.customer_count}\n*Shopify plan* #{shopify_shop.plan_name}  \n*Shop created date* #{shopify_shop.created_at} \n*Password enabled* #{shopify_shop.password_enabled}",
      channel: ENV['SLACK_INSTALLS_CHANNEL']
    )
    CodKingStat.increment_stat('install_count')
    # owner_phone can still be blank if Shopify has no store phone — backfill
    # from the API response as a fallback for the deferred retry path.
    if shop.owner_phone.blank? && shopify_shop.phone.present?
      shop.update_columns(owner_phone: shopify_shop.phone, updated_at: Time.current)
    end

    begin
      ShopifyJobs::AfterAuthenticatePixelSyncJob.perform_async(shop.id)
    rescue => e
      Rails.logger.warn("[WebPixels] Failed to enqueue AfterAuthenticatePixelSyncJob for shop_id=#{shop.id}: #{e.class}: #{e.message}")
    end
  end
end

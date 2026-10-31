class UninstallJob < ActiveJob::Base
  def perform(shop_domain:, webhook:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    if shop.nil?
      logger.error("#{self.class} failed: cannot find shop with domain '#{shop_domain}'")
      return
    end

    client = SlackNotifier::INSTALLS_CLIENT
    uninstalled_shop = UninstalledShop.new(
    shop_id:shop.id,
    shop_domain: shop.shopify_domain,
    email: shop.owner_email, 
    phone: shop.owner_phone,
    owner_name: shop.owner_name,
    country: shop.country_code,
    order_count: shop.order_confirmations.count,
    shopify_created_on: shop.shop_created_date,
    sms: shop.setting.sms,
    confirmation_sms_enabled: shop.setting.confirmation_sms_enabled,
    cod_fee_enabled: shop.setting.cod_fee_enabled || shop.setting.enable_shipping_cod_fees,
    enable_pre_order_otp: shop.setting.enable_pre_order_otp,
    prepaid_enabled: shop.setting.prepaid_enabled,

    )
    
    if !uninstalled_shop.save
      client.ping(
        text: ":rage: App *Uninstalled* (#{Rails.env}) \n*Store*: #{shop.primary_domain.presence || shop.shopify_domain}\nUnable to save Shop in uninstalled table",
        channel: ENV.fetch("SLACK_INSTALLS_CHANNEL", nil)
      )  
    end
    # send mail
    WelcomeMailer.uninstall_feedback(shop.owner_email, {
      name: shop.shop_owner,
      shopify_domain: shop.shopify_domain,
      owner_name: shop.owner_name}).deliver_later
    # shop.sidekiq_jobs.destroy_all # dependent destroy not working
    # Add new table - leads to call
    shop.update(shopify_domain: shop.shopify_domain+'_1')
    # Defensive cleanup: ensure no settings rows remain (FK blocks shop delete).
    Setting.where(shop_id: shop.id).delete_all
    shop.destroy
    # ShopifyJobs::ShopDestroyJob.set(wait:24.hours).perform_later( shop.id)
    
    client.ping(
      text: ":rage: App *Uninstalled* (#{Rails.env}) \n*Store*: #{shop.primary_domain.presence || shop.shopify_domain}\n*Plan*: #{shop.plan.name}\n*Installed Date*: #{shop.created_at}",
      channel: ENV.fetch("SLACK_INSTALLS_CHANNEL", nil)
    )
    CodKingStat.increment_stat('uninstall_count')
  end
end
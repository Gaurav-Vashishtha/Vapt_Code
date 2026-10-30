class UninstallNewJob < ApplicationJob

def perform(shop_domain, params)
    shop = Shop.find_by(shopify_domain: shop_domain)

    if shop.nil?
      logger.error("#{self.class} failed: cannot find shop with domain '#{shop_domain}'")
      return
    end

    client = Slack::Notifier.new  'https://hooks.slack.com/services/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'

    # Snapshot the feature state BEFORE settings are deleted / shop destroyed.
    # (This was missing here — only the legacy UninstallJob captured it — so every
    # uninstalled_shops row showed features as false regardless of what was on.)
    setting = shop.setting
    # Test orders never count as processed orders (churn dashboard "orders processed").
    real_orders = shop.order_confirmations.where('status IS DISTINCT FROM ?', 'Test-Order')
    first_order_at = real_orders.minimum(:created_at)
    last_order_at = real_orders.maximum(:created_at)
    orders_last_30d = real_orders.where('created_at >= ?', 30.days.ago).count
    tenure_days = ((Time.current - shop.created_at) / 1.day).floor
    survey_token = SecureRandom.hex(16)
    uninstalled_shop = UninstalledShop.new(
    shop_id:shop.id,
    shop_domain: shop.shopify_domain,
    email: shop.owner_email,
    phone: shop.owner_phone,
    shopify_created_date: shop.created_at,           # install date (in our system)
    shopify_created_on: shop.shop_created_date,      # Shopify store creation date (shop age)
    owner_name: shop.owner_name,
    country: shop.country_code,
    order_count: real_orders.count,
    customer_count: shop.customer_count,
    first_order_at: first_order_at,
    last_order_at: last_order_at,
    last_active_at: last_order_at,
    orders_last_30d: orders_last_30d,
    tenure_days: tenure_days,
    plan_name_at_uninstall: shop.plan&.name,
    churn_risk_at_uninstall: shop.try(:churn_risk_score),
    churn_risk_band_at_uninstall: shop.try(:churn_risk_band),
    survey_token: survey_token,
    sms: setting&.sms || false,
    confirmation_sms_enabled: setting&.confirmation_sms_enabled || false,
    cod_fee_enabled: (setting&.cod_fee_enabled || setting&.enable_shipping_cod_fees || false),
    enable_pre_order_otp: setting&.enable_pre_order_otp || false,
    abandoned_cart_enabled: setting&.abandoned_cart_enabled || false,
    prepaid_enabled: setting&.prepaid_enabled || false,
    partial_payment_enabled: setting&.partial_payment_enabled || false,
    ac_whatsapp: setting&.ac_whatsapp || false,
    cod_show_hide_enabled: (setting&.is_cod_show_hide_enabled? || false),
    bsp_integrated: shop.whatsapp_account.present?
    )
    if uninstalled_shop.has_attribute?(:feature_snapshot)
      uninstalled_shop.feature_snapshot = Churn::FeatureSet.snapshot_for(shop)
    end

    CodKingStat.increment_stat("#{shop.plan&.name}-deactivations")

    
    if !uninstalled_shop.save
      client.ping(
        text: ":rage: App *Uninstalled* (#{Rails.env}) \n*Store*: #{shop.primary_domain.presence || shop.shopify_domain}\nUnable to save Shop in uninstalled table",
        channel: ENV['SLACK_INSTALLS_CHANNEL']
      )  
    end
    # send mail
    survey_url = (Rails.application.routes.url_helpers.uninstall_survey_url(token: survey_token, host: ENV["APP_HOST"], protocol: "https") rescue nil)
    survey_url = nil unless uninstalled_shop.persisted? # the link only works if the snapshot saved
    WelcomeMailer.uninstall_feedback(shop.owner_email, {
      name: shop.shop_owner,
      shopify_domain: shop.shopify_domain,
      survey_url: survey_url,
      owner_name: shop.owner_name}).deliver_later

    # The uninstall email above is the only message a churned merchant gets; it
    # carries the exit survey. (No separate win-back email on uninstall.)
    MerchantWhatsapp::Events.fire(:uninstalled, uninstalled_shop_id: uninstalled_shop.id) if uninstalled_shop.persisted?
    # shop.sidekiq_jobs.destroy_all # dependent destroy not working
    # Add new table - leads to call
    #
    # Defensive cleanup: some shops may have multiple Setting rows (historical data).
    # `Shop#has_one :setting` only deletes one record, but the DB FK blocks deleting the shop
    # while any settings remain.
    Setting.where(shop_id: shop.id).delete_all
    shop.destroy
    # ShopifyJobs::ShopDestroyJob.set(wait:24.hours).perform_later( shop.id)
    
    client.ping(
      text: ":rage: App *Uninstalled* (#{Rails.env}) \n*Store*: #{shop.primary_domain.presence || shop.shopify_domain}\n*Plan*: #{shop.plan&.name}\n*Installed Date*: #{shop.created_at}",
      channel: ENV['SLACK_INSTALLS_CHANNEL']
    )
    CodKingStat.increment_stat('uninstall_count')
  end
end
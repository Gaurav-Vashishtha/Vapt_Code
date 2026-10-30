# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage
  # include SettingsCache

  has_one :setting, dependent: :destroy
  has_one :support_lead_tracking, dependent: :destroy
  has_one :shop_charge_override, dependent: :destroy
  has_one :additional_setting, dependent: :destroy
  has_many :integrations, dependent: :destroy
  has_many :headers, dependent: :destroy
  belongs_to :plan, optional: true
  # has_many :sidekiq_jobs,
  #   primary_key: 'shopify_domain',
  #   foreign_key: 'name',
  #   :dependent => :destroy
  has_many :order_confirmations, dependent: :destroy
  has_many :redirects, dependent: :destroy
  # Retained on uninstall (shop_id nulled, row kept) so the onboarding funnel
  # keeps its history. The DB FK is ON DELETE SET NULL; this mirrors it.
  has_many :onboarding_events, dependent: :nullify
  has_many :notification_logs, dependent: :delete_all

  
  has_many :abandon_cart_schedules, dependent: :destroy

  has_many :abandoned_carts, dependent: :destroy
  has_many :pre_order_otps, dependent: :destroy
  has_many :follow_ups, dependent: :destroy
  has_many :branded_whatsapp_templates, dependent: :destroy
  has_many :partial_rule_sets, dependent: :destroy
  has_many :discounts, dependent: :destroy
  has_many :whatsapp_accounts, dependent: :destroy
  has_many :whatsapp_templates, through: :whatsapp_accounts
  has_many :whatsapp_template_bindings, dependent: :destroy
  has_many :whatsapp_message_logs, dependent: :destroy
  has_many :whatsapp_order_attributions, dependent: :delete_all
  has_many :webhook_endpoints, dependent: :destroy
  has_many :inbound_webhook_events, dependent: :delete_all
  after_destroy :cleanup_related_records
  after_update :cleanup_related_records 
  has_many :customer_pull_job_queues, dependent: :delete_all
  has_many :scheduled_emails, dependent: :destroy
  has_many :scheduled_shop_reports, dependent: :destroy
  has_many :scheduled_report_deliveries, dependent: :destroy

  # COD Form module (docs/cod-form/ARCHITECTURE.md B.19). `integrations` above is the existing
  # ::Integration model; the COD Form one is `cod_form_integrations`.
  has_one :cod_form_shop_config, class_name: "CodForm::ShopConfig", dependent: :destroy
  has_one :cod_button_config, class_name: "CodForm::ButtonConfig", dependent: :delete
  has_many :cod_forms, class_name: "CodForm::Form", dependent: :delete_all
  has_many :cod_offers, class_name: "CodForm::Offer", dependent: :delete_all
  has_many :cod_offer_ab_tests, class_name: "CodForm::AbTest", dependent: :delete_all
  has_many :cod_shipping_rates, class_name: "CodForm::ShippingRate", dependent: :delete_all
  has_many :cod_block_entries, class_name: "CodForm::BlockEntry", dependent: :delete_all
  has_many :cod_form_sessions, class_name: "CodForm::Session", dependent: :delete_all
  has_many :cod_form_rejections, class_name: "CodForm::Rejection", dependent: :delete_all
  has_many :tracking_pixels, class_name: "CodForm::TrackingPixel", dependent: :delete_all
  has_many :form_order_usages, class_name: "CodForm::OrderUsage", dependent: :delete_all
  has_many :cod_form_daily_stats, class_name: "CodForm::DailyStat", dependent: :delete_all
  has_many :cod_form_integrations, class_name: "CodForm::Integration", dependent: :delete_all

  # Excludes placeholder rows created for uninstalled-shop follow-ups before
  # follow-ups could attach to uninstalled_shops (shopify_token "uninstalled_<hex>").
  scope :real_installs, -> { where("shops.shopify_token NOT LIKE 'uninstalled\\_%'") }

  # Shops worth spending customer-pull capacity on: a real install that is paying,
  # newly installed, or has had orders recently. Dormant shops are skipped.
  #   CUSTOMER_PULL_NEW_INSTALL_DAYS (default 14), CUSTOMER_PULL_ACTIVE_DAYS (default 30)
  scope :pull_worthy, -> {
    real_installs.where(
      "(shops.charge_id IS NOT NULL AND shops.charge_id <> '') OR shops.created_at >= ? OR shops.last_order_at >= ?",
      ENV.fetch('CUSTOMER_PULL_NEW_INSTALL_DAYS', 14).to_i.days.ago,
      ENV.fetch('CUSTOMER_PULL_ACTIVE_DAYS', 30).to_i.days.ago
    )
  }

  def placeholder_install?
    shopify_token.to_s.start_with?('uninstalled_')
  end

  scope :needs_verification, -> {
    where(
      "(created_at >= ? AND (relationship_manager IS NULL OR relationship_manager = '')) AND 
       (shop_created_date IS NOT NULL AND shop_created_date <= ? AND (relationship_manager IS NULL OR relationship_manager = ''))",
      7.days.ago, 3.months.ago.strftime('%Y-%m-%d')
    )
  }
  
  def needs_setup_verification?
    return false if relationship_manager.present?
    (created_at >= 7.days.ago) || (created_at <= 3.months.ago)
  end
  
  def shop_initials
    return 'NA' if shopify_domain.blank?
    
    domain_parts = shopify_domain.split('.').first.split('-')
    if domain_parts.length >= 2
      "#{domain_parts[0][0]}#{domain_parts[1][0]}".upcase
    else
      shopify_domain[0..1].upcase
    end
  end

  # cache_self by: :shopify_domain
  # cache_at :setting


  after_create :enqueue_customer_pull
  after_create :enqueue_scheduled_report_subscriptions_sync
  after_commit :bootstrap_rto_intelligence_on_install, on: %i[create update]

  def enqueue_customer_pull
    # Only skip if there is already a pending or processing job (cancelled/done/failed allow a new one)
    return if CustomerPullJobQueue.where(shop_id: id).where(status: %w[pending processing]).exists?

    CustomerPullJobQueue.create!(shop: self)
    ShopifyJobs::CustomerPullQueueProcessorJob.perform_async
  end

  def enqueue_scheduled_report_subscriptions_sync
    ScheduledReports::SyncShopSubscriptionsJob.perform_async(id)
  rescue StandardError => e
    Rails.logger.error("[ScheduledReports] failed to enqueue SyncShopSubscriptionsJob shop_id=#{id} #{e.class}: #{e.message}")
    nil
  end

  def bootstrap_rto_intelligence_on_install
    # Run only when we have a (new or refreshed) token; avoids firing on unrelated shop updates.
    return unless saved_change_to_shopify_token? || previous_changes.key?("shopify_token")
    Rto::InstallationBootstrapService.call(shop: self)
  rescue => e
    Rails.logger.warn("[RTO] bootstrap failed shop=#{shopify_domain} #{e.class}: #{e.message}")
    nil
  end


  def abandoned_cart_enabled
    return false if setting.blank?
    setting.abandoned_cart_enabled || setting.ac_whatsapp
  end

  # A binding row existing for the event IS the per-shop BSP switch; there is
  # no separate enabled flag.
  def bsp_abandoned_cart?(event_type_key = 'abandoned_cart')
    whatsapp_template_bindings.exists?(event_type_key: event_type_key)
  end

  # Both AC schedulers switch their Shopify funnel off for these shops: a
  # Shopflo-checkout store has its carts pushed to us, so also polling Shopify
  # would send every cart twice.
  def webhook_cart_ingestion?
    return false unless self.class.webhook_ingestion_allowed?(shopify_domain)

    webhook_endpoints.enabled.exists?
  end

  # Blank env var means no restriction; the endpoint row is then the only gate.
  def self.webhook_ingestion_allowlist
    ENV.fetch('WEBHOOK_INGESTION_ENABLED_SHOPS', '').to_s.split(',').map(&:strip).reject(&:blank?)
  end

  def self.webhook_ingestion_allowed?(domain)
    list = webhook_ingestion_allowlist
    list.empty? || list.include?(domain.to_s)
  end

  # Blocks plan downgrades to tiers without WhatsApp notifications; paused
  # notifications don't count, so a merchant can pause everything and downgrade.
  def whatsapp_notifications_active?
    WhatsappAccount.active.where(shop_id: id).exists? &&
      whatsapp_template_bindings.active.exists?
  end

  # The number transactional sends fall back to when an event isn't routed to a
  # specific number. Exactly one account per shop carries is_default; if none is
  # flagged (legacy/edge), fall back to the first active, then any account. This
  # is what the backward-compatible `whatsapp_account` alias returns, so every
  # existing single-number call site keeps working unchanged.
  def default_whatsapp_account
    whatsapp_accounts.find_by(is_default: true) ||
      whatsapp_accounts.active.order(:id).first ||
      whatsapp_accounts.order(:id).first
  end

  # Backward-compatible singular accessor. Legacy call sites that assumed one
  # number resolve to the default; new per-event routing uses
  # whatsapp_account_for instead.
  def whatsapp_account
    default_whatsapp_account
  end

  # The number a given event/stage should send from: the binding's explicit
  # account when set, otherwise the shop default.
  def whatsapp_account_for(event_type_key, stage_index = 0)
    binding = whatsapp_template_bindings.find_by(event_type_key: event_type_key, stage_index: stage_index)
    binding&.whatsapp_account || default_whatsapp_account
  end

  # Shopify domains listed in the WHATSAPP_BSP_PLAN_EXEMPT_DOMAINS env var
  # (comma-separated) get WhatsApp BSP access without the india_budget/Enterprise
  # plan check — e.g. internal test stores and special partners.
  def self.whatsapp_bsp_allowlist
    ENV.fetch('WHATSAPP_BSP_PLAN_EXEMPT_DOMAINS', '').to_s.split(',').map(&:strip).reject(&:blank?)
  end

  def whatsapp_bsp_plan_exempt?
    shopify_domain.present? && self.class.whatsapp_bsp_allowlist.include?(shopify_domain)
  end
  
  def prepaid_boost_case_study
    return false if setting.blank?
    !(setting.enable_shipping_cod_fees || setting.partial_payment_enabled || setting.cod_fee_enabled || setting.prepaid_enabled)
  end

  def has_enabled_any_feature?
    return false if setting.blank?
  
    setting.sms ||
      setting.enable_pre_order_otp ||
      setting.cod_fee_enabled ||
      setting.enable_shipping_cod_fees ||
      setting.partial_payment_enabled
  end

  def billing_activated?
    charge_id.present?
  end

  def self.find_by_shopify_domain_with_cache(shopify_domain)
    Rails.cache.fetch(shopify_domain_cache_key(shopify_domain)) do
      find_by(shopify_domain: shopify_domain)
    end
  end

  # Method to generate a cache key based on the shopify_domain
  def self.shopify_domain_cache_key(shopify_domain)
    "shop/#{shopify_domain}"
  end

  # Expiration logic can be added if you need to clear the cache
  def self.expire_cache(shopify_domain)
    Rails.cache.delete(shopify_domain_cache_key(shopify_domain))
  end

  def cached_setting
    Rails.cache.fetch(setting_cache_key) do
      retrieve_shop_setting
    end
  end

def setting_cache_key
  "shop/#{id}/settings"  # Unique cache key for the settings based on shop ID
end

def retrieve_shop_setting
  self.setting || {}  # Change from "self.settings" to "self.setting"
end


def cleanup_related_records
  Rails.cache.delete(self.class.shopify_domain_cache_key(self.shopify_domain))
end

  # ShopifyApp's session storage writes shopify_token and nothing else, so after
  # an OAuth install/reinstall the expiry and refresh columns still describe the
  # token this one replaced. OfflineTokenService reads those columns as gospel
  # and would treat the new token as a healthy expiring one, never re-minting
  # it. Clearing them sends the next embedded load through token exchange.
  def self.store(auth_session, *args)
    shop_id = super
    shop = find_by(id: shop_id)
    return shop_id if shop.blank?

    shop.update_columns(
      shopify_token_expires_at: nil,
      shopify_refresh_token: nil,
      shopify_refresh_token_expires_at: nil,
      shopify_token_refreshed_at: nil
    )
    expire_cache(shop.shopify_domain)
    # OAuth is a brand-new grant, so whatever failed before this is no longer
    # evidence about the current token — leaving the guard armed would lock the
    # merchant out of the bootstrap they just re-authorized to reach.
    ShopifyServices::OfflineTokenService.clear_remint_marker(shop)
    shop_id
  end

  def api_version
    ShopifyApp.configuration.api_version
  end

  def init_session
    # Keep the offline token valid (refresh expiring tokens). Never raise here —
    # this runs before every Admin API call, including ~40 background-job sites.
    # A legacy not-yet-migrated shop returns :legacy_unmigrated (no-op) and is
    # upgraded on its next embedded admin load (see ShopContextInitializer /
    # HomeController, which pass the session token to ensure_fresh!).
    begin
      ShopifyServices::OfflineTokenService.ensure_fresh!(self)
    rescue ShopifyServices::OfflineTokenService::NeedsReauth => e
      Rails.logger.warn("[OfflineToken] #{e.message}")
      notify_token_reauth_needed_once(e.message)
    rescue ShopifyServices::OfflineTokenService::Error => e
      Rails.logger.warn("[OfflineToken] ensure_fresh failed shop=#{shopify_domain}: #{e.message}")
    end

    session = ShopifyAPI::Session.new(
      domain: shopify_domain,
      token: shopify_token,
      api_version: api_version
    )
    ShopifyAPI::Base.activate_session(session)
  end

  # Slack alert (throttled to once/shop/day) when a shop's refresh token is dead
  # and it can't self-heal from a background job — the merchant must re-open the
  # app to re-mint a token via token exchange.
  def notify_token_reauth_needed_once(message)
    key = "offline_token_reauth_alert/#{shopify_domain}"
    return if Rails.cache.exist?(key)
    Rails.cache.write(key, true, expires_in: 1.day)
    SlackNotifyJob.perform_async(
      ":warning: (#{Rails.env}) Shopify token needs reauth — #{shopify_domain}: #{message}"
    )
  rescue => e
    Rails.logger.warn("[OfflineToken] reauth Slack notify failed shop=#{shopify_domain}: #{e.message}")
  end

  def get_ver_type
    if setting.sms
      'SMS'
    else
      'IVR'
    end
  end

  def crisp_url
    token = Digest::MD5.hexdigest(shopify_domain)
    begin
      url = "https://go.crisp.chat/chat/embed/?website_id=#{ENV['CRISP_WEBSITE_ID']}&user_email=#{URI.encode_www_form_component(owner_email || '')}&user_nickname=#{URI.encode_www_form_component(shop_owner || '')}&token_id=#{token}"
      uri = URI.parse(url)
      uri.to_s
    rescue URI::InvalidURIError => e
      Rails.logger.error "Error parsing Crisp URL: #{e.message}"
      # Return a simple fallback URL
      "https://go.crisp.chat/chat/embed/?website_id=#{ENV['CRISP_WEBSITE_ID']}&token_id=#{token}"
    end
  end

  def cached_lightweight_settings
    Rails.cache.fetch(lightweight_settings_cache_key, expires_in: 10.minutes) do
      generate_lightweight_settings
    end
  end
  
  # Generate the lightweight settings hash
  def generate_lightweight_settings
    settings = cached_setting || {}
    
    {
      enablePreOrderOtp: settings['enable_pre_order_otp'],
      otpWaitTimeInCodKSettings: settings['otp_wait_time'],
      maxTriesInCodKSettings: settings['max_retries'],
      countryCodeList: settings['country_code_list'],
      wrongOtpText: settings['pre_invalid_otp_msg'],
      verifyBtnText: settings['pre_verify_button_label'],
      heading: settings['pre_heading'],
      subHeading: settings['pre_sub_heading'],
      sendBtnText: settings['pre_send_button_label'],
      skipBtnText: settings['pre_skip_btn_text'],
      redirectText: settings['pre_redirect_text'],
      showSkipBtn: settings['pre_show_skip_btn'],
      prePrimaryButtonColor: settings['pre_primary_button_color'],
      preSecondaryButtonColor: settings['pre_secondary_button_color'],
      prePrimaryButtonFontColor: settings['pre_primary_button_font_color'],
      preSecondaryButtonFontColor: settings['pre_secondary_button_font_color'],
      preWhatsappButton: settings['pre_whatsapp_button'],
      preWhatsappButtonText: settings['pre_whatsapp_button_text'],
      hideShippingMethod: settings['hide_shipping_method'],
      hideForUnverifiedOrders: settings['hide_for_unverified_orders'],
      isPrefilledAddressEnabled: settings['is_prefilled_address_enabled'],
      phonePlaceholder: settings['pre_phone_placeholder'],
      invalidPhoneText: settings['pre_invalid_phone'],
      verifyMobileText: settings['pre_verify_mobile'],
      enterCodeText: settings['pre_enter_code'],
      retryInText: settings['pre_retry_in'],
      resendText: settings['pre_resend'],
      failedToVerifyText: settings['pre_failed_to_verify'],
      verifyingText: settings['pre_verifying'],
      tooManyAttemptsText: settings['pre_too_many'],
      isNewDesignEnabled: settings['pre_is_new_design_enabled'],
      preV2Title: settings['pre_v2_title'],
      storeFrontToken: settings['store_front_token'],
      preIsLoginEnabled: settings['pre_is_login_enabled'],
      preV2Theme: settings['pre_v2_theme'],
      preV2ShowOrderSummary: settings['pre_v2_show_order_summary'],
      partialPaymentEnabled: settings['partial_payment_enabled'],
      debug: settings['debug'],
      preEmailMandatory: settings['pre_email_mandatory'],
      preGeoCountries: settings['pre_geo_countries'],
      preShowBranding: settings['pre_show_branding'],
      preV2ShowSendCode: settings['pre_v2_show_send_code'],
      preV2PartialTaxText: settings['pre_v2_partial_tax_text'],
      preV2NoRuleQualifiedMessage: settings['pre_v2_no_rule_qualified_message'],
      variantPickCondition: settings['variant_pick_condition'],
      brandLogoUrl: settings['brand_logo_url'],
      preV2OverwritePopupCondition: settings['pre_v2_overwrite_popup_condition'],
      preV2CartDrawerLayoutSelectors: settings['pre_v2_cart_drawer_layout_selectors'],
      # Promo Banner Settings
      promoBannerShow: settings['promo_banner_show'],
      promoBannerText: settings['promo_banner_text'],
      promoBannerColor: settings['promo_banner_color'],
      promoTextColor: settings['promo_text_color'],
      showOfferAndReward: settings['show_offer_and_reward'],
      shopifyVisitorAppId: ENV["SHOPIFY_VISITOR_APP_ID"].presence,
      conversionTracking:
        settings.key?('conversion_tracking') ? settings['conversion_tracking'] != false : true
    }
  end
  
  # Public method to manually expire lightweight settings cache
  def expire_lightweight_settings_cache
    Rails.cache.delete(lightweight_settings_cache_key)
    Rails.logger.info "Expired lightweight settings cache for shop #{id}"
  end

  # Update your existing cleanup_related_records method to include lightweight settings cache
  def cleanup_related_records
    Rails.cache.delete(self.class.shopify_domain_cache_key(self.shopify_domain))
    Rails.cache.delete(setting_cache_key) if respond_to?(:setting_cache_key)
    Rails.cache.delete(lightweight_settings_cache_key)
  end

  # Sync partial rule sets (cart rules only) to shop metafields for app-embed.liquid.
  # Writes codk.partial_rule_sets (json) and codk.partial_rule_sets_updated_at (timestamp).
  # Updates partial_rule_sets_metafield_synced_at when column exists.
  def sync_partial_rule_sets_metafields
    return unless id.present?

    cart_rules = partial_rule_sets.where(is_enabled: true, is_cart_rule: true).order(position: :asc, id: :asc)
    payload = cart_rules.map(&:as_json)
    ts = Time.current.iso8601

    metafields = []
    begin
      init_session
      shopify_shop = ShopifyAPI::Shop.current
      shop_gid = "gid://shopify/Shop/#{shopify_shop.id}"

      metafields << {
        ownerId: shop_gid,
        namespace: "codk",
        key: "partial_rule_sets_updated_at",
        value: ts,
        type: "single_line_text_field"
      }
      metafields << {
        ownerId: shop_gid,
        namespace: "codk",
        key: "partial_rule_sets",
        value: payload.to_json,
        type: "json"
      }
    rescue => e
      Rails.logger.warn "[Shop] sync_partial_rule_sets_metafields: Could not build metafields: #{e.message}"
      return nil
    end

    result = ShopifyServices::MetafieldsSetService.call(self, metafields)
    Rails.logger.info "[Shop] sync_partial_rule_sets_metafields: MetafieldsSetService returned: #{result.inspect}"

    if respond_to?(:partial_rule_sets_metafield_synced_at=)
      update_column(:partial_rule_sets_metafield_synced_at, Time.current)
    end
    result
  end

  private

  def lightweight_settings_cache_key
    "shop/#{id}/lightweight_settings"
  end

end

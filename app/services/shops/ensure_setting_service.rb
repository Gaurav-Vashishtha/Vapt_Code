# frozen_string_literal: true

module Shops
  class EnsureSettingService < ApplicationService
    def initialize(shop, welcome_email: true)
      @shop = shop
      @welcome_email = welcome_email
    end

    # Creating the setting outside HomeController must also fire the
    # first-install side effects (InstallJob, welcome email, default partial
    # rules) — once a setting exists, HomeController's first-load block never
    # runs, so anything skipped here would be lost forever.
    def call
      return @shop.setting if @shop.setting.present?

      sync_shop_metadata
      I18n.with_locale(locale_for_shop) do
        build_and_save_setting
      end
    end

    private

    def sync_shop_metadata
      return if @shop.primary_locale.present?

      @shop.init_session
      api_shop_data = ShopifyAPI::Shop.current
      @shop.update(
        customer_email: api_shop_data.customer_email,
        owner_email: api_shop_data.email,
        owner_name: api_shop_data.name,
        primary_locale: api_shop_data.primary_locale,
        owner_phone: api_shop_data.phone,
        country_code: api_shop_data.country_code,
        money_format: api_shop_data.money_format,
        currency: api_shop_data.currency,
        country_name: api_shop_data.country_name,
        owner_timezone: api_shop_data.timezone,
        shop_owner: api_shop_data.shop_owner,
        plan: Plan.find_by(name: 'Free'),
        cod_include_tags: GlobalSetting.first.cod_include_tags,
        cod_exclude_tags: GlobalSetting.first.cod_exclude_tags,
        primary_domain: api_shop_data.domain,
        shopify_plan: api_shop_data.plan_name,
        shop_created_date: api_shop_data.created_at
      )
      MerchantWhatsapp::Events.fire(:installed, shop_id: @shop.id)
    rescue StandardError => e
      Rails.logger.warn("[EnsureSetting] metadata sync failed shop=#{@shop.shopify_domain}: #{e.class}: #{e.message}")
    end

    def locale_for_shop
      candidate = @shop.primary_locale.to_s[0..1].presence&.to_sym
      if candidate && I18n.available_locales.excluding(:bg, :ar, :hi, :hr, :sl).include?(candidate)
        candidate
      else
        :en
      end
    end

    def build_and_save_setting
      setting = Setting.find_or_initialize_by(shop_id: @shop.id)
      setting.status = false
      setting.sms = false
      setting.whatsapp = false
      setting.ivr = false
      setting.template = I18n.t('admin.sms_template_default', store: @shop.owner_name)
      setting.retry_template = I18n.t('admin.retry_template_default', store: @shop.owner_name)
      setting.prepaid_template = I18n.t('admin.prepaid_template_default')
      setting.ivr_introduction = I18n.t('admin.ivr_introduction', domain: @shop.shopify_domain)
      setting.ivr_confirm_message = I18n.t('admin.ivr_confirm_message')
      setting.ivr_cancel_message = I18n.t('admin.ivr_cancel_message')
      setting.order_confirmation_template = I18n.t('admin.order_confirm_template_default', store: @shop.owner_name)
      setting.pre_skip_btn_text = 'Skip and place Non-COD Order'
      setting.pre_redirect_text = 'Redirecting to checkout...'
      setting.prepaid_discount = 0.0
      setting.payment_provider = 'RAZORPAY'
      setting.fulfilment_template = I18n.t('admin.fulfilment_template_default', store: @shop.owner_name)
      setting.cod_fee_shipping_keyword = 'cash'
      setting.pre_is_new_design_enabled = true
      setting.pre_v2_show_order_summary = true
      setting.pre_v2_theme = 'minimalWhiteTheme'
      setting.country_code_list = @shop.country_code
      setting.pre_v2_title = @shop.owner_name
      setting.pre_v2_overwrite_popup_condition = 1
      setting.show_cancel_button = true
      setting.partial_payment_flow_version = 2
      setting.partial_expand_flow_enabled = true
      setting.retry = 5
      # Persistent sign-in (verify once, stay signed in) is on for every new install, on every plan.
      setting.persistent_signin = true if setting.new_record?
      setting.shop = @shop

      run_install_side_effects(setting) if setting.save
      setting
    end

    def run_install_side_effects(setting)
      InstallJob.perform_later(@shop.id)
      if @welcome_email
        WelcomeMailer.first_time(
          @shop.owner_email,
          {
            name: @shop.shop_owner.presence || @shop.owner_name,
            shopify_domain: @shop.shopify_domain
          }
        ).deliver_later
      end
      PartialRuleSet.create!(
        shop_id: @shop.id,
        rule_name: 'Full Payment',
        amount: 100.00,
        amount_type: 'percentage',
        is_all: true,
        is_enabled: true,
        is_cart_rule: true
      )
      PartialRuleSet.create!(
        shop_id: @shop.id,
        rule_name: 'Pay 10% - Rest on Delivery',
        amount: 10.00,
        amount_type: 'percentage',
        is_all: true,
        is_enabled: true,
        is_cart_rule: true
      )
      setting.update_conversion_tracking(false)
    end
  end
end

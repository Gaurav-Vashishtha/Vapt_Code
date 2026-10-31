class Setting < ApplicationRecord
  # Column names that feed #lightweight_settings_payload — keep in sync when that method changes.
  LIGHTWEIGHT_SETTINGS_PAYLOAD_COLUMNS = %w[
    enable_pre_order_otp otp_wait_time max_retries country_code_list pre_invalid_otp_msg
    pre_verify_button_label pre_proceed_button_label pre_heading pre_sub_heading pre_send_button_label pre_skip_btn_text
    pre_redirect_text pre_show_skip_btn pre_primary_button_color pre_secondary_button_color
    pre_primary_button_font_color pre_secondary_button_font_color pre_whatsapp_button
    pre_whatsapp_button_text hide_shipping_method hide_for_unverified_orders is_prefilled_address_enabled
    pre_phone_placeholder pre_invalid_phone pre_verify_mobile pre_enter_code pre_retry_in pre_resend
    pre_failed_to_verify pre_verifying pre_too_many pre_is_new_design_enabled pre_v2_title
    store_front_token pre_is_login_enabled pre_v2_theme pre_v2_show_order_summary partial_payment_enabled
    debug pre_email_mandatory pre_geo_countries pre_show_branding pre_v2_show_send_code
    pre_v2_partial_tax_text pre_v2_no_rule_qualified_message variant_pick_condition brand_logo_url
    pre_v2_overwrite_popup_condition pre_v2_cart_drawer_layout_selectors partial_payment_flow_version
    web_ux_version promo_banner_show promo_banner_text promo_banner_color promo_text_color
    private_payment_provider cod_form_enabled pre_v2_show_tax_info pre_v2_show_shipping_info
    include_shipping_in_payment_options
    plus_checkout_otp_extension_enabled revert_discount pixel_id pixel_token pixel_test_event_id
    persistent_signin google_conversion_id google_conversion_token conversion_tracking
    meta_events_enabled
    show_offer_and_reward is_tax_included_with_product partial_expand_flow_enabled
    omit_whatsapp_message_ttl optimized_buy_now codking_loading pre_block_phone
    cod_form_config ui_customization
  ].freeze

  # ui_customization.texts keys the storefront widget understands. Anything else
  # is dropped so a typo/stale key can never bloat the lightweight payload.
  # Keep in sync with notifik-svelte-app/src/utils/uiCustomization.js.
  UI_CUSTOMIZATION_TEXT_KEYS = %w[
    order_summary_title item_singular item_plural saved_so_far qty
    upsell_title upsell_add upsell_added_toast upsell_options upsell_select_option upsell_add_to_cart upsell_adding
    remove_item_confirm remove_item_exit continue_checkout
    no_items_in_cart billing_summary_title subtotal discount
    discount_with_name discount_on_mrp shipping shipping_value tax
    total_amount payment_options_title payment_options_perk no_payment_options
    no_rule_qualified discount_badge_percent discount_badge_amount
    option_save option_save_percent cod_fee_badge shipping_fee_badge tax_hint
    desc_cod desc_cod_with_fee desc_prepaid
    desc_prepaid_with_discount desc_partial desc_pay_now_only
    desc_cod_fee_exception cta_proceed cta_complete_order cta_pay_now
    cta_close cta_preparing legal_terms legal_privacy loader_title
    loader_subtitle cart_loader_fallback cart_loader_title
    cart_loader_subtitle cart_loader_progress cart_loader_proceeding
    cart_loader_error redirect_title redirect_subtitle order_processing
    order_confirmed_redirect close_confirm_banner
    close_confirm_banner_saved close_confirm_continue close_confirm_leave
    close phone_title phone_subtitle phone_continue_with phone_send_otp_via
    otp_resend_via otp_channel_sms login_not_you go_to_phone_screen
    addr_pincode addr_postal_code addr_validating_pincode addr_first_name
    addr_last_name addr_line1 addr_line2 addr_landmark addr_city addr_state
    addr_email addr_email_note addr_type_title addr_type_home addr_type_office addr_type_other addr_add_new addr_none_saved
    addr_add_first addr_edit saved_addresses_title addr_intro
    addr_intro_checkout delivery_card_title
    delivery_summary_title delivery_no_address delivery_add delivery_change
    delivery_edit_hint
    shipping_method_title coupon_sheet_title coupon_placeholder
    coupon_applicable coupon_unlock coupon_apply coupon_none coupon_saved
    coupon_tap_remove coupon_have_code confirm_sheet_title total_amount_inline
    cta_confirm_order rzp_sheet_title rzp_loading rzp_retry rzp_window_open
    rzp_window_note rzp_initializing oc_thank_you oc_placed oc_preparing
    oc_order_number oc_payment_method oc_estimated_delivery oc_updates_note
    oc_track_order oc_view_orders oc_continue_shopping celebration_thanks
    try_again logout_confirm_title logout_confirm_message logout_stay
    exit_confirm_title
    legal_prefix legal_terms_full tax_included_note tax_excluded_note
    badge_pci_dss badge_secure_payments badge_assured_delivery badge_verified_seller
].freeze

  UI_CUSTOMIZATION_BRANDING_KEYS = %w[hide_footer_branding terms_url privacy_url whatsapp_primary brand_color].freeze
  UI_CUSTOMIZATION_BOOLEAN_BRANDING_KEYS = %w[hide_footer_branding whatsapp_primary].freeze
  UI_CUSTOMIZATION_COLOR_BRANDING_KEYS = %w[brand_color].freeze

  # Per-string cap — these are labels and one-line sentences, not descriptions.
  UI_CUSTOMIZATION_MAX_TEXT_LENGTH = 300

  # ui_customization.widget_visibility — which storefront pages the app-embed
  # script is allowed to boot on. Page types mirror Liquid's request.page_type.
  UI_CUSTOMIZATION_VISIBILITY_MODES = %w[all include exclude].freeze
  UI_CUSTOMIZATION_PAGE_TYPES = %w[
    index product collection list-collections cart search page
    blog article policy password gift_card 404
    customers/account customers/login customers/register
    customers/order customers/addresses
  ].freeze
  UI_CUSTOMIZATION_MAX_VISIBILITY_PATHS = 50
  UI_CUSTOMIZATION_MAX_VISIBILITY_PATH_LENGTH = 200

  CHURN_ADOPTION_COLUMNS = %w[
    sms confirmation_sms_enabled confirmation_whatsapp fulfilment_whatsapp ac_whatsapp
    abandoned_cart_enabled cod_fee_enabled prepaid_enabled partial_payment_enabled
    enable_pre_order_otp first_purchase_whatsapp_enabled enable_fulfilment_message
  ].freeze

  belongs_to :shop
  has_many :sms_template_approvals, dependent: :destroy
  before_save :before_save_action
  after_update :audit_churn_adoption_changes
  before_save :mark_lightweight_metafield_sync_after_commit
  # Pushes codk.settings_updated_at + lightweight_settings to Shopify and touches the shop
  # only when attributes that affect the storefront lightweight payload actually changed.
  after_commit :touch_shop_and_sync_metafields, on: :update, if: -> { lightweight_metafield_sync_after_commit == true }
  after_commit :enqueue_shop_pixel_sync, on: %i[create update], if: :web_pixel_settings_changed?
  after_commit :enqueue_partial_discount_automatic_app_job, on: %i[create update]
  attr_accessor :plan, :lightweight_metafield_sync_after_commit
  enum whatsapp_approval_status: { send_request: "send_request", requested: "requested", approved: "approved", rejected: "rejected" }

  # MSG91 SMS flows: use per-shop operator auth key when set, else global env key (same pattern as WhatsApp services).
  def msg91_auth_key
    whatsapp_operator_config.to_s.strip.presence || ENV.fetch("MSG91_AUTHKEY", nil)
  end

  # Returns the prepaid reminders (enabled-only) whose cart range covers the
  # given order amount. A nil cart_min/cart_max means no floor / ceiling.
  # Fan-out: each match schedules its own SendPrepaidSmsJob at its own delay.
  def matching_prepaid_reminders(order_amount)
    amount = order_amount.to_f
    Array(prepaid_reminders).select do |r|
      next false unless r.is_a?(Hash)
      next false unless r['enabled'] != false
      next false if r['delay_minutes'].to_i <= 0
      (r['cart_min'].nil? || amount >= r['cart_min'].to_f) &&
        (r['cart_max'].nil? || amount <  r['cart_max'].to_f)
    end
  end

  def find_prepaid_reminder(reminder_id)
    Array(prepaid_reminders).find { |r| r.is_a?(Hash) && r['id'].to_s == reminder_id.to_s }
  end

  # Merges a reminder's overrides with the shop-level defaults so the send
  # path always sees a fully resolved config. `nil`/blank fields fall through.
  def resolve_prepaid_reminder(reminder)
    reminder = reminder.to_h.with_indifferent_access
    {
      # `id` is not decoration: WhatsappPrepaidBspService builds the send's
      # source_external_id from it, and the partial unique index on
      # whatsapp_message_logs would collapse every reminder for one order into
      # a single send if they all resolved to the same key.
      'id'              => present_value(reminder['id']),
      'delay_minutes'   => reminder['delay_minutes'].to_i,
      'discount'        => present_value(reminder['discount'])      || prepaid_discount,
      'discount_type'   => present_value(reminder['discount_type']) || prepaid_discount_type,
      'add_shipping'    => reminder['add_shipping'] == true,
      'template_key'    => present_value(reminder['template_key'])  || whatsapp_prepaid_template_name,
      'bsp_template_id' => present_value(reminder['bsp_template_id']) || bsp_prepaid_template_id,
      'language'        => present_value(reminder['language'])      || whatsapp_language_code
    }
  end

  private def present_value(v)
    return nil if v.nil?
    return nil if v.respond_to?(:blank?) && v.blank? && !(v.is_a?(Numeric))
    v
  end
  public

  # Admin API DiscountCombinesWithInput for the partial-payment app discount.
  def partial_discount_combines_with
    {
      orderDiscounts: partial_discount_combines_with_order == true,
      productDiscounts: partial_discount_combines_with_product == true,
      shippingDiscounts: partial_discount_combines_with_shipping == true
    }
  end

  # nil when nothing is opted into, so the create payload stays identical to
  # what shops got before this setting existed.
  def partial_discount_combines_with_input
    cw = partial_discount_combines_with
    cw.values.any? ? cw : nil
  end

  def enqueue_partial_discount_automatic_app_job
    return unless shop.present?
    return unless partial_payment_enabled == true
    ShopifyJobs::PartialDiscountAutomaticAppJob.perform_async(shop.id)
  rescue => e
    Rails.logger.warn("[Setting] enqueue_partial_discount_automatic_app_job failed setting_id=#{id} shop_id=#{shop_id} #{e.class}: #{e.message}")
    nil
  end

  def is_cod_show_hide_enabled?
    # String columns - check if non-nil and non-blank
    string_columns = [
      hide_delivery_method,
      selected_countries,
      selected_zips,
      selected_product_ids,
      phone_numbers,
      excluded_zips,
      excluded_shipping_methods,
      show_provinces,
      hide_provinces,
      hide_product_variant_ids,
      show_product_ids,
      email_addresses,
      hide_vendors,
      show_vendors,
    ]
  
    # Integer columns - check if non-nil and non-zero
    integer_columns = [
      min_cart_total,
      max_cart_total,
      hide_discount_total
    ]
  
    # Boolean columns - check if explicitly set to TRUE
    boolean_columns = [
      hide_gift_cards
    ]
  
    # Special string columns that are stored as strings but represent booleans
    boolean_string_columns = [
    ]
    
    # Check string columns
    string_columns.any? { |value| value.present? } ||
    
    # Check integer columns  
    integer_columns.any? { |value| value.present? && value != 0 } ||
    
    # Check boolean columns - check if explicitly true
    boolean_columns.any? { |value| value == true } ||
    
    # Check boolean string columns (should be 'true' or 'false', not blank)
    boolean_string_columns.any? { |value| value.present? && value != 'false' } ||
    
    # Special case: collection_ids - check both selected and excluded
    selected_collection_ids.present? ||
    excluded_collection_ids.present?
  end


  def before_save_action

    monitored_attributes = [
      :payment_method_name,
      :min_cart_total,
      :max_cart_total,
      :hide_delivery_method,
      :selected_countries,
      :selected_zips,
      :selected_product_ids,
      :enable_pre_order_otp,
      :phone_numbers,
      :excluded_zips,
      :cod_fee_enabled,
      :cod_label,
      :excluded_shipping_methods,
      :show_provinces,
      :hide_provinces,
      :debug,
      :cod_fee_shipping_keyword,
      :enable_shipping_cod_fees,
      :hide_product_variant_ids,
      :lock_paid_feature,
      :show_product_ids,
      :pre_is_login_enabled,
      :partial_payment_enabled,
      :hide_for_unverified_orders
    ]

    begin
      if store_front_token_was.blank?
        shop.init_session

        shop_store_front_token = ShopifyAPI::StorefrontAccessToken.new(title:'COD-King-Token')
        if shop_store_front_token.save
          self.store_front_token = shop_store_front_token.access_token
        end
      end
    rescue Exception => e
      puts 'Exception in getting storefront token'
    end


    # if monitored_attributes.any? { |attr| self.changed_attributes.has_key?(attr.to_s) }
    #   payment_id = ShopifyServices::PaymentCustomizationService.call(self.shop , '')
    #   delivery_id = ShopifyServices::DeliveryCustomizationService.call(self.shop)
    # end

    if partial_payment_enabled || pre_is_login_enabled
      self.pre_is_new_design_enabled = true
    end

    notify_whatsapp_approvers = false
    if whatsapp_approval_status_was=="send_request" && (confirmation_whatsapp==true || fulfilment_whatsapp==true || ac_whatsapp==true || first_purchase_whatsapp_enabled==true)
      self.whatsapp_approval_status = "requested"
      notify_whatsapp_approvers = true
    end
    if whatsapp_approval_status_was=="send_request" && whatsapp_approval_status=="requested"
      auto_approval = Whatsapp::AutoApprovalPolicy.new(shop)
      if auto_approval.eligible?
        self.whatsapp_approval_status = "approved"
        self.whatsapp_approval_notes = auto_approval.note
        notify_whatsapp_approvers = false
      end
    end
    if whatsapp_approval_status_was!='approved' && whatsapp_approval_status=='approved'
      job_id = WelcomeMailer.send_whatsapp_approval_confirmation(shop.id).deliver_later
    end
    if whatsapp_approval_status_was!="rejected" && whatsapp_approval_status=="rejected"
      job_id = WelcomeMailer.send_whatsapp_rejection(shop.id).deliver_later
    end
    if notify_whatsapp_approvers
      job_id = WelcomeMailer.send_whatsapp_approval_request(shop.id).deliver_later
    end
  end

  # Payload in the same format as ScriptController#lightweight_settings (snake_case).
  # Used for API response and for codk.lightweight_settings metafield so settingSession format is unchanged.
  # When passing settings_updated_at:, use the same timestamp as codk.settings_updated_at metafield so the frontend can skip the API when they match.
  def lightweight_settings_payload(settings_updated_at: nil)
    updated_at_value = settings_updated_at.presence || shop&.updated_at&.iso8601
    {
      enable_pre_order_otp: enable_pre_order_otp,
      otp_wait_time: otp_wait_time,
      max_retries: max_retries,
      country_code_list: country_code_list,
      pre_invalid_otp_msg: pre_invalid_otp_msg,
      pre_verify_button_label: pre_verify_button_label,
      pre_proceed_button_label: pre_proceed_button_label,
      pre_heading: pre_heading,
      pre_sub_heading: pre_sub_heading,
      pre_send_button_label: pre_send_button_label,
      pre_skip_btn_text: pre_skip_btn_text,
      pre_redirect_text: pre_redirect_text,
      pre_show_skip_btn: pre_show_skip_btn,
      pre_primary_button_color: pre_primary_button_color,
      pre_secondary_button_color: pre_secondary_button_color,
      pre_primary_button_font_color: pre_primary_button_font_color,
      pre_secondary_button_font_color: pre_secondary_button_font_color,
      pre_whatsapp_button: pre_whatsapp_button,
      pre_whatsapp_button_text: pre_whatsapp_button_text,
      hide_shipping_method: hide_shipping_method,
      hide_for_unverified_orders: hide_for_unverified_orders,
      is_prefilled_address_enabled: is_prefilled_address_enabled,
      pre_phone_placeholder: pre_phone_placeholder,
      pre_invalid_phone: pre_invalid_phone,
      pre_verify_mobile: pre_verify_mobile,
      pre_enter_code: pre_enter_code,
      pre_retry_in: pre_retry_in,
      pre_resend: pre_resend,
      pre_failed_to_verify: pre_failed_to_verify,
      pre_verifying: pre_verifying,
      pre_too_many: pre_too_many,
      pre_is_new_design_enabled: pre_is_new_design_enabled,
      pre_v2_title: pre_v2_title,
      store_front_token: store_front_token,
      pre_is_login_enabled: pre_is_login_enabled,
      pre_v2_theme: pre_v2_theme,
      pre_v2_show_order_summary: pre_v2_show_order_summary,
      partial_payment_enabled: partial_payment_enabled,
      debug: debug,
      pre_email_mandatory: pre_email_mandatory,
      pre_geo_countries: pre_geo_countries,
      pre_show_branding: pre_show_branding,
      pre_v2_show_send_code: pre_v2_show_send_code,
      pre_v2_partial_tax_text: pre_v2_partial_tax_text,
      pre_v2_no_rule_qualified_message: pre_v2_no_rule_qualified_message,
      variant_pick_condition: variant_pick_condition,
      brand_logo_url: brand_logo_url,
      pre_v2_overwrite_popup_condition: pre_v2_overwrite_popup_condition,
      pre_v2_cart_drawer_layout_selectors: pre_v2_cart_drawer_layout_selectors,
      partial_payment_flow_version: partial_payment_flow_version,
      partial_expand_flow_enabled: (
        has_attribute?(:partial_expand_flow_enabled) ? (self[:partial_expand_flow_enabled] || false) : false
      ),
      web_ux_version: web_ux_version || 2,
      promo_banner_show: promo_banner_show,
      promo_banner_text: promo_banner_text,
      promo_banner_color: promo_banner_color,
      promo_text_color: promo_text_color,
      private_payment_provider: private_payment_provider,
      cod_form_enabled: cod_form_enabled || false,
      pre_v2_show_tax_info: pre_v2_show_tax_info || false,
      is_tax_included_with_product: is_tax_included_with_product || false,
      pre_v2_show_shipping_info: pre_v2_show_shipping_info || false,
      include_shipping_in_payment_options: (
        has_attribute?(:include_shipping_in_payment_options) ? (self[:include_shipping_in_payment_options] || false) : false
      ),
      plus_checkout_otp_extension_enabled: (
        has_attribute?(:plus_checkout_otp_extension_enabled) ? (self[:plus_checkout_otp_extension_enabled] || false) : false
      ),
      revert_discount: has_attribute?(:revert_discount) ? self[:revert_discount] : false,
      conversion_tracking: (
        has_attribute?(:conversion_tracking) ? (self[:conversion_tracking] == true) : false
      ),
      meta_events_enabled: (
        has_attribute?(:meta_events_enabled) ? (self[:meta_events_enabled] == true) : false
      ),
      pixel_id: pixel_id,
      pixel_test_event_id: pixel_test_event_id,
      persistent_signin: persistent_signin,
      google_conversion_id: google_conversion_id,
      google_conversion_label: google_conversion_label,
      show_offer_and_reward: show_offer_and_reward,
      shopify_visitor_app_id: ENV.fetch("SHOPIFY_VISITOR_APP_ID", nil).presence,
      omit_whatsapp_message_ttl: omit_whatsapp_message_ttl,
      optimized_buy_now: (
        has_attribute?(:optimized_buy_now) ? (self[:optimized_buy_now] || false) : false
      ),
      codking_loading: (
        has_attribute?(:codking_loading) ? (self[:codking_loading] || false) : false
      ),
      pre_block_phone: pre_block_phone,
      cod_form_config: (
        has_attribute?(:cod_form_config) ? (self[:cod_form_config].presence || {}) : {}
      ),
      ui_customization: ui_customization_payload,
      upsell_config: upsell_config_payload,
      free_gift: FreeGifts.storefront_payload(shop),
      active_discounts: active_discounts_payload,
      shop_updated_at: updated_at_value
    }
  end

  def upsell_config_payload
    config = Upsells::Config.sanitize(shop&.additional_setting&.upsell_config)
    config.except("items") if config&.dig("enabled")
  end

  # Merchant-authored checkout copy + white-label branding for the widget,
  # sanitized to the known key set so the storefront payload can't be used as
  # arbitrary storage. Copy, widget_visibility and the footer policy links ship
  # on every plan; hiding the COD King mark needs Pro or above (see
  # UiCustomizationPlanGuard).
  def ui_customization_payload
    return {} unless has_attribute?(:ui_customization)

    raw = self[:ui_customization]
    return {} unless raw.is_a?(Hash)

    payload = {}
    visibility = widget_visibility_payload(raw)
    payload["widget_visibility"] = visibility if visibility

    texts = (raw["texts"] || raw[:texts] || {})
    branding = (raw["branding"] || raw[:branding] || {})

    clean_texts = {}
    if texts.is_a?(Hash)
      texts.each do |key, value|
        key = key.to_s
        next unless UI_CUSTOMIZATION_TEXT_KEYS.include?(key)
        next unless value.is_a?(String)

        value = value.strip
        next if value.blank?

        clean_texts[key] = value[0, UI_CUSTOMIZATION_MAX_TEXT_LENGTH]
      end
    end

    clean_branding = {}
    if branding.is_a?(Hash)
      allowed_keys = UI_CUSTOMIZATION_BRANDING_KEYS
      unless UiCustomizationPlanGuard.branding_allowed_for?(shop)
        allowed_keys -= UiCustomizationPlanGuard::GATED_BRANDING_KEYS
      end

      branding.stringify_keys.slice(*allowed_keys).each do |key, value|
        clean_branding[key.to_s] =
          if UI_CUSTOMIZATION_BOOLEAN_BRANDING_KEYS.include?(key.to_s)
            ActiveModel::Type::Boolean.new.cast(value) == true
          elsif UI_CUSTOMIZATION_COLOR_BRANDING_KEYS.include?(key.to_s)
            sanitize_ui_customization_color(value)
          else
            sanitize_ui_customization_url(value)
          end
      end
      clean_branding.compact!
    end

    payload["texts"] = clean_texts if clean_texts.any?
    payload["branding"] = clean_branding if clean_branding.any?
    payload
  end

  # Page targeting for the storefront script.
  # Returns nil for anything the storefront should read as "run everywhere",
  # including an include-mode selection that matches nothing (a merchant who
  # picked "only on" and selected nothing meant to configure, not to switch off).
  private def widget_visibility_payload(raw)
    visibility = raw["widget_visibility"] || raw[:widget_visibility]
    return nil unless visibility.is_a?(Hash)

    mode = (visibility["mode"] || visibility[:mode]).to_s.strip.downcase
    return nil unless UI_CUSTOMIZATION_VISIBILITY_MODES.include?(mode)
    return nil if mode == "all"

    page_types = Array(visibility["page_types"] || visibility[:page_types])
                 .map { |type| type.to_s.strip.downcase }
                 .select { |type| UI_CUSTOMIZATION_PAGE_TYPES.include?(type) }
                 .uniq

    paths = Array(visibility["paths"] || visibility[:paths])
            .map { |path| sanitize_visibility_path(path) }
            .compact
            .uniq
            .first(UI_CUSTOMIZATION_MAX_VISIBILITY_PATHS)

    return nil if page_types.empty? && paths.empty?

    { "mode" => mode, "page_types" => page_types, "paths" => paths }
  end

  private def sanitize_visibility_path(value)
    path = value.to_s.strip.downcase.split("?").first.to_s.split("#").first.to_s
    return nil if path.blank?
    return nil if path.length > UI_CUSTOMIZATION_MAX_VISIBILITY_PATH_LENGTH

    path = "/#{path}" unless path.start_with?("/")
    path = path.chomp("/") if path.length > 1 && path.end_with?("/")
    path.presence
  end

  private def sanitize_ui_customization_color(value)
    hex = value.to_s.strip.delete_prefix("#").downcase
    return nil unless hex.match?(/\A(\h{3}|\h{6})\z/)

    hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
    "##{hex}"
  end

  # Footer links are rendered as href in the storefront widget: https only.
  private def sanitize_ui_customization_url(value)
    url = value.to_s.strip
    return nil if url.blank?
    return nil unless url.start_with?("https://")
    return nil if url.length > 500

    url
  end

  # Curated list of widget-visible discounts shipped to the storefront widget.
  # Only synced + active + widget_enabled discounts; never exposes sync internals.
  def active_discounts_payload
    return [] unless shop

    shop.discounts.widget_visible.order(display_order: :asc, created_at: :asc).map do |d|
      {
        id: d.id,
        method: d.method,
        code: d.code,
        discount_type: d.discount_type,
        value: d.value&.to_f,
        applies_to: d.applies_to,
        product_gids: d.product_gids_array,
        collection_gids: d.collection_gids_array,
        excluded_product_gids: d.excluded_product_gids_array,
        bxgy_config: d.bxgy_config,
        minimum_requirement_type: d.minimum_requirement_type,
        minimum_requirement_value: d.minimum_requirement_value&.to_f,
        combines_with: {
          order: d.combines_with_order,
          product: d.combines_with_product,
          shipping: d.combines_with_shipping
        },
        starts_at: d.starts_at&.iso8601,
        ends_at: d.ends_at&.iso8601,
        headline: d.headline,
        unlock_text: d.unlock_text
      }
    end
  end

  def mark_lightweight_metafield_sync_after_commit
    return unless persisted?

    names = changed_attribute_names_to_save.map(&:to_s)
    payload_changed = (names & self.class::LIGHTWEIGHT_SETTINGS_PAYLOAD_COLUMNS).any?
    self.lightweight_metafield_sync_after_commit = payload_changed
    self.lightweight_settings_changed_at = Time.current if payload_changed && respond_to?(:lightweight_settings_changed_at=)
  end

  def touch_shop_and_sync_metafields
    return unless shop.present?

    Rails.logger.info "[Setting] after_commit update: setting_id=#{id} shop_id=#{shop.id} shop=#{shop.shopify_domain} touching shop and calling MetafieldsSetService"
    shop.touch

    metafields = []
    begin
      shop.init_session
      shopify_shop = ShopifyAPI::Shop.current
      shop_gid = "gid://shopify/Shop/#{shopify_shop.id}"

      # Same timestamp for both metafields so app-embed can skip API when they match
      settings_updated_at_ts = Time.current.iso8601

      # codk.settings_updated_at for app-embed.liquid to detect changes
      metafields << {
        ownerId: shop_gid,
        namespace: "codk",
        key: "settings_updated_at",
        value: settings_updated_at_ts,
        type: "single_line_text_field"
      }

      # codk.lightweight_settings JSON (includes same shop_updated_at) so app-embed can set settingSession from metafield without blocking
      metafields << {
        ownerId: shop_gid,
        namespace: "codk",
        key: "lightweight_settings",
        value: lightweight_settings_payload(settings_updated_at: settings_updated_at_ts).to_json,
        type: "json"
      }
    rescue => e
      Rails.logger.warn "[Setting] Could not build shop metafields: #{e.message}"
      if e.message.to_s.include?("401") || e.message.to_s.include?("Unauthorized")
        Rails.logger.warn "[Setting] Shop #{shop.shopify_domain} (id=#{shop.id}) has an invalid or expired Shopify access token. Re-install the app or re-authorize from Shopify admin to fix."
      end
    end

    result = metafields.present? ? ShopifyServices::MetafieldsSetService.call(shop, metafields) : nil
    Rails.logger.info "[Setting] MetafieldsSetService returned: #{result.inspect}"
    update_columns(metafield_settings_refreshed_at: Time.current) if respond_to?(:metafield_settings_refreshed_at)
  end

  # Builds and syncs only the lightweight_settings + settings_updated_at metafields to Shopify,
  # then updates metafield_settings_refreshed_at. Callable from ShopifyJobs::RefreshMetafieldLightweightSettingsJob
  # if that job is enqueued elsewhere; this repo does not enqueue it.
  # Does not touch the shop.
  def sync_lightweight_metafields_and_touch_refreshed_at
    return unless shop.present?

    metafields = []
    begin
      shop.init_session
      shopify_shop = ShopifyAPI::Shop.current
      shop_gid = "gid://shopify/Shop/#{shopify_shop.id}"
      settings_updated_at_ts = Time.current.iso8601

      metafields << {
        ownerId: shop_gid,
        namespace: "codk",
        key: "settings_updated_at",
        value: settings_updated_at_ts,
        type: "single_line_text_field"
      }

      metafields << {
        ownerId: shop_gid,
        namespace: "codk",
        key: "lightweight_settings",
        value: lightweight_settings_payload(settings_updated_at: settings_updated_at_ts).to_json,
        type: "json"
      }
    rescue => e
      Rails.logger.warn "[Setting] sync_lightweight_metafields_and_touch_refreshed_at: Could not build metafields: #{e.message}"
      return
    end

    result = ShopifyServices::MetafieldsSetService.call(shop, metafields)
    Rails.logger.info "[Setting] sync_lightweight_metafields_and_touch_refreshed_at: MetafieldsSetService returned: #{result.inspect}"

    update_columns(metafield_settings_refreshed_at: Time.current)
  end

  # Updates conversion_tracking without triggering the lightweight metafield refresh.
  # Uses update_columns to skip before_save / after_commit callbacks, so MetafieldsSetService is not called.
  def update_conversion_tracking(value)
    update_columns(conversion_tracking: value)
  end

  # Gate for the full-funnel Meta pipeline (web pixel browser hit + /events/meta -> CAPI).
  # Off unless the merchant opted in, conversion tracking is on, and both credentials exist.
  def meta_events_active?
    return false unless has_attribute?(:meta_events_enabled)

    self[:meta_events_enabled] == true &&
      self[:conversion_tracking] != false &&
      pixel_id.present? &&
      pixel_token.present?
  end

  # Web pixel settings are pushed to Shopify via webPixelUpdate, so any column that
  # feeds WebPixels::SyncShopPixelService#build_settings has to re-trigger the sync.
  WEB_PIXEL_SYNC_COLUMNS = %w[
    meta_events_enabled pixel_id pixel_token pixel_test_event_id conversion_tracking debug
  ].freeze

  def web_pixel_settings_changed?
    return true if previously_new_record?

    WEB_PIXEL_SYNC_COLUMNS.any? { |column| saved_changes.key?(column) }
  end

  def enqueue_shop_pixel_sync
    Rails.logger.info "[Setting] enqueue_shop_pixel_sync: Enqueuing ShopifyJobs::SyncShopPixelJob for shop #{shop_id}"
    ShopifyJobs::SyncShopPixelJob.perform_async(shop_id)
  rescue StandardError => e
    Rails.logger.error("[WebPixels] enqueue from Setting failed shop_id=#{shop_id} #{e.class}: #{e.message}")
  end

  def audit_churn_adoption_changes
    changes = saved_changes.slice(*CHURN_ADOPTION_COLUMNS)
    return if changes.empty?

    rows = changes.map do |field, (old_val, new_val)|
      { shop_id: shop_id, field: field, old_value: old_val.to_s, new_value: new_val.to_s,
        changed_at: Time.current, changed_by: 'merchant', created_at: Time.current, updated_at: Time.current }
    end
    SettingsChangeAudit.insert_all(rows) if rows.any?
  rescue StandardError => e
    Rails.logger.warn("[Setting] churn adoption audit failed shop_id=#{shop_id}: #{e.message}")
  end

end

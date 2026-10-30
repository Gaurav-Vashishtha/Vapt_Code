require "administrate/base_dashboard"

class SettingDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    shop: Field::BelongsTo,
    id: Field::Number,
    status: Field::Boolean,
    lock_paid_feature: Field::Boolean,
    template: Field::Text,
    sms: Field::Boolean,
    whatsapp: Field::Boolean,
    ivr: Field::Boolean,
    ivr_introduction: Field::String,
    ivr_confirm_message: Field::String,
    ivr_cancel_message: Field::String,
    provider: Field::String,
    provider_api_key: Field::Text,
    provider_sender_id: Field::String,
    prepaid_template: Field::String,
    locked: Field::Boolean,
    otp_fallback_text: Field::Text,
    otp_wait_time: Field::Number,
    max_retries: Field::Number,
    auto_verify: Field::Boolean,
    show_cancel_button: Field::Boolean,
    dlt_template_id: Field::String,
    dlt_bulk_template_id: Field::String,
    cod_fee_enabled: Field::Boolean,
    cod_fees: Field::Number,
    cod_label: Field::String,
    pre_proceed_button_label: Field::String,
    cod_description: Field::String,
    cod_instrutction: Field::String,
    is_checkout_done: Field::Boolean,
    is_shipping_phone_done: Field::Boolean,
    auto_cancel: Field::Number,
    auto_delete: Field::Boolean,
    cancel_flow_id: Field::String,
    cod_variant_id: Field::String,
    test_variant_id: Field::String,
    test_order_url: Field::String,
    retry_template: Field::String,
    retry_flow_id: Field::String,
    retry: Field::Number,
    send_verification_link_only: Field::Boolean, 
    is_percentage: Field::Boolean,
    confirmation_sms_enabled: Field::Boolean,
    confirmation_whatsapp: Field::Boolean,
    confirmation_flow_id: Field::String,
    fulfilment_flow_id: Field::String,
    payment_provider: Field::String,
    payment_provider_api_key: Field::String,
    payment_provider_api_secret: Field::String,
    prepaid_enabled: Field::String,
    prepaid_expiry: Field::Number,
    prepaid_discount: Field::Number,
    prepaid_amount_type: Field::String,
    prepaid_token_amount: Field::Number,
    prepaid_discount_type: Field::String,
    prepaid_heading: Field::String,
    prepaid_sub_heading: Field::String,
    prepaid_banner_color: Field::String,
    prepaid_notif: Field::Boolean,
    thankyou_message: Field::String,
    transaction_fee: Field::Number,
    whatsapp_enabled: Field::Boolean,
    whatsapp_approval_status: Field::String,
    whatsapp_approval_notes: Field::String,
    cancel_template: Field::String,
    cancel_notif_enabled: Field::Boolean,
    include_countries: Field::String,
    custom_script: Field::String,
    payment_customization_id: Field::String,
    payment_method_name: Field::String,
    cart_transform_id: Field::String,
    min_cart_total: Field::Number,
    max_cart_total: Field::Number,
    abandoned_cart_enabled: Field::Boolean,
    abandoned_template: Field::String,
    ac_flow_id:Field::String,
    ac_whatsapp_schedule: Field::String,
    ac_sms_schedule: Field::String,
    ac_whatsapp_discount: Field::String,
    ac_whatsapp_discount_code: Field::String,
    ac_whatsapp_discout_enabled: Field::Boolean,
    shipping_cost: Field::Number,
    hide_delivery_method: Field::String,
    selected_countries: Field::String,
    show_provinces: Field::String,
    hide_provinces: Field::String,
    hide_product_variant_ids: Field::String,
    enable_pre_order_otp: Field::Boolean,
    selected_zips: Field::String,
    excluded_zips: Field::String,
    excluded_shipping_methods: Field::String,
    selected_product_ids: Field::String,
    show_product_ids: Field::String,
    country_code_list: Field::String,
    phone_numbers: Field::String,
    pre_skip_btn_text: Field::String,
    pre_redirect_text: Field::String,
    order_number_prefix: Field::String,
    order_number_suffix: Field::String,
    order_confirmation_template: Field::String,
    enable_fulfilment_message: Field::Boolean,
    fulfilment_whatsapp: Field::Boolean,
    fulfilment_template: Field::String,
    pre_primary_button_color: Field::String,
    pre_secondary_button_color: Field::String,
    pre_primary_button_font_color: Field::String,
    pre_secondary_button_font_color: Field::String,
    pre_whatsapp_button: Field::Boolean,
    pre_whatsapp_button_text: Field::String,
    pre_phone_placeholder: Field::String, 
    pre_invalid_phone: Field::String, 
    pre_verify_mobile: Field::String,
    pre_enter_code: Field::String, 
    pre_retry_in: Field::String, 
    pre_resend: Field::String, 
    pre_failed_to_verify: Field::String, 
    pre_verifying: Field::String, 
    pre_is_new_design_enabled: Field::Boolean, 
    pre_too_many: Field::String,
    pre_show_branding: Field::String,
    skip_draft_order: Field::Boolean,
    ac_whatsapp: Field::Boolean,
    debug: Field::Boolean,
    sender: Field::String,
    cod_fee_shipping_keyword: Field::String,
    enable_shipping_cod_fees: Field::Boolean,
    branded_whatsapp_number: Field::String,
    only_send_confirmation_to_cod: Field::String,
    prepaid_schedule: Field::String,
    post_order_include_product_ids:Field::String,
    otp_ext_heading:Field::String,
    otp_ext_enter_otp_sent_on:Field::String,
    otp_ext_sending_otp:Field::String,
    otp_ext_enter_otp:Field::String,
    otp_ext_resend_otp_in:Field::String,
    otp_ext_resend_otp:Field::String,
    otp_ext_get_code_in_whatsapp:Field::String,
    otp_ext_verify_otp:Field::String,
    otp_ext_successful:Field::String,
    otp_ext_change:Field::String,
    otp_ext_submit:Field::String,
    first_purchase_whatsapp_enabled: Field::Boolean,
    first_purchase_schedule:Field::String,
    first_purchase_discount_code:Field::String,
    first_purchase_discount_off:Field::String,
    whatsapp_operator_config: Field::String,
    hide_shipping_method: Field::Boolean,
    hide_for_unverified_orders: Field::Boolean,
    delivery_customization_id: Field::String,
    is_prefilled_address_enabled: Field::Boolean,
    pre_is_login_enabled: Field::Boolean,
    pre_v2_title: Field::String,
    pre_v2_theme: Field::String,
    pre_v2_show_order_summary: Field::Boolean,
    pre_block_phone: Field::String,
    store_front_token: Field::String,
    partial_payment_enabled: Field::Boolean,
    partial_payment_flow_version: Field::Number,
    partial_expand_flow_enabled: Field::Boolean,
    revert_discount: Field::Boolean,
    partial_dummy_variant_id: Field::String,
    hide_discount_total: Field::Number,
    email_addresses: Field::String,
    hide_gift_cards: Field::Boolean,
    hide_vendors: Field::String,
    show_vendors: Field::String,
    is_tax_included_with_product: Field::Boolean,
    selected_locale: Field::String,
    pre_email_mandatory: Field::Boolean,
    partial_shipping_keyword: Field::String,
    pre_geo_countries: Field::String,
    partial_payment_flow: Field::String,
    pre_v2_show_send_code: Field::Boolean,
    pre_v2_partial_tax_text: Field::String,
    pre_v2_show_tax_info: Field::Boolean,
    pre_v2_show_shipping_info: Field::Boolean,
    include_shipping_in_payment_options: Field::Boolean,
    pixel_id: Field::String,
    pixel_token: Field::String,
    pixel_test_event_id: Field::String,
    conversion_tracking: Field::Boolean,
    meta_events_enabled: Field::Boolean,
    google_conversion_id: Field::String,
    google_conversion_label: Field::String,
    google_conversion_token: Field::String,
    persistent_signin: Field::Boolean,
    partial_transaction_fee: Field::Number,
    post_send_only_whatsapp: Field::Boolean,
    variant_pick_condition: Field::Number,
    whatsapp_language_code: Field::String,
    whatsapp_order_confirmation_template: Field::String,
    whatsapp_first_purchase_template: Field::String,
    whatsapp_abandoned_cart_template: Field::String,
    whatsapp_fulfilment_template: Field::String,
    whatsapp_cod_verification_template: Field::String,
    whatsapp_pre_verify_otp_template: Field::String,
    whatsapp_prepaid_template_name: Field::String,
    prepaid_reminders: Field::Text, # raw JSON editing for admin; merchant UI is the primary editor
    brand_logo_url: Field::String,
    quick_onboarding_visited: Field::Boolean, 
    user_journey: Field::String,
    verification_tag: Field::String,
    pre_v2_overwrite_popup_condition: Field::String,
    pre_v2_cart_drawer_layout_selectors: Field::String,
    last_callback_request_at: Field::String,
    callback_requests_count: Field::Number,
    web_ux_version: Field::Number,
    promo_banner_show: Field::Boolean,
    promo_banner_text: Field::String,
    promo_banner_color: Field::String,
    promo_text_color: Field::String,
    private_payment_provider: Field::Text,
    cod_form_enabled: Field::Boolean,
    ui_customization: Field::Text, # raw JSON editing for admin; merchant UI is the primary editor
    show_offer_and_reward: Field::Boolean,
    optimized_buy_now: Field::Boolean,
    omit_whatsapp_message_ttl: Field::Number,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    shop
    id
    sms
    lock_paid_feature
    cod_fee_enabled
    confirmation_sms_enabled
    enable_pre_order_otp
    abandoned_cart_enabled
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    lock_paid_feature
    locked
    template
    sms
    whatsapp_enabled
    post_send_only_whatsapp
    whatsapp_approval_status
    whatsapp_approval_notes
    retry
    retry_template
    retry_flow_id
    send_verification_link_only
    auto_cancel
    auto_delete
    cancel_flow_id
    cancel_template
    cancel_notif_enabled
    is_checkout_done
    is_shipping_phone_done
    otp_fallback_text
    otp_wait_time
    max_retries
    auto_verify
    show_cancel_button
    test_variant_id
    include_countries
    custom_script
    skip_draft_order
    provider
    provider_api_key
    provider_sender_id
    prepaid_template
    sender
    dlt_template_id
    dlt_bulk_template_id
    cod_fee_enabled
    cod_fees
    is_percentage
    cod_label
    pre_proceed_button_label
    cod_description
    cod_instrutction
    cod_variant_id
    test_order_url
    payment_provider
    payment_provider_api_key
    payment_provider_api_secret
    prepaid_enabled
    prepaid_amount_type
    prepaid_token_amount
    prepaid_discount_type
    prepaid_expiry
    prepaid_discount
    prepaid_heading
    prepaid_sub_heading
    prepaid_banner_color
    prepaid_schedule
    prepaid_notif
    thankyou_message
    transaction_fee
    abandoned_cart_enabled
    abandoned_template
    ac_flow_id
    ac_whatsapp
    ac_whatsapp_schedule
    ac_sms_schedule
    ac_whatsapp_discount
    ac_whatsapp_discount_code
    ac_whatsapp_discout_enabled
    payment_customization_id
    payment_method_name
    cart_transform_id
    min_cart_total
    max_cart_total
    shipping_cost
    hide_delivery_method
    selected_countries
    show_provinces
    hide_provinces
    hide_product_variant_ids
    enable_pre_order_otp
    selected_zips
    excluded_zips
    excluded_shipping_methods
    selected_product_ids
    show_product_ids
    country_code_list
    phone_numbers
    debug
    pre_skip_btn_text
    pre_redirect_text
    pre_primary_button_color
    pre_secondary_button_color
    pre_primary_button_font_color
    pre_secondary_button_font_color
    pre_whatsapp_button
    pre_whatsapp_button_text
    pre_phone_placeholder 
    pre_invalid_phone
    pre_verify_mobile
    pre_enter_code
    pre_retry_in
    pre_resend
    pre_failed_to_verify 
    pre_verifying
    pre_is_new_design_enabled
    pre_too_many
    pre_show_branding
    order_confirmation_template
    order_number_prefix
    order_number_suffix
    enable_fulfilment_message
    fulfilment_whatsapp
    fulfilment_template
    confirmation_sms_enabled
    confirmation_whatsapp
    confirmation_flow_id
    only_send_confirmation_to_cod
    fulfilment_flow_id
    cod_fee_shipping_keyword
    enable_shipping_cod_fees
    branded_whatsapp_number
    post_order_include_product_ids
    otp_ext_heading
    otp_ext_enter_otp_sent_on
    otp_ext_sending_otp
    otp_ext_enter_otp
    otp_ext_resend_otp_in
    otp_ext_resend_otp
    otp_ext_get_code_in_whatsapp
    otp_ext_verify_otp 
    otp_ext_successful 
    otp_ext_change
    otp_ext_submit
    first_purchase_whatsapp_enabled
    first_purchase_schedule
    first_purchase_discount_code
    first_purchase_discount_off
    whatsapp_operator_config
    hide_shipping_method
    hide_for_unverified_orders
    delivery_customization_id
    is_prefilled_address_enabled
    pre_is_login_enabled
    pre_v2_title
    pre_v2_theme
    pre_v2_show_order_summary
    pre_block_phone
    partial_payment_enabled
    partial_payment_flow_version
    partial_expand_flow_enabled
    revert_discount
    partial_dummy_variant_id
    is_tax_included_with_product
    store_front_token
    hide_discount_total
    email_addresses
    hide_gift_cards
    hide_vendors
    show_vendors
    selected_locale
    partial_shipping_keyword
    pre_geo_countries
    partial_payment_flow
    pre_v2_show_send_code
    pre_v2_partial_tax_text
    pre_v2_show_tax_info
    pre_v2_show_shipping_info
    include_shipping_in_payment_options
    pixel_id
    pixel_token
    pixel_test_event_id
    conversion_tracking
    meta_events_enabled
    google_conversion_id
    google_conversion_label
    google_conversion_token
    persistent_signin
    partial_transaction_fee
    variant_pick_condition
    pre_v2_overwrite_popup_condition
    pre_v2_cart_drawer_layout_selectors
    quick_onboarding_visited 
    user_journey
    verification_tag
    whatsapp_language_code
    whatsapp_order_confirmation_template
    whatsapp_first_purchase_template
    whatsapp_abandoned_cart_template
    whatsapp_fulfilment_template
    whatsapp_cod_verification_template
    whatsapp_pre_verify_otp_template
    whatsapp_prepaid_template_name
    prepaid_reminders
    brand_logo_url
    last_callback_request_at
    callback_requests_count
    web_ux_version
    promo_banner_show
    promo_banner_text
    promo_banner_color
    promo_text_color
    private_payment_provider
    cod_form_enabled
    ui_customization
    show_offer_and_reward
    optimized_buy_now
    omit_whatsapp_message_ttl
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    id
    template
    sms
    lock_paid_feature
    locked
    whatsapp_enabled
    post_send_only_whatsapp
    whatsapp_approval_status
    whatsapp_approval_notes
    retry
    retry_template
    retry_flow_id
    send_verification_link_only
    auto_cancel
    auto_delete
    cancel_flow_id
    cancel_template
    cancel_notif_enabled
    is_checkout_done
    is_shipping_phone_done
    otp_fallback_text
    otp_wait_time
    max_retries
    auto_verify
    show_cancel_button
    test_variant_id
    include_countries
    custom_script
    skip_draft_order
    provider
    provider_api_key
    provider_sender_id
    prepaid_template
    sender
    dlt_template_id
    dlt_bulk_template_id
    cod_fee_enabled
    cod_fees
    is_percentage
    cod_label
    pre_proceed_button_label
    cod_description
    cod_instrutction
    cod_variant_id
    test_order_url
    payment_provider
    payment_provider_api_key
    payment_provider_api_secret
    prepaid_enabled
    prepaid_amount_type
    prepaid_token_amount
    prepaid_discount_type
    prepaid_expiry
    prepaid_discount
    prepaid_heading
    prepaid_sub_heading
    prepaid_banner_color
    prepaid_schedule
    prepaid_notif
    thankyou_message
    transaction_fee
    abandoned_cart_enabled
    abandoned_template
    ac_flow_id
    ac_whatsapp
    ac_whatsapp_schedule
    ac_sms_schedule
    ac_whatsapp_discount
    ac_whatsapp_discount_code
    ac_whatsapp_discout_enabled
    payment_customization_id
    payment_method_name
    cart_transform_id
    min_cart_total
    max_cart_total
    shipping_cost
    hide_delivery_method
    selected_countries
    show_provinces
    hide_provinces
    hide_product_variant_ids
    enable_pre_order_otp
    selected_zips
    excluded_zips
    excluded_shipping_methods
    selected_product_ids
    show_product_ids
    country_code_list
    phone_numbers
    debug
    pre_skip_btn_text
    pre_redirect_text
    pre_primary_button_color
    pre_secondary_button_color
    pre_primary_button_font_color
    pre_secondary_button_font_color
    pre_whatsapp_button
    pre_whatsapp_button_text
    pre_phone_placeholder
    pre_invalid_phone
    pre_verify_mobile
    pre_enter_code
    pre_retry_in
    pre_resend
    pre_failed_to_verify
    pre_verifying
    pre_is_new_design_enabled
    pre_too_many
    pre_show_branding
    order_confirmation_template
    order_number_prefix
    order_number_suffix
    enable_fulfilment_message
    fulfilment_whatsapp
    fulfilment_template
    confirmation_sms_enabled
    confirmation_whatsapp
    confirmation_flow_id
    only_send_confirmation_to_cod
    fulfilment_flow_id
    cod_fee_shipping_keyword
    enable_shipping_cod_fees
    branded_whatsapp_number
    post_order_include_product_ids
    otp_ext_heading
    otp_ext_enter_otp_sent_on
    otp_ext_sending_otp
    otp_ext_enter_otp
    otp_ext_resend_otp_in
    otp_ext_resend_otp
    otp_ext_get_code_in_whatsapp
    otp_ext_verify_otp 
    otp_ext_successful 
    otp_ext_change
    otp_ext_submit
    first_purchase_whatsapp_enabled
    first_purchase_schedule
    first_purchase_discount_code
    first_purchase_discount_off
    whatsapp_operator_config
    hide_shipping_method
    hide_for_unverified_orders
    delivery_customization_id
    is_prefilled_address_enabled
    pre_is_login_enabled
    pre_v2_title
    pre_v2_theme
    pre_v2_show_order_summary
    pre_block_phone
    partial_payment_enabled
    partial_payment_flow_version
    partial_expand_flow_enabled
    revert_discount
    partial_dummy_variant_id
    is_tax_included_with_product
    store_front_token
    hide_discount_total
    email_addresses
    hide_gift_cards
    hide_vendors
    show_vendors
    selected_locale
    partial_shipping_keyword
    pre_geo_countries
    partial_payment_flow
    pre_v2_show_send_code
    pre_v2_partial_tax_text
    partial_transaction_fee
    variant_pick_condition
    pre_v2_overwrite_popup_condition
    pre_v2_cart_drawer_layout_selectors
    quick_onboarding_visited 
    user_journey
    verification_tag
    
    whatsapp_language_code
    whatsapp_order_confirmation_template
    whatsapp_first_purchase_template
    whatsapp_abandoned_cart_template
    whatsapp_fulfilment_template
    whatsapp_cod_verification_template
    whatsapp_pre_verify_otp_template
    whatsapp_prepaid_template_name
    prepaid_reminders
    brand_logo_url
    last_callback_request_at
    callback_requests_count
    web_ux_version
    promo_banner_show
    promo_banner_text
    promo_banner_color
    promo_text_color
    pre_v2_show_tax_info
    pre_v2_show_shipping_info
    include_shipping_in_payment_options
    pixel_id
    pixel_token
    pixel_test_event_id
    conversion_tracking
    meta_events_enabled
    google_conversion_id
    google_conversion_label
    google_conversion_token
    persistent_signin
    private_payment_provider
    cod_form_enabled
    ui_customization
    show_offer_and_reward
    optimized_buy_now
    omit_whatsapp_message_ttl
    pre_email_mandatory
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how settings are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(setting)
    "##{setting.id}-#{setting.shop.shopify_domain}(#{setting.sms}, #{setting.whatsapp})"
  end
end

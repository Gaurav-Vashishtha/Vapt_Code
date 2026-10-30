// Central mapping between legacy snake_case settings keys and camelCase keys
const SETTINGS_KEY_MAP = {
  enable_pre_order_otp: "enablePreOrderOtp",
  otp_wait_time: "otpWaitTimeInCodKSettings",
  max_retries: "maxTriesInCodKSettings",
  country_code_list: "countryCodeList",
  pre_invalid_otp_msg: "wrongOtpText",
  pre_block_phone: "preBlockPhone",
  pre_verify_button_label: "verifyBtnText",
  pre_proceed_button_label: "preProceedButtonLabel",
  pre_heading: "heading",
  pre_sub_heading: "subHeading",
  pre_send_button_label: "sendBtnText",
  pre_skip_btn_text: "skipBtnText",
  pre_redirect_text: "redirectText",
  pre_show_skip_btn: "showSkipBtn",
  pre_primary_button_color: "prePrimaryButtonColor",
  pre_secondary_button_color: "preSecondaryButtonColor",
  pre_primary_button_font_color: "prePrimaryButtonFontColor",
  pre_secondary_button_font_color: "preSecondaryButtonFontColor",
  pre_whatsapp_button: "preWhatsappButton",
  pre_whatsapp_button_text: "preWhatsappButtonText",
  hide_shipping_method: "hideShippingMethod",
  hide_for_unverified_orders: "hideForUnverifiedOrders",
  is_prefilled_address_enabled: "isPrefilledAddressEnabled",
  pre_phone_placeholder: "phonePlaceholder",
  pre_invalid_phone: "invalidPhoneText",
  pre_verify_mobile: "verifyMobileText",
  pre_enter_code: "enterCodeText",
  pre_retry_in: "retryInText",
  pre_resend: "resendText",
  pre_failed_to_verify: "failedToVerifyText",
  pre_verifying: "verifyingText",
  pre_too_many: "tooManyAttemptsText",
  pre_is_new_design_enabled: "isNewDesignEnabled",
  pre_v2_title: "preV2Title",
  store_front_token: "storeFrontToken",
  pre_is_login_enabled: "preIsLoginEnabled",
  pre_v2_theme: "preV2Theme",
  pre_v2_show_order_summary: "preV2ShowOrderSummary",
  partial_payment_enabled: "partialPaymentEnabled",
  debug: "debug",
  pre_email_mandatory: "preEmailMandatory",
  pre_geo_countries: "preGeoCountries",
  pre_show_branding: "preShowBranding",
  pre_v2_show_send_code: "preV2ShowSendCode",
  pre_v2_partial_tax_text: "preV2PartialTaxText",
  pre_v2_no_rule_qualified_message: "preV2NoRuleQualifiedMessage",
  variant_pick_condition: "variantPickCondition",
  brand_logo_url: "brandLogoUrl",
  quick_onboarding_visited: "quickOnboardingVisited",
  user_journey: "userJourney",
  pre_v2_overwrite_popup_condition: "preV2OverwritePopupCondition",
  pre_v2_cart_drawer_layout_selectors: "preV2CartDrawerLayoutSelectors",
  partial_payment_flow_version: "partialPaymentFlowVersion",
  partial_expand_flow_enabled: "partialExpandFlowEnabled",
  revert_discount: "revertDiscount",
  routeUrl: "routeUrl",
  shopDomain: "shopDomain",
  // Promo Banner Settings
  promo_banner_show: "promoBannerShow",
  promo_banner_text: "promoBannerText",
  promo_banner_color: "promoBannerColor",
  promo_text_color: "promoTextColor",
  shop_updated_at: "shopUpdatedAt",
  web_ux_version: "webUxVersion",
  pixel_id: "pixelId",
  pixel_test_event_id: "pixelTestEventId",
  conversion_tracking: "conversionTracking",
  persistent_signin: "persistentSignin",
  show_offer_and_reward: "showOfferAndReward",
  pre_v2_show_tax_info: "preV2ShowTaxInfo",
  is_tax_included_with_product: "isTaxIncludedWithProduct",
  pre_v2_show_shipping_info: "preV2ShowShippingInfo",
  include_shipping_in_payment_options: "includeShippingInPaymentOptions",
  shopify_visitor_app_id: "shopifyVisitorAppId",
  active_discounts: "activeDiscounts",
  optimized_buy_now: "optimizedBuyNow",
  codking_loading: "codkingLoading",
  ui_customization: "uiCustomization",
  upsell_config: "upsellConfig",
  free_gift: "freeGift",
};

/**
 * Ensures we always have camelCase settings keys stored/consumed inside the app.
 * Falls back to the original settings object if mapping is not possible.
 *
 * @param {Record<string, any>|null|undefined} rawSettings
 * @returns {Record<string, any>|null}
 */
export function mapSettingsToCamel(rawSettings) {
  if (!rawSettings || typeof rawSettings !== "object") {
    return rawSettings ?? null;
  }

  const normalized = { ...rawSettings };

  Object.entries(SETTINGS_KEY_MAP).forEach(([legacyKey, camelKey]) => {
    if (legacyKey in normalized) {
      normalized[camelKey] = normalized[legacyKey];
      delete normalized[legacyKey];
    } else if (camelKey in rawSettings) {
      normalized[camelKey] = rawSettings[camelKey];
    }
  });

  return normalized;
}

export { SETTINGS_KEY_MAP };

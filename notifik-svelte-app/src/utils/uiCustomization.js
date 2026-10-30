// Pre-order OTP UI customization — merchant-supplied copy + branding for the
// payment screen. Fed by settings.uiCustomization (settings.ui_customization
// jsonb).
//
// Shape:
// {
//   texts:    { payment_options_title: "Scegli il metodo di pagamento", ... },
//   branding: { hide_footer_branding: true, terms_url: "", privacy_url: "", brand_color: "#3173e3" }
// }
//
// Keys must stay in sync with app/javascript/packs/Components/uiCustomizationCatalog.js
// (the merchant-facing editor).

import { getSessionValue } from "../services/sessionService.js";
import { getFilteredCountries } from "../data/countries.js";

export const UI_TEXT_DEFAULTS = {
  // Order summary card + details sheet
  order_summary_title: "Order summary",
  item_singular: "item",
  item_plural: "items",
  saved_so_far: "Yay! You've saved {{amount}} so far",
  qty: "Qty {{count}}",
  remove_item_confirm: "Removing {{name}} will exit checkout.",
  remove_item_exit: "Remove item & exit",
  continue_checkout: "Continue checkout",
  upsell_title: "Items you may like",
  upsell_add: "Add",
  upsell_added_toast: "Product added to cart successfully",
  upsell_options: "+{{count}} options",
  upsell_select_option: "Select {{name}} :",
  upsell_add_to_cart: "Add to cart",
  upsell_adding: "Adding...",
  free_gift_added: "Free gift added",
  free_gift_tag: "Free Gift",
  free_gift_price: "FREE",
  no_items_in_cart: "No items in cart",
  billing_summary_title: "Bill summary",
  subtotal: "Subtotal",
  discount: "Discount",
  discount_with_name: "Discount ({{name}})",
  discount_on_mrp: "Discount on MRP",
  shipping: "Shipping charges",
  shipping_value: "Calculated at next step",
  tax: "Tax",
  total_amount: "Total amount",

  // Payment options
  payment_options_title: "Pay via",
  payment_options_perk: "Enjoy fast delivery on all prepaid orders",
  no_payment_options: "No payment options available at the moment",
  no_rule_qualified:
    "No payment option applies to your cart. You can close this window and try again.",
  discount_badge_percent: "🎉 Flat {{percent}}% Off",
  discount_badge_amount: "🎉 Flat {{amount}} Off",
  option_save: "Save {{amount}}",
  option_save_percent: "Save {{percent}}%",
  cod_fee_badge: "+{{amount}} COD fee",
  free_delivery_badge: "Free Delivery",
  repeat_customer_badge: "Returning customer offer",
  shipping_fee_badge: "+{{amount}} Shipping",
  tax_hint: "+ tax {{amount}}",
  tax_included_note: "Price inclusive of all taxes",
  tax_excluded_note: "Taxes calculated at the next step",

  // Payment option descriptions ({{pay_now}}, {{pay_later}}, {{total}},
  // {{discount}}, {{cod_fee}}, {{shipping}} are replaced with formatted amounts)
  desc_cod: "Pay {{total}} on delivery",
  desc_cod_with_fee: "Pay {{total}} on delivery ({{cod_fee}} COD fee applicable)",
  desc_prepaid: "Pay {{pay_now}} now (prepaid)",
  desc_prepaid_with_discount: "Pay {{pay_now}} now and get {{discount}} off",
  desc_partial: "Pay {{pay_now}} now and {{pay_later}} on delivery",
  desc_pay_now_only: "Pay {{pay_now}} now",
  desc_cod_fee_exception:
    "Pay {{pay_now}} cod fee now, remaining {{pay_later}} on delivery",

  // Primary CTA
  cta_proceed: "Proceed to Payment",
  cta_complete_order: "Complete Order",
  cta_pay_now: "Pay Now",
  cta_close: "Close",
  cta_preparing: "Getting your order ready",

  // Legal footer ({{legal_terms_full}} replaces the abbreviation when the
  // COD King brand mark is hidden and the row has space)
  legal_terms: "T&C",
  legal_terms_full: "Terms & Conditions",
  legal_privacy: "Privacy Policy",

  // Trust badges (phone screen footer)
  badge_pci_dss: "PCI DSS compliant",
  badge_secure_payments: "Secure payments",
  badge_assured_delivery: "Assured delivery",
  badge_verified_seller: "Verified seller",

  // Checkout loader (payment screen, while the cart is fetched)
  loader_title: "Preparing your secure checkout",
  loader_subtitle: "Fetching cart details securely",

  // Initial cart loading screen (full-screen, before the modal has data)
  cart_loader_fallback: "Loading…",
  cart_loader_title: "Loading your checkout…",
  cart_loader_subtitle: "Fetching cart details securely",
  cart_loader_progress: "Getting your cart details...",
  cart_loader_proceeding: "Getting your cart details...",
  cart_loader_error: "We couldn't load your cart. Please refresh the page and try again.",

  // Redirect to Shopify checkout
  redirect_title: "Redirecting to checkout…",
  redirect_subtitle: "OTP Verified! You're all set. Redirecting to checkout...",

  // COD order placement (processing → confirmed → thank you)
  order_processing: "Processing your order…",
  order_confirmed_redirect: "Order is confirmed, redirecting you to orders page…",

  // Exit-intent sheet
  close_confirm_banner: "Products in huge demand might run Out of Stock",
  close_confirm_banner_saved: "You might miss out on savings of {{amount}}",
  close_confirm_continue: "No, continue checkout",
  close_confirm_leave: "Yes, exit checkout",

  // Phone & OTP screens
  close: "Close",
  phone_title: "Enter mobile number",
  phone_subtitle: "Provide your mobile number to continue",
  phone_continue_with: "Continue with",
  phone_send_otp_via: "Send OTP via",
  otp_resend_via: "Resend OTP via",
  otp_channel_sms: "SMS",
  login_not_you: "Not you?",
  go_to_phone_screen: "Go to Phone Screen",

  // Address form & list
  addr_pincode: "Pincode",
  addr_postal_code: "Postal code",
  addr_validating_pincode: "Validating pincode...",
  addr_first_name: "First name",
  addr_last_name: "Last name",
  addr_line1: "Flat, house number, floor, building",
  addr_line2: "Area, street, sector, village",
  addr_landmark: "Landmark",
  addr_city: "City",
  addr_state: "State",
  addr_email: "E-mail",
  addr_email_note: "Order delivery details will be sent here",
  addr_type_title: "Address type",
  addr_type_home: "Home",
  addr_type_office: "Office",
  addr_type_other: "Others",
  addr_add_new: "Add new address",
  addr_none_saved: "No saved addresses yet. Add one to continue.",
  addr_add_first: "Add your first address",
  addr_edit: "Edit",
  saved_addresses_title: "Saved addresses",
  addr_intro: "Including addresses linked to {{phone}} where we can deliver your order",
  addr_intro_checkout:
    "Including addresses linked to {{phone}}. Pick one and we'll fill it in at checkout",

  // Delivery & shipping
  delivery_card_title: "Delivery details",
  delivery_summary_title: "Delivery Details",
  delivery_no_address: "No address selected",
  delivery_add: "Add",
  delivery_change: "Change",
  delivery_edit_hint: "Click To Edit Address",
  shipping_method_title: "Shipping Method",

  // Coupons & offers
  coupon_sheet_title: "Apply Coupon",
  coupon_placeholder: "Enter coupon code",
  coupon_applicable: "Applicable coupons",
  coupon_unlock: "Unlock Coupons",
  coupon_apply: "Apply",
  coupon_none: "No offers available right now.",
  coupon_saved: "Saved",
  coupon_tap_remove: "Tap to remove",
  coupon_have_code: "Already have a coupon ?",

  // Confirm & payment window
  confirm_sheet_title: "Confirm Your Order",
  total_amount_inline: "Total amount:",
  cta_confirm_order: "Confirm & place order",
  rzp_sheet_title: "Complete Payment",
  rzp_loading: "Loading payment gateway...",
  rzp_retry: "Retry",
  rzp_window_open: "Payment window is open",
  rzp_window_note: "Complete the payment in the Razorpay window above, or close it to cancel.",
  rzp_initializing: "Initializing payment...",

  // Order confirmation
  oc_thank_you: "Thank you for your order!",
  oc_placed: "Your order has been successfully placed.",
  oc_preparing: "We're preparing your order and will notify you once it ships.",
  oc_order_number: "Order Number",
  oc_payment_method: "Payment Method",
  oc_estimated_delivery: "Estimated Delivery",
  oc_updates_note: "You will receive updates about your order via SMS or WhatsApp.",
  oc_track_order: "Track Order",
  oc_view_orders: "View orders",
  oc_continue_shopping: "Continue Shopping",

  // Dialogs
  celebration_thanks: "Woohoo! Thanks",
  try_again: "Try Again",
  logout_confirm_title: "Are you sure you want to log out?",
  logout_confirm_message: "You'll need to verify with OTP again next time",
  logout_stay: "No, stay logged in",
  exit_confirm_title: "Are you sure you want to exit?",
};

// Keys that already had a dedicated settings column before ui_customization.
// ui_customization wins; the column stays as the fallback so existing merchant
// copy keeps rendering.
const LEGACY_SETTING_KEYS = {
  cta_proceed: ["preProceedButtonLabel", "pre_proceed_button_label"],
  no_rule_qualified: [
    "preV2NoRuleQualifiedMessage",
    "pre_v2_no_rule_qualified_message",
  ],
  redirect_subtitle: ["redirectText", "pre_redirect_text"],
  tax_excluded_note: ["preV2PartialTaxText", "pre_v2_partial_tax_text"],
};

const readSessionSettings = () => getSessionValue("settingSession") || null;

export const getUiCustomization = (settings) =>
  settings?.uiCustomization || settings?.ui_customization || {};

export const interpolate = (template, vars) => {
  if (!vars) return template;
  return String(template).replace(/\{\{(\w+)\}\}/g, (match, key) =>
    vars[key] === undefined || vars[key] === null ? match : String(vars[key]),
  );
};

/**
 * Resolve a customer-facing string: merchant override → legacy setting → default.
 *
 * @param {string} key one of UI_TEXT_DEFAULTS
 * @param {Record<string, any>|null} [vars] {{placeholder}} values
 * @param {Record<string, any>|null} [settings] settings object (falls back to settingSession)
 */
export const uiText = (key, vars = null, settings = undefined) => {
  const resolved = settings === undefined ? readSessionSettings() : settings;
  const override = getUiCustomization(resolved)?.texts?.[key];
  if (typeof override === "string" && override.trim()) {
    return interpolate(override.trim(), vars);
  }

  for (const legacyKey of LEGACY_SETTING_KEYS[key] || []) {
    const legacy = resolved?.[legacyKey];
    if (typeof legacy === "string" && legacy.trim()) {
      return interpolate(legacy.trim(), vars);
    }
  }

  return interpolate(UI_TEXT_DEFAULTS[key] ?? "", vars);
};

/**
 * Bind the resolver to a settings object so components can use `{T("key")}`
 * in markup and stay reactive to settings changes.
 *
 * @param {Record<string, any>|null} settings
 * @returns {(key: string, vars?: Record<string, any>|null) => string}
 */
export const createTranslator =
  (settings) =>
  (key, vars = null) =>
    uiText(key, vars, settings);

export const isWhatsappPrimary = (settings) =>
  getUiCustomization(settings)?.branding?.whatsapp_primary === true;

export const DEFAULT_BRAND_COLOR = "#3173e3";

export const getBrandColor = (settings) => {
  const raw = getUiCustomization(settings)?.branding?.brand_color;
  return typeof raw === "string" && /^#[0-9a-f]{6}$/i.test(raw.trim())
    ? raw.trim()
    : DEFAULT_BRAND_COLOR;
};

export const getBrandForeground = (hex) => {
  const n = parseInt(String(hex).slice(1), 16);
  if (Number.isNaN(n)) return "#ffffff";
  const luminance =
    (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return luminance > 0.7 ? "#1a1a1a" : "#ffffff";
};

// White-label: drop the COD King mark from the legal footer.
export const isFooterBrandingHidden = (settings) =>
  getUiCustomization(settings)?.branding?.hide_footer_branding === true;

const isWhatsappOtpEnabled = (settings) => {
  if (!settings) return false;
  const value = settings.preWhatsappButton ?? settings.pre_whatsapp_button;
  if (value === true || value === 1) return true;
  if (value === false || value === 0 || value === null || value === undefined)
    return false;
  const str = String(value).toLowerCase().trim();
  return str === "true" || str === "1" || str === "yes";
};

// India-only country list with WhatsApp OTP off → SMS-only flow that gets the
// reassurance badges above the legal footer.
export const shouldShowTrustBadges = (settings) => {
  return true
  if (!settings || isWhatsappOtpEnabled(settings)) return false;
  const raw = settings.countryCodeList ?? settings.country_code_list;
  const list = (typeof raw === "string" ? raw.split(",") : raw || [])
    .map((c) => String(c).trim().toUpperCase())
    .filter((c) => c.length > 0);
  if (!list.length) return false;
  const countries = getFilteredCountries(list);
  return (
    countries.length === 1 &&
    String(countries[0]?.code || "").replace(/^\+/, "") === "91"
  );
};

export const getLegalLinks = (settings, fallbacks = {}) => {
  const branding = getUiCustomization(settings)?.branding || {};
  return {
    termsUrl: branding.terms_url?.trim() || fallbacks.termsUrl,
    privacyUrl: branding.privacy_url?.trim() || fallbacks.privacyUrl,
  };
};

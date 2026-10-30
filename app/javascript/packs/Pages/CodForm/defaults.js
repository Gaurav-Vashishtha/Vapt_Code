/**
 * Default / canonical config shapes edited by the COD Form admin screens.
 *
 * These mirror ARCHITECTURE sections B.1.1, B.1.2, C.1–C.6 and the product
 * defaults of PM_DECISIONS. The server's `normalize` is the authority; these
 * exist so a screen can render before (or without) a complete payload and so
 * "new" records start from the documented defaults. A contract change is a
 * change to this file (and api.js) only.
 */
import { clone, mergeDefaults } from "./utils";

/* B.1.1 — cod_form_shop_configs.general */
export const DEFAULT_GENERAL = {
  countries: [],
  pages: { product: true, cart: true, drawer: true, quick_buy: false },
  products: {
    scope: "all",
    include_product_ids: [],
    include_collection_ids: [],
    exclude_product_ids: [],
    exclude_collection_ids: [],
  },
  order_total: { min_cents: null, max_cents: null, message: "" },
  hide_out_of_stock: true,
  cod_only_through_form: false,
  cod_fee_taxable: false,
  otp: { enabled: null, mode: "before_order", risk_band: "medium", whatsapp: false, max_attempts: 3, resend_wait_seconds: 30 },
  rto: { gating_enabled: false, block_band: "high", min_score: null, message: "" },
  discounts: { code_field_enabled: false, codes_combine_with_offers: false },
  prepaid: { show_pay_online: true, discount_label_enabled: false, discount_label: "" },
  consent: { respect_customer_privacy: true },
  branding: { hide_powered_by: false },
  autocomplete: { enabled: false, provider: "google", google_api_key: "", ola_api_key: "" },
  abandonment: {
    enabled: true,
    delay_minutes: 15,
    create_draft_order: false,
    recovery_discount: { type: null, value: 0 },
  },
  embedded: { enabled: false, selector: "", position: "after", form_id: null },
  upsell_window_minutes: 5,
  language: "",
};

/* B.1.2 — cod_form_shop_configs.fraud */
export const DEFAULT_FRAUD = {
  blocked_message: "",
  limits: {
    phone: { enabled: false, max_orders: 3, window_hours: 24 },
    email: { enabled: false, max_orders: 3, window_hours: 24 },
    ip: { enabled: false, max_orders: 5, window_hours: 24 },
  },
  limit_message: "",
  max_quantity_per_order: null,
  max_quantity_message: "",
  min_submit_seconds: 3,
  honeypot: true,
};

/* C.1.2 — cod_button_configs.config (preset is a sibling of config) */
export const DEFAULT_BUTTON_PRESET = "B";
export const DEFAULT_BUTTON_CONFIG = {
  button: {
    labels: { default: "Buy with COD" },
    subtitles: { default: "" },
    style: {
      bg: "#111111",
      color: "#ffffff",
      border_color: "#111111",
      border_width: 0,
      radius: 8,
      shadow: "md",
      font_size: 18,
      bold: true,
      height: 56,
      full_width: true,
      icon: "cart",
      animation: "none",
    },
    placement: { position: "below", selector: "" },
    sticky: { enabled: true, labels: { default: "Buy with COD" } },
    cart: { enabled: false, labels: { default: "Checkout with COD" }, selector: "" },
    drawer: { enabled: false, labels: { default: "Checkout with COD" }, selector: "" },
    quick_buy: { enabled: false, selector: "" },
  },
  theme: {
    rename_buy_now: { default: "" },
    rename_add_to_cart: { default: "" },
    rename_checkout: { default: "" },
    rename_drawer_checkout: { default: "" },
    hide: { add_to_cart: false, buy_now: false, checkout: false, drawer_checkout: false, wallets: false },
  },
  quantity_widget: { enabled: true, position: "above_buttons", selector: "" },
};

/* C.2 — cod_forms.draft_config */
export const CORE_BLOCK_IDS = [
  "order_summary", "quantity_offer", "contact", "address", "shipping", "bumps", "discount", "totals", "submit",
];
export const CONTENT_BLOCK_TYPES = ["rich_text", "image", "trust_badges", "countdown", "threshold_bar"];
export const BUILT_IN_FIELD_KEYS = [
  "first_name", "last_name", "phone", "email", "country", "address1", "address2", "zip", "province", "city",
  "gst_number", "note", "marketing_consent",
];
export const LOCKED_FIELD_KEYS = ["phone", "country"];
export const SCHEMA_REQUIRED_FIELD_KEYS = ["zip", "province", "city"];
export const CUSTOM_FIELD_TYPES = ["text", "textarea", "select", "radio", "checkbox", "date"];

export const DEFAULT_FORM_CONFIG = {
  schema: 1,
  mode: "popup",
  design: {
    primary: "#111111",
    on_primary: "#ffffff",
    text: "#1a1a1a",
    muted: "#6b7280",
    background: "#ffffff",
    surface: "#f6f6f7",
    border: "#d9d9de",
    error: "#d72c0d",
    radius: 10,
    field_radius: 8,
    density: "comfortable",
    theme: "classic",
    header: { show_title: true, logo_url: "", show_close: true },
    sticky_submit: true,
    hide_shipping_selector_when_single: true,
  },
  blocks: [
    { id: "order_summary", type: "order_summary", enabled: true, settings: { show_image: true, show_compare_at: true, show_quantity: true } },
    { id: "quantity_offer", type: "quantity_offer", enabled: true, settings: {} },
    { id: "contact", type: "fields", enabled: true, settings: { group: "contact", title_key: "contact_title" } },
    { id: "address", type: "fields", enabled: true, settings: { group: "address", title_key: "address_title" } },
    { id: "shipping", type: "shipping", enabled: true, settings: {} },
    { id: "bumps", type: "bumps", enabled: true, settings: {} },
    { id: "discount", type: "discount", enabled: false, settings: {} },
    { id: "totals", type: "totals", enabled: true, settings: { show_tax_line: false } },
    { id: "submit", type: "submit", enabled: true, settings: { show_total_in_button: true } },
  ],
  fields: [
    { key: "first_name", type: "text", group: "contact", enabled: true, required: true, width: "full", autocomplete: "name", validation: { max: 60 } },
    { key: "last_name", type: "text", group: "contact", enabled: false, required: false, width: "half", autocomplete: "family-name", validation: { max: 60 } },
    { key: "phone", type: "tel", group: "contact", enabled: true, required: true, width: "full", autocomplete: "tel-national", validation: {} },
    { key: "email", type: "email", group: "contact", enabled: false, required: false, width: "full", autocomplete: "email", validation: {} },
    { key: "country", type: "country", group: "address", enabled: true, required: true, width: "full", validation: {} },
    { key: "address1", type: "text", group: "address", enabled: true, required: true, width: "full", autocomplete: "address-line1", validation: { min: 3, max: 120 } },
    { key: "address2", type: "text", group: "address", enabled: false, required: false, width: "full", autocomplete: "address-line2", validation: { max: 120 } },
    { key: "zip", type: "postal", group: "address", enabled: true, required: null, width: "half", autocomplete: "postal-code", validation: {} },
    { key: "province", type: "province", group: "address", enabled: true, required: true, width: "half", validation: {} },
    { key: "city", type: "city", group: "address", enabled: false, required: true, width: "half", validation: { max: 80 } },
    { key: "gst_number", type: "text", group: "address", enabled: false, required: false, width: "full", only_countries: ["IN"], validation: { regex: "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$" } },
    { key: "note", type: "textarea", group: "address", enabled: false, required: false, width: "full", validation: { max: 500 } },
    { key: "marketing_consent", type: "consent", group: "contact", enabled: false, required: false, width: "full", default_checked: false, channels: ["sms", "email"] },
  ],
  language: "",
  texts: {},
  thank_you: {
    type: "order_status",
    url: "",
    message: { en: "Thank you {first_name}! Your order {order_name} is confirmed." },
    whatsapp: { phone: "", message: { en: "Hi, I just placed order {order_name}." } },
  },
  steps: { phone_first: false },
  pay_online: { enabled: true },
};

/* Fill a form config received from the API; arrays (blocks, fields) are kept as sent. */
export const withFormDefaults = (config) => {
  const merged = mergeDefaults(DEFAULT_FORM_CONFIG, config || {});
  if (!Array.isArray(merged.blocks) || merged.blocks.length === 0) merged.blocks = clone(DEFAULT_FORM_CONFIG.blocks);
  if (!Array.isArray(merged.fields) || merged.fields.length === 0) merged.fields = clone(DEFAULT_FORM_CONFIG.fields);
  return merged;
};

/* Form themes (design.theme). Choosing one sets the colours and corner radius of that look;
   every value can still be changed afterwards. "express" is the look of the COD King checkout
   widget (OTP, saved address and partial payment screens). */
export const FORM_THEMES = {
  classic: {
    primary: DEFAULT_FORM_CONFIG.design.primary,
    on_primary: DEFAULT_FORM_CONFIG.design.on_primary,
    text: DEFAULT_FORM_CONFIG.design.text,
    muted: DEFAULT_FORM_CONFIG.design.muted,
    background: DEFAULT_FORM_CONFIG.design.background,
    surface: DEFAULT_FORM_CONFIG.design.surface,
    border: DEFAULT_FORM_CONFIG.design.border,
    error: DEFAULT_FORM_CONFIG.design.error,
    radius: DEFAULT_FORM_CONFIG.design.radius,
    field_radius: DEFAULT_FORM_CONFIG.design.field_radius,
  },
  express: {
    primary: "#000000",
    on_primary: "#ffffff",
    text: "#2f2f2f",
    muted: "#7e7e7e",
    background: "#ffffff",
    surface: "#f6f8fc",
    border: "#e2e6ee",
    error: "#e00000",
    radius: 12,
    field_radius: 4,
  },
};

/* FRM-21 fallback, used only when GET /cod_form/forms/defaults has no templates. */
export const FALLBACK_TEMPLATES = [
  { key: "classic", name: "Classic", design: clone(DEFAULT_FORM_CONFIG.design), blocks_order: CORE_BLOCK_IDS },
  {
    key: "minimal",
    name: "Minimal",
    design: { ...clone(DEFAULT_FORM_CONFIG.design), primary: "#1a1a1a", surface: "#ffffff", border: "#e5e5e5", radius: 4, field_radius: 4, density: "compact" },
    blocks_order: ["contact", "address", "shipping", "order_summary", "quantity_offer", "bumps", "discount", "totals", "submit"],
  },
  {
    key: "bold",
    name: "Bold",
    design: { ...clone(DEFAULT_FORM_CONFIG.design), primary: "#e11d48", on_primary: "#ffffff", surface: "#fff1f2", border: "#fecdd3", radius: 16, field_radius: 12 },
    blocks_order: ["order_summary", "quantity_offer", "bumps", "contact", "address", "shipping", "discount", "totals", "submit"],
  },
  {
    key: "compact",
    name: "Compact",
    design: { ...clone(DEFAULT_FORM_CONFIG.design), radius: 8, field_radius: 6, density: "compact" },
    blocks_order: ["order_summary", "contact", "address", "shipping", "quantity_offer", "bumps", "discount", "totals", "submit"],
  },
];

/* English defaults of the buyer-facing texts (G.7). The API's
   `forms/defaults.texts` wins; this is the last fallback for the preview. */
export const FALLBACK_TEXTS = {
  title: "Cash on Delivery",
  close: "Close",
  loading: "Loading…",
  powered_by: "Powered by COD King",
  secure_note: "Pay when your order arrives",
  summary_title: "Order summary",
  quantity: "Quantity",
  item_singular: "item",
  item_plural: "items",
  you_save: "You save {total}",
  out_of_stock: "Out of stock",
  contact_title: "Enter your shipping address",
  address_title: "Delivery address",
  label_first_name: "First name",
  label_full_name: "Full name",
  label_last_name: "Last name",
  label_phone: "Phone number",
  label_email: "Email",
  label_country: "Country",
  label_address1: "Address",
  label_address2: "Apartment, suite, etc.",
  label_province: "State / Province",
  label_city: "City",
  label_zip: "Postal code",
  label_pincode: "Pincode",
  label_gst_number: "GST number",
  label_note: "Order note",
  label_marketing_consent: "Send me news and offers",
  placeholder_first_name: "",
  placeholder_last_name: "",
  placeholder_phone: "",
  placeholder_email: "",
  placeholder_address1: "House number and street",
  placeholder_address2: "",
  placeholder_province: "Select",
  placeholder_city: "",
  placeholder_zip: "",
  placeholder_gst_number: "",
  placeholder_note: "",
  error_required: "This field is required",
  error_blocked: "Cash on delivery is not available for this order.",
  error_no_shipping: "We don't deliver to this address yet.",
  shipping_title: "Shipping",
  shipping_free: "Free",
  shipping_enter_address: "Enter your address to see shipping options",
  discount_title: "Discount code",
  discount_placeholder: "Discount code",
  discount_apply: "Apply",
  discount_remove: "Remove",
  discount_applied: "Discount applied",
  subtotal: "Subtotal",
  discount: "Discount",
  shipping: "Shipping",
  cod_fee: "COD fee",
  tax: "Tax",
  tax_included: "Including taxes",
  total: "Total",
  savings: "You save",
  submit: "Complete order — {total}",
  submit_processing: "Placing your order…",
  pay_online: "Pay online instead",
  pay_online_hint: "",
  otp_title: "Verify your phone",
  otp_subtitle: "Enter the code we sent to {phone}",
  otp_placeholder: "Code",
  otp_verify: "Verify",
  otp_verifying: "Verifying…",
  otp_resend: "Resend code",
  otp_resend_in: "Resend in {seconds}s",
  otp_change_number: "Change number",
  otp_via_sms: "Send by SMS",
  otp_via_whatsapp: "Send by WhatsApp",
  payment_title: "How would you like to pay?",
  payment_full_cod: "Cash on delivery",
  payment_partial: "Pay part now",
  payment_prepaid: "Pay online",
  payment_pay_now: "Pay now",
  payment_pay_later: "On delivery",
  payment_continue: "Continue",
  bump_add: "Add",
  upsell_timer: "Offer ends in {seconds}s",
  processing_title: "Placing your order",
  processing_subtitle: "Please keep this window open",
  thank_you_title: "Order confirmed",
  thank_you_message: "Thank you {first_name}! Your order {order_name} is confirmed.",
  thank_you_order: "Order {order_name}",
  thank_you_continue: "Continue shopping",
  thank_you_whatsapp: "Message us on WhatsApp",
  exit_title: "Leave without ordering?",
  exit_stay: "Keep my order",
  exit_leave: "Leave",
};

/* C.3 — shipping rate */
export const newShippingRate = (currency) => ({
  name: "",
  description: "",
  price_cents: 0,
  currency: currency || null,
  active: true,
  source: "manual",
  conditions: {
    countries: [],
    provinces: [],
    subtotal_min_cents: null,
    subtotal_max_cents: null,
    weight_min_grams: null,
    weight_max_grams: null,
    quantity_min: null,
    quantity_max: null,
    products: { mode: "any", product_ids: [], collection_ids: [] },
  },
});
export const withRateDefaults = (rate) => mergeDefaults(newShippingRate(null), rate || {});

/* C.4 — offers */
export const DEFAULT_TARGETING = { scope: "all", product_ids: [], collection_ids: [] };

export const newQuantityTier = (quantity) => ({
  quantity,
  discount_type: quantity > 1 ? "percentage" : "none",
  value: quantity > 1 ? 10 : 0,
  label: { default: "" },
  badge: { default: "" },
  image_url: "",
  preselected: false,
});

export const OFFER_CONFIG_DEFAULTS = {
  quantity: {
    title: { default: "Buy more, save more" },
    layout: "cards",
    show_widget_on_product_page: true,
    tiers: [
      { quantity: 1, discount_type: "none", value: 0, label: { default: "1 pack" }, badge: { default: "" }, image_url: "", preselected: false },
      { quantity: 2, discount_type: "percentage", value: 10, label: { default: "2 packs" }, badge: { default: "Most popular" }, image_url: "", preselected: true },
      { quantity: 3, discount_type: "percentage", value: 15, label: { default: "3 packs" }, badge: { default: "" }, image_url: "", preselected: false },
    ],
    apply_to_higher_quantities: true,
  },
  bump: {
    title: { default: "" },
    description: { default: "" },
    image_url: "",
    kind: "custom",
    variant_id: null,
    price_cents: 0,
    compare_at_cents: null,
    checked_by_default: false,
    quantity_picker: false,
    max_quantity: 1,
    requires_shipping: false,
    taxable: true,
    position: "before_totals",
  },
  downsell: {
    trigger_after_closes: 1,
    discount_type: "percentage",
    value: 10,
    title: { default: "Wait! Here is 10% off" },
    body: { default: "Complete your order now and save." },
    accept_label: { default: "Claim discount" },
    decline_label: { default: "No thanks" },
    timer_seconds: 0,
  },
  upsell: {
    variant_id: null,
    quantity: 1,
    discount_type: "percentage",
    value: 20,
    title: { default: "Add one more for 20% off" },
    body: { default: "" },
    accept_label: { default: "Add to my order" },
    decline_label: { default: "No thanks" },
    timer_seconds: 120,
  },
  bundle: {
    product_ids: [],
    discount_type: "percentage",
    value: 10,
    title: { default: "Frequently bought together" },
    body: { default: "" },
    button_label: { default: "" },
    show_on_product_page: true,
    show_in_form: true,
    position: "after_summary",
    page_position: "above_button",
    page_selector: "",
  },
  pre_upsell: {
    display: "popup",
    position: "before_totals",
    match: "any",
    min_cart_cents: null,
    max_cart_cents: null,
    source: "products",
    product_ids: [],
    collection_id: null,
    max_products: 3,
    discount_type: "percentage",
    value: 10,
    quantity_picker: false,
    max_quantity: 3,
    title: { default: "Wait! Add this to your order" },
    body: { default: "Special price, only with this order." },
    accept_label: { default: "Add to my order" },
    decline_label: { default: "No thanks, complete my order" },
    timer_seconds: 0,
  },
  threshold: {
    kind: "free_shipping",
    threshold_cents: 0,
    gift_variant_id: null,
    text_progress: { default: "Add {remaining} more for free shipping" },
    text_reached: { default: "You unlocked free shipping!" },
  },
};

export const newOffer = (offerType) => ({
  offer_type: offerType,
  name: "",
  status: "draft",
  priority: 0,
  targeting: clone(DEFAULT_TARGETING),
  config: clone(OFFER_CONFIG_DEFAULTS[offerType] || {}),
  starts_at: null,
  ends_at: null,
});

export const withOfferDefaults = (offer) => {
  const base = newOffer(offer && offer.offer_type);
  const merged = mergeDefaults(base, offer || {});
  if (offer && offer.config && Array.isArray(offer.config.tiers)) merged.config.tiers = offer.config.tiers;
  return merged;
};

/* B.6 — A/B test */
export const newAbTest = (offerType) => ({
  name: "",
  offer_type: offerType || "quantity",
  status: "draft",
  variants: [
    { key: "a", offer_id: null, weight: 50 },
    { key: "control", offer_id: null, weight: 50 },
  ],
});

/* C.6 — pixel */
export const newPixel = (platform) => ({
  platform,
  pixel_id: "",
  access_token: "",
  enabled: true,
  targeting: clone(DEFAULT_TARGETING),
  config: {
    browser: true,
    server: true,
    purchase_event: "purchase",
    events: { form_open: true, add_payment_info: false, purchase: true },
    test_event_code: "",
    conversion_label: "",
    ad_account_id: "",
  },
});
export const withPixelDefaults = (pixel) => mergeDefaults(newPixel((pixel && pixel.platform) || "meta"), pixel || {});

/* B.18 — integrations */
export const DEFAULT_CRM_CONFIG = { events: { order: true, abandoned: true } };

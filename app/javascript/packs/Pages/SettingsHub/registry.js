import {
  PaintBrushFlatIcon,
  MobileIcon,
  DiscountIcon,
  CreditCardPercentIcon,
  CreditCardIcon,
  CheckCircleIcon,
  PhoneIcon,
  CartIcon,
  HideIcon,
  CashDollarIcon,
  ChatIcon,
  ChatReferralIcon,
  SendIcon,
  GlobeIcon,
  TransactionIcon,
  AppsIcon,
  IntegrationsIcon,
  MegaphoneIcon,
  SettingsIcon,
  ButtonIcon,
  ShieldCheckMarkIcon,
  ChartVerticalIcon,
  AdjustIcon,
  SparklesIcon,
} from "./icons";
import I18n from "../../i18n-lang";

export const t = (key, fallback) => I18n.t(key, { defaultValue: fallback });

export const SETTINGS_GROUPS = [
  {
    id: "checkout-widget",
    labelKey: "settings_hub.group_checkout_widget",
    label: "Checkout Widget",
  },
  { id: "cod-form", labelKey: "settings_hub.group_cod_form", label: "COD Form" },
  {
    id: "notifications",
    labelKey: "settings_hub.group_notifications",
    label: "Notifications",
  },
  {
    id: "cod-verification",
    labelKey: "settings_hub.group_cod_workflow",
    label: "COD Workflow",
  },
  {
    id: "integrations",
    labelKey: "settings_hub.group_integrations",
    label: "Integrations",
  },
  {
    id: "general",
    labelKey: "settings_hub.group_general",
    label: "General",
  },
];

/**
 * Single source of truth for the Settings hub sidebar, routing and search.
 * Adding a feature = adding one entry here (plus its component route in Home.jsx
 * if it's a brand-new path).
 *
 * - `path` is the EXISTING route of the screen; the hub wraps it, it does not fork it.
 * - `isVisible(ctx)` mirrors existing gating (never widens access).
 * - Two items may share a path (Default WhatsApp / SMS live on one screen);
 *   the first one in this array wins the selected highlight.
 */
// COD Form group: visible only once the per-shop module flag is known to be on
// (ctx.codForm comes from GET /cod_form/bootstrap; null while it loads).
const codFormVisible = (ctx) => ctx.codForm?.moduleEnabled === true;

export const SETTINGS_ITEMS = [
  // ── Checkout Widget ──────────────────────────────────────────────
  {
    id: "otp-verification",
    group: "checkout-widget",
    labelKey: "settings_hub.item_otp_verification",
    label: "OTP verification",
    icon: MobileIcon,
    path: "/features/otp/pre-order",
    keywords: ["otp", "verify", "verification", "phone", "login", "pre-order"],
  },
  {
    id: "partial-payment",
    group: "checkout-widget",
    labelKey: "settings_hub.item_partial_payment",
    label: "Partial payments & COD",
    icon: CreditCardIcon,
    path: "/features/partial-payment",
    keywords: ["advance", "deposit", "rto", "partial cod", "rules", "token"],
  },
  {
    id: "prepaid-discount",
    group: "checkout-widget",
    labelKey: "settings_hub.item_prepaid_discount",
    label: "Prepaid discount",
    icon: CreditCardPercentIcon,
    path: "/features/prepaid-discount",
    keywords: ["discount", "prepaid", "online payment"],
  },
  {
    id: "discounts",
    group: "checkout-widget",
    labelKey: "settings_hub.item_discounts",
    label: "Discounts",
    icon: DiscountIcon,
    path: "/features/discounts",
    keywords: ["coupon", "code", "offer", "bxgy", "automatic"],
  },
  {
    id: "upsell",
    group: "checkout-widget",
    labelKey: "settings_hub.item_upsell",
    label: "Upsell",
    icon: CartIcon,
    path: "/features/upsell",
    keywords: ["upsell", "cross-sell", "items you may like", "free gift", "gift with purchase"],
  },
   {
    id: "ui-customization",
    group: "checkout-widget",
    labelKey: "settings_hub.item_ui_customization",
    label: "UI customization",
    icon: PaintBrushFlatIcon,
    path: "/features/ui-customization",
    altPaths: ["/features/otp/pre-order/ui"],
    keywords: ["app embed", "theme", "widget", "design", "colors", "branding"],
  },
  // ── COD Form ─────────────────────────────────────────────────────
  // Setup stays first: its path is a prefix of the others, and the longer
  // candidates win the longest-prefix match for sub-pages.
  { id: "cod-form-setup",    group: "cod-form", labelKey: "settings_hub.item_cod_form_setup",    label: "Setup",            icon: SettingsIcon,        path: "/features/cod-form",          keywords: ["cod form", "order form", "enable", "app embed", "countries", "otp", "autocomplete", "cap", "usage"], isVisible: codFormVisible },
  { id: "cod-form-buttons",  group: "cod-form", labelKey: "settings_hub.item_cod_form_buttons",  label: "Buttons",          icon: ButtonIcon,          path: "/features/cod-form/buttons",  keywords: ["buy button", "buy now", "cod button", "sticky", "rename", "hide add to cart", "preset"], isVisible: codFormVisible },
  { id: "cod-form-designer", group: "cod-form", labelKey: "settings_hub.item_cod_form_designer", label: "Form designer",    icon: PaintBrushFlatIcon,  path: "/features/cod-form/designer", keywords: ["fields", "design", "texts", "translation", "thank you", "publish", "template", "custom field"], isVisible: codFormVisible },
  { id: "cod-form-fraud",    group: "cod-form", labelKey: "settings_hub.item_cod_form_fraud",    label: "Fraud protection", icon: ShieldCheckMarkIcon, path: "/features/cod-form/fraud",    keywords: ["block", "blacklist", "fake orders", "limit", "ip", "phone", "rto", "blocked attempts"], isVisible: codFormVisible },
  { id: "cod-form-offers",   group: "cod-form", labelKey: "settings_hub.item_cod_form_offers",   label: "Offers",           icon: DiscountIcon,        path: "/features/cod-form/offers",   keywords: ["upsell", "downsell", "order bump", "quantity offer", "bundle", "a/b test", "free gift"], isVisible: codFormVisible },
  { id: "cod-form-analytics", group: "cod-form", labelKey: "settings_hub.item_cod_form_analytics", label: "Analytics",       icon: ChartVerticalIcon,   path: "/features/cod-form/analytics", keywords: ["analytics", "sessions", "funnel", "conversion", "form opens", "orders", "abandoned", "report"], isVisible: codFormVisible },
  // Shipping rates live inside Advanced settings: /features/cod-form/shipping keeps this item selected.
  { id: "cod-form-advanced", group: "cod-form", labelKey: "settings_hub.item_cod_form_advanced", label: "Advanced settings", icon: AdjustIcon,          path: "/features/cod-form/advanced", altPaths: ["/features/cod-form/shipping"], keywords: ["advanced", "order limit", "minimum order", "maximum order", "shipping", "delivery", "rates", "free shipping", "province", "discount code", "pay online", "abandoned form", "embedded", "consent", "branding", "powered by"], isVisible: codFormVisible },
  // ── COD Workflow ─────────────────────────────────────────────────
  {
    id: "post-order-otp",
    group: "cod-verification",
    labelKey: "settings_hub.item_post_order_otp",
    label: "Post-order OTP verification",
    icon: CheckCircleIcon,
    path: "/features/post-order-otp",
    altPaths: ["/features/otp/post-order"],
    keywords: ["otp", "thank you page", "confirm", "ivr", "cancel"],
  },
  {
    id: "whatsapp-cod-verification",
    group: "cod-verification",
    labelKey: "settings_hub.item_whatsapp_cod_verification",
    label: "WhatsApp COD verification",
    icon: PhoneIcon,
    path: "/features/whatsapp-cod-verification",
    keywords: ["whatsapp", "verify", "confirm order", "automation", "binding"],
  },
  {
    id: "plus-checkout-widget",
    group: "cod-verification",
    labelKey: "settings_hub.item_plus_checkout_widget",
    label: "Shopify Plus widget",
    icon: CartIcon,
    path: "/features/shopify-plus-widget",
    altPaths: ["/features/otp/checkout-extension"],
    keywords: ["shopify plus", "checkout extension", "otp"],
  },
  {
    id: "limit-cod",
    group: "cod-verification",
    labelKey: "settings_hub.item_limit_cod",
    label: "Limit COD",
    icon: HideIcon,
    path: "/features/limit-cod",
    altPaths: ["/features/cod-show-hide"],
    keywords: ["hide", "block", "show", "risk", "pincode", "zip", "fraud"],
  },
  {
    id: "cod-to-prepaid",
    group: "cod-verification",
    labelKey: "settings_hub.item_cod_to_prepaid",
    label: "COD to prepaid",
    icon: TransactionIcon,
    path: "/features/cod-to-prepaid",
    keywords: ["convert", "payment link", "razorpay", "reminder", "upi"],
    isVisible: (ctx) => !!ctx.isPrepaidEnabled,
  },

  {
    id: "cod-fees",
    group: "cod-verification",
    labelKey: "settings_hub.item_cod_fees",
    label: "COD fees",
    icon: CashDollarIcon,
    path: "/features/cod-fees",
    keywords: ["fee", "charge", "surcharge", "shipping", "extra"],
  },

  // ── Notifications ────────────────────────────────────────────────
  {
    id: "branded-whatsapp",
    group: "notifications",
    labelKey: "settings_hub.item_branded_whatsapp",
    label: "Business Brand WhatsApp",
    icon: ChatIcon,
    path: "/features/whatsapp",
    keywords: ["whatsapp", "waba", "meta", "own number", "templates"],
  },
  {
    id: "whatsapp-inbox",
    group: "notifications",
    labelKey: "settings_hub.item_whatsapp_inbox",
    label: "WhatsApp inbox",
    icon: ChatReferralIcon,
    path: "/features/whatsapp/inbox",
    altPaths: ["/features/whatsapp/replies"],
    keywords: ["inbox", "support", "tickets", "replies", "chat", "customer messages", "conversations"],
  },
  {
    id: "whatsapp-ai-agent",
    group: "notifications",
    labelKey: "settings_hub.item_whatsapp_ai_agent",
    label: "WhatsApp AI agent",
    icon: SparklesIcon,
    path: "/features/whatsapp/inbox/ai",
    keywords: ["ai", "ai agent", "chatbot", "bot", "auto reply", "ai credits", "gpt", "assistant"],
  },
  {
    id: "whatsapp-campaigns",
    group: "notifications",
    labelKey: "settings_hub.item_whatsapp_campaigns",
    label: "WhatsApp campaigns",
    icon: MegaphoneIcon,
    // Its own prefix, not /features/whatsapp/..., so the sidebar highlights
    // this item rather than Business Brand WhatsApp on every campaign screen.
    path: "/features/whatsapp-campaigns",
    altPaths: ["/features/whatsapp/campaigns", "/features/whatsapp/audience"],
    keywords: [
      "whatsapp",
      "campaign",
      "broadcast",
      "bulk message",
      "marketing",
      "audience",
      "segment",
      "contacts",
      "list",
    ],
  },
  {
    id: "customer-notifications",
    group: "notifications",
    labelKey: "settings_hub.item_customer_notifications",
    label: "Customer notifications",
    icon: SendIcon,
    path: "/features/notifications",
    keywords: [
      "whatsapp",
      "sms",
      "cod king number",
      "order confirmation",
      "abandoned cart",
      "default whatsapp",
    ],
  },
  {
    id: "local-sms-gateway",
    group: "notifications",
    labelKey: "settings_hub.item_local_sms_gateway",
    label: "Local SMS gateway",
    icon: GlobeIcon,
    path: "/networks",
    keywords: ["sms provider", "operator", "twilio", "sender id", "gateway"],
  },
  // ── Integrations ─────────────────────────────────────────────────
  // One row, not one per tool. The screen behind it is a directory of cards,
  // so a new integration is added there rather than lengthening the sidebar.
  {
    id: "integrations",
    group: "integrations",
    labelKey: "settings_hub.group_integrations",
    label: "Integrations",
    icon: IntegrationsIcon,
    path: "/integrations",
    altPaths: [
      "/integrations/google-ads",
      "/integrations/pixel",
      "/integrations/webhooks",
      "/settings-hub/webhooks",
      "/integrations/tiktok",
      "/integrations/form-pixels",
      "/integrations/google-sheets",
    ],
    keywords: [
      "google",
      "ads",
      "conversion",
      "meta",
      "facebook",
      "pixel",
      "capi",
      "webhook",
      "api",
      "events",
      "callback",
      "developer",
      "shopflo",
    ],
  },

  // ── General ──────────────────────────────────────────────────────
  // Plans, Billing and Help & Support are top-level destinations in the admin
  // nav, not settings items, so they are deliberately absent here (and not
  // hub-wrapped below): opening them must not light up "Settings".
  {
    id: "reports",
    group: "general",
    labelKey: "store.scheduled_reports",
    label: "Reports",
    icon: ChartVerticalIcon,
    path: "/features/reports",
    keywords: ["reports", "scheduled reports", "email report", "digest", "schedule", "csv", "delivery status", "abandoned cart"],
  },
  {
    id: "partner-apps",
    group: "general",
    labelKey: "settings_hub.item_partner_apps",
    label: "Partner apps",
    icon: AppsIcon,
    path: "/settings-hub/partner-apps",
    keywords: ["apps", "partners", "recommended", "integrations"],
  },
];

const normalizePath = (path) =>
  path && path.length > 1 ? path.replace(/\/+$/, "") : path;

/**
 * Every settings-area path keeps the sidebar, including screens that are not
 * sidebar items themselves (WhatsApp overview, section hubs, sub-forms) — the
 * sidebar must never disappear while the merchant is inside Settings.
 * Full-screen flows (onboarding wizard, custom setup) are intentionally absent.
 */
const WRAPPED_PREFIXES = [
  "/settings-hub",
  "/features",
  "/checkout",
  "/messaging",
  "/post-purchase",
  "/checkout-enhancements",
  "/integrations",
  "/networks",
];

export const isHubWrappedPath = (path) => {
  const normalized = normalizePath(path);
  if (!normalized) return false;
  return WRAPPED_PREFIXES.some(
    (prefix) => normalized === prefix || normalized.startsWith(`${prefix}/`),
  );
};

export const visibleItems = (ctx = {}) =>
  SETTINGS_ITEMS.filter((item) => !item.isVisible || item.isVisible(ctx));

/** Longest-prefix match so sub-pages (e.g. /features/partial-payment/add) keep their item selected. */
export const findItemByPath = (path) => {
  const normalized = normalizePath(path);
  if (!normalized) return null;
  let best = null;
  SETTINGS_ITEMS.forEach((item) => {
    [item.path, ...(item.altPaths || [])].forEach((candidate) => {
      const matches =
        normalized === candidate || normalized.startsWith(`${candidate}/`);
      if (matches && (!best || candidate.length > best.path.length)) {
        best = item;
      }
    });
  });
  return best;
};

export const getFirstVisibleItem = (ctx) => visibleItems(ctx)[0] || null;

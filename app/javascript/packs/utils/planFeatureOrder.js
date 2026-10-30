import I18n from "../i18n-lang";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";
import { planFeatureLabel } from "./planFeatureHelpers";

/**
 * Pricing pages list the features the merchant has switched on first, then the rest.
 * A feature line is matched to a topic by its translation key, so this works in every locale.
 */
const TOPIC_KEYS = {
  otp: [
    "plans.otp_verification_sms_whatsapp",
    "plans_india.otp_verification_sms_whatsapp",
    "plans.otp_verification_checkout_shopify_plus",
    "plans.persistent_signin_feature",
    "plans.realtime_verification_dashboard",
    "plans_india.realtime_verification_dashboard",
    "plans.auto_filled_shipping",
    "plans_india.auto_filled_shipping",
  ],
  partial: [
    "plans.partial_payment_rate",
    "plans.partial_payment_1_percent",
    "plans.partial_payment_0_8_percent",
    "plans.partial_payment_0_5_percent",
    "plans_india.partial_payment_1_5_percent",
    "plans_india.partial_payment_0_8_percent",
    "plans_india.partial_payment_0_5_percent",
    "plans.partial_payment_shipping_rate_keyword",
    "plans_india.partial_payment_shipping_rate_keyword",
    "plans.cod_to_prepaid_incentives",
  ],
  sms: [
    "plans.competitive_sms_rates",
    "plans.premium_sms_rates",
    "plans.enterprise_sms_rates",
    "plans_india.competitive_sms_rates",
    "plans_india.premium_sms_rates",
    "plans_india.enterprise_sms_rates",
    "plans.reliable_sms_gateway",
    "plans.branded_sms_sender",
    "plans_india.branded_sms_sender_v3",
    "admin.sms_cost_extra",
  ],
  whatsapp: [
    "plans.whatsapp_business_rates",
    "plans.whatsapp_rates",
    "plans.whatsapp_rates_enterprise",
    "plans_india.whatsapp_business_messaging",
    "plans_india.whatsapp_rates_pro",
    "plans_india.whatsapp_rates_enterprise",
    "plans.branded_whatsapp_paid_plans",
    "plans.branded_whatsapp",
    "plans.whatsapp_chat_widget",
  ],
  confirmation: [
    "plans.automated_order_confirmation",
    "plans_india.automated_order_confirmation",
  ],
  fulfilment: ["plans.order_fulfillment_notifications"],
  abandoned: ["plans.abandoned_cart_recovery", "plans.abandoned_cart_reminders"],
  cod_form: ["plans.cod_form_orders", "plans.cod_form_orders_unlimited"],
};

// "All Free plan features included" style lines always stay first.
const LEAD_KEYS = [
  "plans.all_free_features",
  "plans.all_pro_features",
  "plans.all_enterprise_features",
  "plans_india.everything_in_enterprise",
];

const MARK = "\u0001";
const VARS = { price: MARK, country: MARK, count: MARK, amount: MARK, rate: MARK };

// The fixed pieces of a translation, with its variables cut out.
const piecesOf = (key) => {
  const text = I18n.t(key, { ...VARS, defaultValue: "" });
  if (!text || typeof text !== "string") return null;
  const parts = text.split(MARK).filter((part) => part.trim() !== "");
  return parts.length ? parts : null;
};

const matchesKey = (label, key) => {
  const parts = piecesOf(key);
  if (!parts) return false;
  if (parts.length === 1 && I18n.t(key, { ...VARS, defaultValue: "" }) === parts[0]) {
    return label === parts[0];
  }
  let from = 0;
  for (let i = 0; i < parts.length; i += 1) {
    const at = label.indexOf(parts[i], from);
    if (at < 0) return false;
    from = at + parts[i].length;
  }
  return true;
};

const matchesAny = (label, keys) => keys.some((key) => matchesKey(label, key));

const isOn = (value) => value === true || value === "true" || value === 1 || value === "1";

/** Topics the merchant has switched on. `codFormOn`: the COD Form is on for the store. */
export const selectedTopics = (setting, codFormOn) => {
  const s = setting || {};
  const sms = isOn(s.confirmationSmsEnabled) || isOn(s.enableFulfilmentMessage) || isOn(s.abandonedCartEnabled);
  const whatsapp =
    isOn(s.confirmationWhatsapp) || isOn(s.fulfilmentWhatsapp) || isOn(s.acWhatsapp) || isOn(s.sendVerificationLinkOnly);
  const otp = isOn(s.enablePreOrderOtp);
  return {
    otp,
    partial: isOn(s.partialPaymentEnabled),
    // OTP codes go out by SMS and WhatsApp, so their rates matter to an OTP store too.
    sms: sms || otp,
    whatsapp: whatsapp || otp,
    confirmation: isOn(s.confirmationSmsEnabled) || isOn(s.confirmationWhatsapp),
    fulfilment: isOn(s.enableFulfilmentMessage) || isOn(s.fulfilmentWhatsapp),
    abandoned: isOn(s.abandonedCartEnabled) || isOn(s.acWhatsapp),
    cod_form: !!codFormOn,
  };
};

/** Same list with the lines of switched-on features first; the order is otherwise kept. */
export const sortPlanFeatures = (features, topics) => {
  const list = Array.isArray(features) ? features : [];
  const on = Object.keys(TOPIC_KEYS).filter((topic) => topics && topics[topic]);
  const lead = [];
  // `pin: true` lines (the COD Form limit) always stay near the top, so they are never
  // folded away under "more features".
  const pinned = [];
  const first = [];
  const rest = [];
  list.forEach((feature) => {
    const label = planFeatureLabel(feature);
    if (typeof label !== "string") {
      rest.push(feature);
    } else if (matchesAny(label, LEAD_KEYS)) {
      lead.push(feature);
    } else if (feature && feature.pin && !(feature.topic && topics && topics[feature.topic])) {
      pinned.push(feature);
    } else if (
      (feature && feature.topic && topics && topics[feature.topic]) ||
      on.some((topic) => matchesAny(label, TOPIC_KEYS[topic]))
    ) {
      first.push(feature);
    } else {
      rest.push(feature);
    }
  });
  return lead.concat(first.slice(0, 3), pinned, first.slice(3), rest);
};

/** Hook for the plan cards: the merchant's switched-on topics and a sorter bound to them. */
export const usePlanFeatureOrder = (setting) => {
  const bootstrap = useCodFormBootstrap();
  const codFormOn = !!(bootstrap && bootstrap.moduleEnabled && bootstrap.mode === "cod_form");
  const topics = selectedTopics(setting, codFormOn);
  return { topics, sort: (features) => sortPlanFeatures(features, topics) };
};

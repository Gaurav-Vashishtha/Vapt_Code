import { hasValidChargeId } from "./shopUtils";

/**
 * Partial rule is disabled when explicitly false (default / missing = enabled).
 */
function isPartialRuleEnabled(rule) {
  if (rule == null) return false;
  if (rule.is_enabled === false || rule.isEnabled === false) return false;
  return true;
}

/**
 * "Pay 100% now" partial rule — same idea as PrepaidDiscount.jsx and
 * AnalyticsController#shop_has_full_payment_prepaid_discount? (percentage + ~100%).
 */
export function isFullPaymentPartialRule(rule) {
  const amountType = String(rule?.amount_type || rule?.amountType || "").toLowerCase();
  const amount = Number(rule?.amount ?? 0);
  if (amountType !== "percentage") return false;
  return amount >= 99.99 && amount <= 100;
}

function ruleHasPositiveDiscountValue(rule) {
  const dv = rule?.discount_value ?? rule?.discountValue;
  const n = parseFloat(String(dv ?? "").trim());
  return !Number.isNaN(n) && n > 0;
}

/**
 * Paid-only "prepaid discount": full upfront payment rule with a non-zero discount.
 * Partial payment without this discount remains available on the Free plan.
 */
export function ruleHasFullPaymentPrepaidDiscount(rule) {
  if (!isPartialRuleEnabled(rule)) return false;
  if (!isFullPaymentPartialRule(rule)) return false;
  return ruleHasPositiveDiscountValue(rule);
}

/**
 * Mirrors AnalyticsController#shop_has_full_payment_prepaid_discount?
 * (partial_payment_enabled + enabled 100% rule + discount_value > 0).
 */
export function shopHasFullPaymentPrepaidDiscount(setting, partialRuleSets) {
  if (!setting || setting.partialPaymentEnabled !== true) return false;
  if (!Array.isArray(partialRuleSets) || partialRuleSets.length === 0) return false;
  return partialRuleSets.some((r) => ruleHasFullPaymentPrepaidDiscount(r));
}

/**
 * Merchant is on a billed Shopify subscription (not Free / no active charge).
 */
export function isPaidPlanSubscriber(plan, shop) {
  const name = String(plan?.name || "").toLowerCase();
  if (name === "free") return false;
  return hasValidChargeId(shop);
}

/**
 * Paid-only capabilities that must be turned off before moving to the Free plan.
 * `codShowHideEnabled` should come from GET /settings/is_cod_show_hide_enabled when possible.
 * `partialRuleSets` should be the GET /partial_rule_sets array when available (paid shops).
 */
export function collectPaidPlanDowngradeBlockerKeys(
  setting,
  codShowHideEnabled,
  partialRuleSets = [],
  whatsappNotificationsActive = false,
) {
  const keys = [];

  // WhatsApp BSP notifications live outside `setting` (in template bindings), so
  // this is gated on a separate flag and checked before the `!setting` guard.
  if (whatsappNotificationsActive) {
    keys.push("whatsapp_active_notification");
  }

  if (!setting) return keys;

  if (shopHasFullPaymentPrepaidDiscount(setting, partialRuleSets)) {
    keys.push("prepaid_discount");
  }

  if (codShowHideEnabled) {
    keys.push("cod_show_hide");
  }

  if (setting.codFeeEnabled === true || setting.enableShippingCodFees === true) {
    keys.push("cod_fees");
  }

  const branded = String(
    setting.brandedWhatsappNumber || setting.branded_whatsapp_number || "",
  ).trim();
  if (branded.length > 0) {
    keys.push("branded_whatsapp");
  }

  if (setting.prepaidEnabled === true) {
    keys.push("cod_prepaid");
  }

  if (
    setting.plusCheckoutOtpExtensionEnabled === true ||
    setting.plus_checkout_otp_extension_enabled === true
  ) {
    keys.push("plus_checkout_extension");
  }

  const brandingHidden =
    setting.preShowBranding === false || setting.pre_show_branding === false;
  if (brandingHidden) {
    keys.push("cod_branding_hidden");
  }

  // Persistent sign-in is on every plan now (Free included), so it never blocks a downgrade.

  return keys;
}

/**
 * Map each blocker key to the minimum target plan tier that supports it.
 * Used to filter blocker keys per-target when deciding whether to block a downgrade.
 */
const BLOCKER_MIN_TIER = {
  cod_branding_hidden: "enterprise_plus",
  // WhatsApp notifications exist on Enterprise / Enterprise Plus / india_budget,
  // so they block downgrades to anything below (Free, Pro) but not between them.
  whatsapp_active_notification: "enterprise_or_higher",
};

function normalizePlanKey(planKey) {
  return String(planKey || "")
    .trim()
    .toLowerCase()
    .replace(/[\s_-]+/g, " ");
}

/**
 * Plan keys vary per surface — PlansIndia uses "india_budget", PlansNewDesign
 * uses "Premium" for the same Enterprise tier, and Plans.jsx uses "Enterprise".
 * An unrecognised key used to fall through to "free", which made every paid
 * target look like a downgrade to Free.
 */
const PLAN_TIER_BY_KEY = {
  free: "free",
  pro: "pro",
  enterprise: "enterprise_or_higher",
  premium: "enterprise_or_higher",
  "india budget": "enterprise_or_higher",
  "enterprise plus": "enterprise_plus",
  "enterprise premium": "enterprise_plus",
};

const TIER_RANK = {
  free: 0,
  pro: 1,
  enterprise_or_higher: 2,
  enterprise_plus: 3,
};

function planTier(planKey) {
  return PLAN_TIER_BY_KEY[normalizePlanKey(planKey)] || "free";
}

function toPrice(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(String(value).replace(/[^0-9.]/g, ""));
  return Number.isFinite(n) ? n : null;
}

/**
 * Paid features only need to be turned off when moving DOWN. Prices are the
 * authoritative signal because plan keys differ per surface; they are only
 * comparable when both come from the same rendered plan list (same currency),
 * so the caller passes the current plan's price from that same list. Falls back
 * to tier rank when either price is unknown.
 */
export function isUpgradeToTarget({
  currentPlanKey,
  currentPlanPrice,
  targetPlanKey,
  targetPrice,
} = {}) {
  if (normalizePlanKey(currentPlanKey) === normalizePlanKey(targetPlanKey)) {
    return false;
  }

  const current = toPrice(currentPlanPrice);
  const target = toPrice(targetPrice);
  if (current !== null && target !== null) return target >= current;

  const currentRank = TIER_RANK[planTier(currentPlanKey)];
  const targetRank = TIER_RANK[planTier(targetPlanKey)];
  if (currentRank === undefined || targetRank === undefined) return false;
  return targetRank > currentRank;
}

/**
 * Given the full list of enabled paid-feature keys and the target plan key,
 * return only the keys that are blockers for that specific downgrade.
 */
export function filterBlockerKeysForTarget(allBlockerKeys, targetPlanKey) {
  if (!Array.isArray(allBlockerKeys) || allBlockerKeys.length === 0) return [];
  const tier = planTier(targetPlanKey);
  const isFreeTarget = tier === "free";

  return allBlockerKeys.filter((key) => {
    const required = BLOCKER_MIN_TIER[key];
    if (required === "enterprise_plus") return tier !== "enterprise_plus";
    if (required === "enterprise_or_higher")
      return tier !== "enterprise_plus" && tier !== "enterprise_or_higher";
    return isFreeTarget;
  });
}

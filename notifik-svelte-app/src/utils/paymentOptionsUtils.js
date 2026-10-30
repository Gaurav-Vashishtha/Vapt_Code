import { get } from "svelte/store";
import {
  createPartialCart,
  getCart,
  fetchPartialRuleSets,
  fetchRtoDecision,
} from "../services/otpService.js";
import {
  getCurrentStep,
  getMachineId,
  getSessionValue,
  setSessionValue,
  setLocalValue,
  getShopDomain,
  addCartAttributesWithOtpStore,
  applyDiscountCodeToOtpStore,
  removeDiscountCodeFromOtpStore,
} from "../utilities/otpUtils.js";
import { formatCurrency, isTaxIncludedWithProductAny, isPhoneInList, isEmailInList } from "./helpers.js";
import { isOptimizedBuyNowEnabled, getCustomerEmail } from "../services/sessionService.js";
import otpStore, { otpStoreActions } from "../stores/otpStore.js";
import { appStore } from "../stores/buttonManager.js";
import {
  getDescBundle,
  updateAllLineItemsDescription,
  removeAllLineItemsDescription,
  getCodkDiscounts,
  getCodkImageURLs,
  prepaidDiscountAttribute,
} from "./bundlePaymentUtils.js";
import { executePost } from "../services/otpService.js";
import { giftDiscountCents } from "../services/freeGiftService.js";
import {
  EXISTING_CUSTOMER_KEY,
  phoneKey,
  pendingExistingCustomerLookup,
  lookupExistingCustomer,
} from "../services/api.js";
import { createLightweightGraphQLClient } from "../services/lightweightGraphQLClient.js";

/**
 * Calculate tax amounts for a rule based on stored tax data
 * @param {Object} rule - The payment rule
 * @param {Object} cart - The cart data
 * @returns {{ ruleTax: number, remainingTax: number } | null}
 */
const calculateTaxForRule = (rule, cart) => {
  try {
    const otpState = get(otpStore);
    const calculatedTax = otpState?.calculatedTaxData;
    const settings = otpState?.settings || getSessionValue("settingSession");

    if (
      isTaxIncludedWithProductAny(settings, getSessionValue("settingSession"))
    ) {
      return null;
    }

    // Check if tax info should be shown
    const codFormEnabled =
      settings?.cod_form_enabled === true ||
      settings?.cod_form_enabled === "true";
    const showTaxInfo =
      codFormEnabled ||
      (settings?.pre_v2_show_tax_info === true ||
        settings?.preV2ShowTaxInfo === true);

    if (!showTaxInfo || !calculatedTax || !calculatedTax.total_tax) {
      return null;
    }

    // Calculate tax rate
    const taxLines = calculatedTax?.tax_lines;
    let taxRate = 0;
    if (taxLines?.length > 0) {
      taxRate = taxLines.reduce((s, l) => s + (parseFloat(l.rate) || 0), 0);
    }
    if (taxRate <= 0) {
      const totalTax = calculatedTax.total_tax > 10000
        ? calculatedTax.total_tax / 100
        : calculatedTax.total_tax;
      const totalPrice = (cart?.total_price || 0) / 100;
      if (totalTax > 0 && totalPrice > 0) {
        taxRate = totalTax / totalPrice;
      }
    }

    if (taxRate <= 0) return null;

    // Calculate payNow amount
    const totalPriceCents = cart?.total_price || 0;
    const totalAfterDiscount = totalPriceCents / 100;
    const ruleAmount = parseFloat(rule?.amount) || 0;

    let payNow = 0;
    if (rule?.amount_type === "cod") {
      payNow = totalAfterDiscount;
    } else if (rule?.amount_type === "percentage" && rule?.amount === "100.0") {
      payNow = totalAfterDiscount;
    } else if (rule?.amount_type === "fixed") {
      payNow = Math.min(ruleAmount, totalAfterDiscount);
    } else if (rule?.amount_type === "percentage") {
      payNow = (totalAfterDiscount * ruleAmount) / 100;
    }

    const remaining = Math.max(0, totalAfterDiscount - payNow);

    const ruleTax = Math.floor(payNow * taxRate * 100) / 100;
    const remainingTax = Math.floor(remaining * taxRate * 100) / 100;

    return { ruleTax, remainingTax };
  } catch (_) {
    return null;
  }
};

export const PAYMENT_TYPES = {
  PERCENTAGE: "percentage",
  FIXED: "fixed",
  COD: "cod",
};

export const DISCOUNT_TYPES = {
  PERCENTAGE: "percentage",
  FIXED: "fixed",
  FIXED_AMOUNT: "fixed_amount",
};

export const AMOUNT_CONSTANTS = {
  FULL_PAYMENT_PERCENTAGE: "100.0",
  ZERO: "0",
};

export const MAX_UNIQUE_LINES_FOR_PARTIAL = 45;

export const DEFAULT_VALUES = {
  CURRENCY_CODE: "INR",
  LOCALE: "en-IN",
  CART_TOTAL: 0,
  RULE_AMOUNT: 0,
  DISCOUNT_VALUE: 0,
};

const safeParseFloat = (value, fallback = 0) => {
  const parsed = parseFloat(value);
  return isNaN(parsed) ? fallback : parsed;
};

const safeTrim = (v) => (typeof v === "string" ? v.trim() : "");
const validateRule = (rule) => {
  if (!rule || typeof rule !== "object") throw new Error("Invalid rule object provided");
  for (const f of ["id", "amount_type", "rule_name"]) if (!rule[f]) throw new Error(`Missing required field: ${f} in rule`);
  return true;
};
const validateCart = (cart) => {
  if (!cart) throw new Error("Cart object is null or undefined");
  if (!Array.isArray(cart.items)) throw new Error("Cart items must be an array");
  return true;
};

export const convertFloatToInt = (value) => {
  const numericValue = safeParseFloat(value);
  return Math.round(numericValue);
};

const isFullPercentagePayment = (rule) => rule.amount === AMOUNT_CONSTANTS.FULL_PAYMENT_PERCENTAGE && rule.amount_type === PAYMENT_TYPES.PERCENTAGE;
const isCodPayment = (rule) => rule.amount_type === PAYMENT_TYPES.COD;
/**
 * Cart value for min/max rule filtering and payment UI. Uses post-discount total
 * (Shopify `total_price` in cents) so rules update when coupons/discounts change.
 * Do not use `original_total_price` here or a rule (e.g. min 700) stays eligible after
 * the cart drops to 680 with a discount.
 */
const calculateCartTotal = (cart) => {
  if (!cart || typeof cart !== "object") return 0;
  const cents = Number(cart.total_price);
  if (!Number.isNaN(cents) && cents >= 0) return cents / 100;
  const items = cart.items;
  if (!Array.isArray(items)) return 0;
  return items.reduce((sum, item) => {
    const price = safeParseFloat(item?.presentment_price);
    const quantity = safeParseFloat(item?.quantity);
    return sum + price * quantity;
  }, 0);
};

const getCartProductIds = (cartItems) => {
  if (!Array.isArray(cartItems) || cartItems.length === 0) return [];
  const ids = [];
  for (const item of cartItems) {
    const pid =
      item.product_id != null
        ? String(item.product_id)
        : item.productId != null
          ? String(item.productId)
          : item.merchandise?.product?.id
            ? String(item.merchandise.product.id).split("/").pop()
            : null;
    if (pid) ids.push(pid);
  }
  return [...new Set(ids)];
};

const filterRulesByCartProducts = (rules, cartProductIds) => {
  if (!Array.isArray(rules)) return [];
  return rules.filter((rule) => {
    try {
      const productScope = rule.product_scope ?? rule.productScope ?? (rule.is_all === true || rule.isAll === true ? "all" : "include");
      const productIds = rule.product_ids ?? rule.productIds;
      const ruleIds = Array.isArray(productIds)
        ? productIds.map((x) => String(x))
        : typeof productIds === "string" && productIds
          ? productIds.split(",").map((x) => x.trim()).filter(Boolean)
          : [];
      if (productScope === "all" || ruleIds.length === 0) return true;
      if (cartProductIds.length === 0) return productScope === "exclude";
      const matchAnyProduct = rule.match_any_product ?? rule.matchAnyProduct ?? false;
      if (productScope === "include") {
        return matchAnyProduct
          ? cartProductIds.some((pid) => ruleIds.includes(pid))
          : cartProductIds.every((pid) => ruleIds.includes(pid));
      }
      if (productScope === "exclude") {
        return !cartProductIds.some((pid) => ruleIds.includes(pid));
      }
      return true;
    } catch (_e) {
      return false;
    }
  });
};

const filterRulesByCartTotal = (rules, cartTotal) => {
  if (!Array.isArray(rules)) return [];
  return rules.filter((rule) => {
    try {
      validateRule(rule);
      const min = safeParseFloat(rule.min_cart_range);
      const max = safeParseFloat(rule.max_cart_range);
      if (min === 0 && max === 0) return true;
      if (max === 0 && cartTotal >= min) return true;
      if (min === 0 && cartTotal <= max) return true;
      return cartTotal >= min && cartTotal <= max;
    } catch (_) {
      return false;
    }
  });
};

/* Cart item count gate. cart_items_range stays null until a merchant sets a
   bound, so only rules that have one ever need the item count. That count has
   to come from cart.js: the optimistic Buy Now cart is scraped from the page
   and can't be trusted for quantities, so these rules wait for the real cart. */
const parseCartItemsBound = (value) => {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

export const getCartItemsRange = (rule) => {
  const range = rule?.cart_items_range ?? rule?.cartItemsRange;
  if (!range || typeof range !== "object") return null;
  const min = parseCartItemsBound(range.min_cart_items ?? range.minCartItems);
  const max = parseCartItemsBound(range.max_cart_items ?? range.maxCartItems);
  return min === null && max === null ? null : { min, max };
};

export const rulesNeedCartItemCount = (rules) =>
  Array.isArray(rules) && rules.some((rule) => getCartItemsRange(rule) !== null);

export const getCartItemCount = (cart) => {
  if (typeof cart?.item_count === "number") return cart.item_count;
  const items = Array.isArray(cart?.items) ? cart.items : [];
  return items.reduce((sum, item) => sum + (Number(item?.quantity) || 0), 0);
};

export const filterRulesByCartItemCount = (rules, itemCount) => {
  if (!Array.isArray(rules)) return [];
  return rules.filter((rule) => {
    const range = getCartItemsRange(rule);
    if (!range) return true;
    if (range.min !== null && itemCount < range.min) return false;
    if (range.max !== null && itemCount > range.max) return false;
    return true;
  });
};

/**
 * Get customer's zipcode from selected shipping address
 * @returns {string|null} - Customer's zipcode or null if not available
 */
const getCustomerZipcode = () => {
  try {
    const shippingAddresses = getSessionValue("shipping_addresses") || [];
    const stored = getSessionValue("cod_king_selected_address");

    let selectedAddress = null;

    if (stored && typeof stored === "object" && !Array.isArray(stored)) {
      selectedAddress = stored;
    } else if (stored != null && Array.isArray(shippingAddresses)) {
      selectedAddress = shippingAddresses.find(
        (addr) => addr?.id === stored || String(addr?.id) === String(stored)
      );
    }

    if (!selectedAddress && shippingAddresses.length > 0) {
      selectedAddress = shippingAddresses[0];
    }

    if (!selectedAddress) return null;

    const zipcode =
      selectedAddress.zip ||
      selectedAddress.postal_code ||
      selectedAddress.postalCode ||
      selectedAddress.pincode ||
      "";

    return zipcode ? String(zipcode).trim() : null;
  } catch (_e) {
    return null;
  }
};

/**
 * Check if a zipcode is blacklisted for a rule
 * Supports individual zipcodes and ranges (e.g., "400001-400010")
 * @param {string} zipcode - Customer's zipcode
 * @param {string} blacklistStr - Comma-separated list of zipcodes/ranges
 * @returns {boolean} - True if zipcode is blacklisted
 */
const isZipcodeBlacklisted = (zipcode, blacklistStr) => {
  if (!zipcode || !blacklistStr) return false;
  
  const normalizedZip = String(zipcode).trim().replace(/\s+/g, "");
  if (!normalizedZip) return false;

  const entries = blacklistStr.split(",").map((e) => e.trim()).filter(Boolean);
  
  return entries.some((entry) => {
    if (entry.includes("-")) {
      const [rangeStart, rangeEnd] = entry.split("-").map((r) => r.trim());
      return normalizedZip >= rangeStart && normalizedZip <= rangeEnd;
    }
    return normalizedZip === entry;
  });
};

/**
 * Filter rules by customer's zipcode (blacklist check)
 * Rules with zipcode_blacklist_enabled=true will be hidden if customer's zipcode matches
 * @param {Array} rules - Array of payment rules
 * @param {string} customerZipcode - Customer's zipcode from shipping address
 * @returns {Array} - Filtered rules (excluding blacklisted ones)
 */
const filterRulesByZipcode = (rules, customerZipcode) => {
  if (!Array.isArray(rules)) return [];
  if (!customerZipcode) return rules;

  return rules.filter((rule) => {
    try {
      const blacklistEnabled =
        rule.zipcode_blacklist_enabled === true ||
        rule.zipcode_blacklist_enabled === "true" ||
        rule.zipcodeBlacklistEnabled === true ||
        rule.zipcodeBlacklistEnabled === "true";

      if (!blacklistEnabled) return true;

      const blacklist = rule.zipcode_blacklist || rule.zipcodeBlacklist || "";
      if (!blacklist) return true;

      return !isZipcodeBlacklisted(customerZipcode, blacklist);
    } catch (_e) {
      return true;
    }
  });
};

const filterRulesByZipcodeWhitelist = (rules, customerZipcode) => {
  if (!Array.isArray(rules)) return [];
  if (!customerZipcode) return rules;

  return rules.filter((rule) => {
    try {
      const whitelistEnabled =
        rule.zipcode_whitelist_enabled === true ||
        rule.zipcode_whitelist_enabled === "true" ||
        rule.zipcodeWhitelistEnabled === true ||
        rule.zipcodeWhitelistEnabled === "true";

      if (!whitelistEnabled) return true;

      const whitelist = rule.zipcode_whitelist || rule.zipcodeWhitelist || "";
      if (!whitelist) return true;

      return isZipcodeBlacklisted(customerZipcode, whitelist);
    } catch (_e) {
      return true;
    }
  });
};

const getCustomerIdentity = () => {
  const addresses = getSessionValue("shipping_addresses") || [];
  const stored = getSessionValue("cod_king_selected_address");
  const address =
    stored && typeof stored === "object" && !Array.isArray(stored)
      ? stored
      : (Array.isArray(addresses) &&
          (addresses.find((a) => String(a?.id) === String(stored)) || addresses[0])) ||
        null;
  const verified = getSessionValue("verifiedNumberData") || {};
  const otpState = get(otpStore) || {};
  return {
    phones: [
      verified.otpVerifiedPhoneNumber,
      otpState.otpData?.phoneNumber,
      get(appStore)?.phoneNumber,
      address?.phone,
    ].filter(Boolean),
    // Only the selected address's email counts, so a blocked email on another
    // saved address doesn't hide rules. Addresses without one check out with
    // the customer email (same fallback the address list displays).
    emails: [
      String(address?.email || "").trim() ||
        getCustomerEmail() ||
        get(appStore)?.customerEmail,
    ].filter(Boolean),
  };
};

// ── Repeat customers ──────────────────────────────────────────────────
// Two rule settings depend on whether the verified shopper has ordered here
// before: repeat_customer_discount (an extra order-level discount on prepaid
// rules) and cod_cooling_period (hide COD until N days after their last order).

const jsonEnabled = (cfg) =>
  !!cfg && typeof cfg === "object" && (cfg.enabled === true || cfg.enabled === "true");

const repeatDiscountOf = (rule) => {
  if (!rule || !isFullPercentagePayment(rule)) return null;
  const cfg = rule.repeat_customer_discount;
  if (!jsonEnabled(cfg)) return null;
  const value = safeParseFloat(cfg.discount_value);
  if (!(value > 0)) return null;
  return {
    type: cfg.discount_type === "percentage" ? "percentage" : "fixed",
    value,
  };
};

const coolingDaysOf = (rule) => {
  const cfg = rule?.cod_cooling_period;
  if (!jsonEnabled(cfg)) return 0;
  const days = parseInt(cfg.days, 10);
  return days > 0 ? days : 0;
};

const rulesNeedExistingCustomer = (rules) =>
  Array.isArray(rules) &&
  rules.some(
    (r) => repeatDiscountOf(r) || (isCodPayment(r) && coolingDaysOf(r) > 0),
  );

// The lookup runs when the OTP is sent (see lookupExistingCustomer in
// services/api.js). Here we read its answer for the verified phone, wait for
// it if it is still in flight, and only ask directly if it never ran.
const getExistingCustomerStatus = async () => {
  const verified = getSessionValue("verifiedNumberData") || {};
  const key = phoneKey(verified.otpVerifiedPhoneNumber);
  if (!key) return null;

  const read = () => {
    const cached = getSessionValue(EXISTING_CUSTOMER_KEY);
    return cached && cached.phone === key ? cached : null;
  };
  if (read()) return read();

  const pending = pendingExistingCustomerLookup(key);
  if (pending) {
    await pending;
    return read();
  }

  await lookupExistingCustomer({
    phone: verified.otpVerifiedPhoneNumber,
    shop: getShopDomain(),
  });
  return read();
};

const inCoolingPeriod = (lastOrderDate, days) => {
  const last = Date.parse(lastOrderDate);
  if (Number.isNaN(last)) return false;
  return Date.now() - last < days * 24 * 60 * 60 * 1000;
};

// Adds the repeat discount to the prepaid rule's own order-level discount, so
// the save line, badge, _codkDiscounts and the checkout discount function all
// pick it up unchanged. Mixed types are combined as a fixed amount on the cart
// total.
const withRepeatDiscount = (rule, extra, cartTotal) => {
  const baseValue = safeParseFloat(rule.discount_value);
  const baseType = rule.discount_type || "fixed";
  const hasBase = !!String(rule.discount_code || "").trim() && baseValue > 0;
  const label = String(rule.discount_code || "").trim() || "Repeat customer discount";

  let discount_type = extra.type;
  let discount_value = extra.value;
  if (hasBase && baseType === extra.type) {
    discount_value = baseValue + extra.value;
  } else if (hasBase) {
    const toAmount = (type, value) =>
      type === "percentage" ? (cartTotal * value) / 100 : value;
    discount_type = "fixed";
    discount_value = toAmount(baseType, baseValue) + toAmount(extra.type, extra.value);
  }
  return {
    ...rule,
    discount_type,
    discount_value: String(Math.round(discount_value * 100) / 100),
    discount_code: label,
    repeat_customer_applied: true,
  };
};

const applyExistingCustomerRules = async (rules, cartTotal) => {
  if (!rulesNeedExistingCustomer(rules)) return rules;
  const status = await getExistingCustomerStatus();
  if (!status?.existing) return rules;

  return rules
    .filter((rule) => {
      if (!isCodPayment(rule)) return true;
      const days = coolingDaysOf(rule);
      return !(days > 0 && status.lastOrderDate && inCoolingPeriod(status.lastOrderDate, days));
    })
    .map((rule) => {
      const extra = repeatDiscountOf(rule);
      return extra ? withRepeatDiscount(rule, extra, cartTotal) : rule;
    });
};

const filterRulesByBlocklist = (rules, { phones, emails }) => {
  if (!Array.isArray(rules)) return [];
  if (phones.length === 0 && emails.length === 0) return rules;
  return rules.filter((rule) => {
    const phoneList = rule?.phone_blacklist || rule?.phoneBlacklist;
    const emailList = rule?.email_blacklist || rule?.emailBlacklist;
    return (
      !phones.some((phone) => isPhoneInList(phone, phoneList)) &&
      !emails.some((email) => isEmailInList(email, emailList))
    );
  });
};

/**
 * Read the customer's country code from the selected shipping address.
 * GlobalZipStat is keyed on (country, zip), so sending it sharpens the
 * pincode signal; the backend falls back to a country-less lookup without it.
 */
const getCustomerCountry = () => {
  try {
    const shippingAddresses = getSessionValue("shipping_addresses") || [];
    const stored = getSessionValue("cod_king_selected_address");

    let selectedAddress = null;
    if (stored && typeof stored === "object" && !Array.isArray(stored)) {
      selectedAddress = stored;
    } else if (stored != null && Array.isArray(shippingAddresses)) {
      selectedAddress = shippingAddresses.find(
        (addr) => addr?.id === stored || String(addr?.id) === String(stored)
      );
    }
    if (!selectedAddress && shippingAddresses.length > 0) {
      selectedAddress = shippingAddresses[0];
    }
    if (!selectedAddress) return null;

    const country =
      selectedAddress.country_code ||
      selectedAddress.countryCode ||
      selectedAddress.country ||
      "";
    return country ? String(country).trim() : null;
  } catch (_e) {
    return null;
  }
};

// Mirrors PartialRuleSet::RTO_BAND_RANK — keep the two in sync.
const RTO_BAND_RANK = { low: 0, medium: 1, high: 2 };
const RTO_DEFAULT_BAND = "high";

const readRtoConfig = (rule) => {
  const raw = rule?.rto_engine ?? rule?.rtoEngine ?? null;
  if (!raw) return null;

  let cfg = raw;
  // Tolerate a JSON string in case a serializer stringifies the jsonb column.
  if (typeof cfg === "string") {
    try {
      cfg = JSON.parse(cfg);
    } catch (_e) {
      return null;
    }
  }
  if (typeof cfg !== "object" || Array.isArray(cfg)) return null;

  const enabled =
    cfg.enabled === true || cfg.enabled === "true" || cfg.enabled === 1 || cfg.enabled === "1";
  if (!enabled) return null;

  const band = String(cfg.hide_at_band ?? cfg.hideAtBand ?? "").toLowerCase();
  const rawScore = cfg.min_score ?? cfg.minScore;
  const hasScore = rawScore !== null && rawScore !== undefined && String(rawScore).trim() !== "";

  return {
    hideAtBand: band in RTO_BAND_RANK ? band : RTO_DEFAULT_BAND,
    minScore: hasScore ? Math.min(100, Math.max(0, parseInt(rawScore, 10) || 0)) : null,
  };
};

/**
 * Decide whether a scored decision hides a rule.
 * Band and score are OR'd: whichever trips first hides it.
 * Mirrors PartialRuleSet#rto_engine_hides? on the Rails side.
 */
const rtoDecisionHidesRule = (cfg, decision) => {
  if (!cfg || !decision) return false;

  const bandRank = RTO_BAND_RANK[String(decision.band ?? "").toLowerCase()];
  if (bandRank !== undefined && bandRank >= RTO_BAND_RANK[cfg.hideAtBand]) return true;

  if (cfg.minScore === null) return false;
  const score = Number(decision.risk_score);
  if (!Number.isFinite(score)) return false;

  return score >= cfg.minScore;
};

/**
 * Hide payment rules that opted into the RTO engine when this shopper's
 * phone + pincode scores as risky.
 *
 * Fails open in every degenerate case — no opted-in rules, no phone/zip,
 * API error, timeout, malformed body — because silently removing COD for
 * every shopper is far worse than occasionally showing it to a risky one.
 *
 * Costs nothing for shops that never enable it: with no opted-in rule the
 * function returns before making any network call.
 */
const filterRulesByRtoEngine = async (rules, { phone, zip, country, cartTotal }) => {
  if (!Array.isArray(rules) || rules.length === 0) return rules;

  const configs = new Map();
  rules.forEach((rule) => {
    const cfg = readRtoConfig(rule);
    if (cfg) configs.set(rule, cfg);
  });
  if (configs.size === 0) return rules;

  // Scoring is keyed on the shopper's identity + pincode; without either there
  // is nothing to score against, so leave the rules alone.
  if (!phone && !zip) return rules;

  const result = await fetchRtoDecision({
    shopifyDomain: getShopDomain(),
    phone,
    zip,
    country,
    cartTotal,
  });
  if (!result?.success || !result.data) return rules;

  return rules.filter((rule) => {
    const cfg = configs.get(rule);
    if (!cfg) return true;
    try {
      return !rtoDecisionHidesRule(cfg, result.data);
    } catch (_e) {
      return true;
    }
  });
};

/**
 * Get variant IDs from cart items
 * @param {Array} items - Cart items
 * @returns {Array} - Array of variant IDs as strings
 */
const getCartVariantIds = (items) => {
  if (!Array.isArray(items)) return [];
  const ids = [];
  for (const item of items) {
    const vid =
      item.variant_id ||
      item.variantId ||
      (item.merchandise?.id
        ? String(item.merchandise.id).split("/").pop()
        : null);
    if (vid) ids.push(String(vid));
  }
  return [...new Set(ids)];
};

const rulesNeedCollections = (rules) => {
  if (!Array.isArray(rules)) return false;
  return rules.some((r) => {
    const scope = r.collection_scope ?? r.collectionScope;
    const ids = r.collection_ids ?? r.collectionIds;
    return scope && scope !== "all" && Array.isArray(ids) && ids.length > 0;
  });
};

const getCartProductCollectionsMap = async (cartProductIds, settings) => {
  const map = new Map();
  if (!Array.isArray(cartProductIds) || cartProductIds.length === 0) return map;
  const shopifyDomain = settings?.shopDomain || getShopDomain();
  const storefrontToken = settings?.storeFrontToken;
  if (!shopifyDomain || !storefrontToken) return map;

  try {
    const client = createLightweightGraphQLClient(shopifyDomain, storefrontToken);
    const gids = cartProductIds.map((id) => `gid://shopify/Product/${id}`);
    const query = `
      query GetProductCollections($ids: [ID!]!) {
        nodes(ids: $ids) {
          ... on Product {
            id
            collections(first: 50) { nodes { id } }
          }
        }
      }
    `;
    const response = await client.query(query, { ids: gids });
    const nodes = response?.data?.nodes ?? [];
    for (const node of nodes) {
      if (!node?.id) continue;
      const productId = String(node.id).split("/").pop();
      const collectionIds = (node.collections?.nodes ?? [])
        .map((c) => String(c?.id || "").split("/").pop())
        .filter(Boolean);
      map.set(productId, collectionIds);
    }
  } catch (_e) {}
  return map;
};

const filterRulesByCartCollections = (rules, productCollectionsMap) => {
  if (!Array.isArray(rules)) return [];
  return rules.filter((rule) => {
    try {
      const scope = rule.collection_scope ?? rule.collectionScope ?? "all";
      const ruleIds = rule.collection_ids ?? rule.collectionIds;
      const ids = Array.isArray(ruleIds)
        ? ruleIds.map(String)
        : typeof ruleIds === "string" && ruleIds
          ? ruleIds.split(",").map((s) => s.trim()).filter(Boolean)
          : [];
      if (scope === "all" || ids.length === 0) return true;
      if (!productCollectionsMap || productCollectionsMap.size === 0) {
        return scope === "exclude";
      }
      const idSet = new Set(ids);
      const productMatches = (colls) => Array.from(colls || []).some((c) => idSet.has(String(c)));
      const matchAnyProduct = rule.match_any_product ?? rule.matchAnyProduct ?? false;
      if (scope === "include") {
        if (matchAnyProduct) {
          for (const colls of productCollectionsMap.values()) {
            if (productMatches(colls)) return true;
          }
          return false;
        }
        for (const colls of productCollectionsMap.values()) {
          if (!productMatches(colls)) return false;
        }
        return true;
      }
      if (scope === "exclude") {
        for (const colls of productCollectionsMap.values()) {
          if (productMatches(colls)) return false;
        }
        return true;
      }
      return true;
    } catch (_e) {
      return true;
    }
  });
};

const filterRulesByCartVariants = (rules, cartVariantIds) => {
  if (!Array.isArray(rules)) return [];
  return rules.filter((rule) => {
    try {
      const variantScope = rule.variant_scope ?? rule.variantScope ?? "all";
      const variantIds = rule.variant_ids ?? rule.variantIds;
      const ruleIds = Array.isArray(variantIds)
        ? variantIds.map((x) => String(x))
        : typeof variantIds === "string" && variantIds
          ? variantIds.split(",").map((x) => x.trim()).filter(Boolean)
          : [];
      
      if (variantScope === "all" || ruleIds.length === 0) return true;
      if (cartVariantIds.length === 0) return variantScope === "exclude";

      const matchAnyProduct = rule.match_any_product ?? rule.matchAnyProduct ?? false;
      if (variantScope === "include") {
        return matchAnyProduct
          ? cartVariantIds.some((vid) => ruleIds.includes(vid))
          : cartVariantIds.every((vid) => ruleIds.includes(vid));
      }
      if (variantScope === "exclude") {
        return !cartVariantIds.some((vid) => ruleIds.includes(vid));
      }
      return true;
    } catch (_e) {
      return true;
    }
  });
};

export const initializeCartAndRules = async (
  setCartTotal,
  setRuleSets,
  setSelectedRule,
  setIsFullPercentage,
  setIsCOD,
  setIsLoaderLoading,
) => {
  try {
    let storedRules = getSessionValue("ruleSets");
    if (!Array.isArray(storedRules) || storedRules.length === 0) {
      try {
        const result = await fetchPartialRuleSets(getShopDomain());
        if (result?.success && Array.isArray(result.data)) {
          storedRules = result.data;
          setSessionValue("ruleSets", storedRules);
        }
      } catch (_) {}
    }
    if (!Array.isArray(storedRules) || storedRules.length === 0) {
      setSessionValue("partial_payment_no_eligible_rules", false);
      setRuleSets([]);
      setIsLoaderLoading(false);
      return;
    }

    // Optimized: filter against whatever cart we already have — the OPTIMISTIC
    // (scraped) cart is enough to resolve product/variant/collection rules, so
    // payment cards don't wait for the clear/add/cart.js chain; the caller
    // re-runs this to reconcile once the authoritative cart lands.
    // Off: original behavior — wait for isCartReady before filtering.
    const optimized = isOptimizedBuyNowEnabled();
    // Item-count rules opt out of the optimistic cart: they wait for cart.js.
    const needsRealCart = rulesNeedCartItemCount(storedRules);
    const realCartReady = () => {
      const s = get(otpStore);
      return s.isCartReady && !s.isSummaryOptimistic;
    };
    const cartNotAvailable = () =>
      optimized && !needsRealCart
        ? !get(otpStore).currentCartData?.items?.length
        : !realCartReady();
    let cart = get(otpStore)?.currentCartData;
    if (cartNotAvailable()) {
      let waitCount = 0;
      while (cartNotAvailable() && waitCount < 50) {
        await new Promise((r) => setTimeout(r, 100));
        waitCount++;
      }
      cart = get(otpStore).currentCartData;
    }
    if (!cart?.items?.length && get(otpStore).isCartReady) {
      cart = await getCart(true);
    } else if (needsRealCart && !realCartReady()) {
      // The cart chain never settled; read cart.js directly for the count.
      cart = (await getCart(true)) || cart;
    }

    validateCart(cart);

    const cartTotal = calculateCartTotal(cart);

    setCartTotal(cartTotal);

    let filteredRules = filterRulesByCartTotal(storedRules, cartTotal);
    if (needsRealCart) {
      filteredRules = filterRulesByCartItemCount(filteredRules, getCartItemCount(cart));
    }
    const cartProductIds = getCartProductIds(cart.items || []);
    filteredRules = filterRulesByCartProducts(filteredRules, cartProductIds);

    // Filter by variants (works alongside product filter with AND logic)
    const cartVariantIds = getCartVariantIds(cart.items || []);
    filteredRules = filterRulesByCartVariants(filteredRules, cartVariantIds);

    if (rulesNeedCollections(filteredRules)) {
      const settings = getSessionValue("settingSession");
      const productCollectionsMap = await getCartProductCollectionsMap(cartProductIds, settings);
      filteredRules = filterRulesByCartCollections(filteredRules, productCollectionsMap);
    }
    
    const customerZipcode = getCustomerZipcode();
    if (customerZipcode) {
      filteredRules = filterRulesByZipcode(filteredRules, customerZipcode);
      filteredRules = filterRulesByZipcodeWhitelist(filteredRules, customerZipcode);
    }
    filteredRules = filterRulesByBlocklist(filteredRules, getCustomerIdentity());
    filteredRules = await applyExistingCustomerRules(filteredRules, cartTotal);

    // RTO gate runs last, so scoring is only ever requested for rules that
    // already survived every cheap local filter. Phone comes from the OTP the
    // shopper just verified, which is what makes the customer-history signal
    // trustworthy here rather than earlier in the flow.
    filteredRules = await filterRulesByRtoEngine(filteredRules, {
      // Same source the login footer uses: otpData.phoneNumber is only filled
      // during a fresh OTP flow, so a returning ("Not you?") shopper would
      // otherwise reach the gate with no identity to score.
      phone:
        getSessionValue("verifiedNumberData")?.otpVerifiedPhoneNumber ||
        get(otpStore)?.otpData?.phoneNumber ||
        "",
      zip: customerZipcode || "",
      country: getCustomerCountry() || "",
      cartTotal,
    });

    // Hide partial-payment options when the cart has too many unique lines;
    // keep COD and full-payment options available.
    const uniqueLineCount = Array.isArray(cart.items) ? cart.items.length : 0;
    if (uniqueLineCount >= MAX_UNIQUE_LINES_FOR_PARTIAL) {
      filteredRules = filteredRules.filter(
        (rule) => isCodPayment(rule) || isFullPercentagePayment(rule)
      );
    }

    if (filteredRules.length > 0) {
      setSessionValue("partial_payment_no_eligible_rules", false);
      setRuleSets(filteredRules);
      const firstRule = filteredRules[0];
      setSelectedRule(firstRule.id);

      const isFullPercentage = isFullPercentagePayment(firstRule);
      const isCOD = isCodPayment(firstRule);

      setIsFullPercentage(isFullPercentage);
      setIsCOD(isCOD);
    } else {
      setRuleSets([]);
      if (storedRules.length > 0) {
        setSessionValue("partial_payment_no_eligible_rules", true);
      } else {
        setSessionValue("partial_payment_no_eligible_rules", false);
      }
    }
  } catch (_) {
    setSessionValue("partial_payment_no_eligible_rules", false);
    setRuleSets([]);
  } finally {
    setIsLoaderLoading(false);
  }
};

export const handleRuleSelection = (
  id,
  ruleSets,
  setSelectedRule,
  setError,
  setIsCOD,
  setIsFullPercentage,
) => {
  try {
    if (!id) {
      throw new Error("Rule ID is required");
    }

    if (!Array.isArray(ruleSets)) {
      throw new Error("Rule sets must be an array");
    }

    const selectedRule = ruleSets.find((rule) => rule.id === id);

    if (!selectedRule) {
      throw new Error(`Rule with ID ${id} not found`);
    }

    validateRule(selectedRule);

    setSelectedRule(id);
    setError("");

    const isCOD = isCodPayment(selectedRule);
    const isFullPercentage = isFullPercentagePayment(selectedRule);

    setIsCOD(isCOD);
    setIsFullPercentage(isFullPercentage);
  } catch (error) {

    setError(error.message || "Error selecting payment option");
  }
};

export const calculateRulePrice = (
  rule,
  cartTotal,
  orderSummary,
  currencyCode = DEFAULT_VALUES.CURRENCY_CODE,
  shipping = 0,
) => {
  try {
    validateRule(rule);

    const shippingAmount = Math.max(0, safeParseFloat(shipping));
    const safeCartTotal = safeParseFloat(cartTotal);
    const ruleAmount = safeParseFloat(rule.amount);
    const discountValue = safeParseFloat(rule.discount_value);
    const amountToShow = safeTrim(rule.amount_to_show);

    const hasRuleDiscount = Boolean(rule.discount_code && discountValue > 0);
    const isPercentageDiscount =
      rule.discount_type === DISCOUNT_TYPES.PERCENTAGE;

    if (amountToShow && !isNaN(parseFloat(amountToShow))) {
      return formatCurrency(parseFloat(amountToShow), currencyCode);
    }

    let discountAmount = 0;

    if (hasRuleDiscount) {
      discountAmount = isPercentageDiscount
        ? (safeCartTotal * discountValue) / 100
        : discountValue;
    } else if (
      orderSummary?.discountDetails?.code &&
      safeParseFloat(orderSummary.discountDetails.value) > 0
    ) {
      const summaryDiscountValue = safeParseFloat(
        orderSummary.discountDetails.value,
      );
      const summaryDiscountType = orderSummary.discountDetails.type;

      discountAmount =
        summaryDiscountType === DISCOUNT_TYPES.PERCENTAGE
          ? (safeCartTotal * summaryDiscountValue) / 100
          : summaryDiscountValue;
    }

    const cart = getSessionValue("shopify_cart") || getSessionValue("cart");
    const totalAfterDiscount =
      cart && cart.total_price
        ? (cart.total_price || 0) / 100
        : Math.max(0, safeCartTotal - discountAmount);

    let finalPrice = 0;

    switch (rule.amount_type) {
      case PAYMENT_TYPES.COD:
        finalPrice = totalAfterDiscount + ruleAmount + shippingAmount;
        break;

      case PAYMENT_TYPES.FIXED:
        finalPrice = ruleAmount;
        break;

      case PAYMENT_TYPES.PERCENTAGE:
        if (rule.amount === AMOUNT_CONSTANTS.FULL_PAYMENT_PERCENTAGE) {
          if (hasRuleDiscount) {
            const ruleDiscountAmount = isPercentageDiscount
              ? (safeCartTotal * discountValue) / 100
              : discountValue;
            finalPrice = Math.max(0, safeCartTotal - ruleDiscountAmount);
          } else {
            finalPrice = totalAfterDiscount;
          }
          finalPrice += shippingAmount;
        } else {
          finalPrice = (totalAfterDiscount * ruleAmount) / 100;
        }
        break;

      default:

        finalPrice = 0;
    }

    const result = Math.max(0, finalPrice);

    return formatCurrency(result, currencyCode);
  } catch (error) {

    return formatCurrency(0, currencyCode);
  }
};

export const generateRuleDescription = (
  rule,
  cartTotal,
  orderSummary,
  currencyCode,
  getPrice = undefined,
  shipping = 0,
) => {
  try {
    validateRule(rule);

    const shippingAmount = Math.max(0, safeParseFloat(shipping));
    const safeCartTotal = safeParseFloat(cartTotal);
    const ruleAmount = safeParseFloat(rule.amount);
    const discountValue = safeParseFloat(rule.discount_value);
    const amountToShow = safeTrim(rule.amount_to_show);
    const subHeading = safeTrim(rule.sub_heading ?? rule.subHeading);

    const isCodRule = rule.amount_type === PAYMENT_TYPES.COD;
    const hasRuleDiscount = Boolean(rule.discount_code && discountValue > 0);
    const isPercentageDiscount =
      rule.discount_type === DISCOUNT_TYPES.PERCENTAGE;

    const hasOrderSummaryDiscount = Boolean(
      orderSummary?.discountDetails?.code &&
      safeParseFloat(orderSummary.discountDetails.value) > 0,
    );

    if (subHeading) return subHeading;
    const cart = getSessionValue("shopify_cart") || getSessionValue("cart");
    const totalOrderValue = safeCartTotal;
    let totalOrderValueAfterDiscount =
      cart?.total_price ? (cart.total_price || 0) / 100 : safeCartTotal;
    let discountAmount = 0;
    let discountCode = "";
    let discountType = "";
    if (hasRuleDiscount) {
      discountAmount = isPercentageDiscount
        ? (safeCartTotal * discountValue) / 100
        : discountValue;
      discountCode = rule.discount_code;
      discountType = rule.discount_type;
    } else if (hasOrderSummaryDiscount) {
      const summaryDiscountValue = safeParseFloat(
        orderSummary.discountDetails.value,
      );
      const summaryDiscountType = orderSummary.discountDetails.type;

      discountAmount =
        summaryDiscountType === DISCOUNT_TYPES.PERCENTAGE
          ? (safeCartTotal * summaryDiscountValue) / 100
          : summaryDiscountValue;
      discountCode = orderSummary.discountDetails.code;
      discountType = summaryDiscountType;
    }
    let toBePaidNow = 0;
    let toBePaidOnDelivery = 0;
    let codFee = 0;
    if (amountToShow && !isNaN(parseFloat(amountToShow))) {
      toBePaidNow = parseFloat(amountToShow);
      toBePaidOnDelivery =
        Math.max(0, totalOrderValueAfterDiscount - toBePaidNow) +
        shippingAmount;
    }
    if (isFullPercentagePayment(rule)) {
      if (hasRuleDiscount) {
        const ruleDiscountAmount = isPercentageDiscount
          ? (safeCartTotal * discountValue) / 100
          : discountValue;
        toBePaidNow = Math.max(0, safeCartTotal - ruleDiscountAmount);
      } else {
        toBePaidNow = totalOrderValueAfterDiscount;
      }
      toBePaidNow += shippingAmount;
      toBePaidOnDelivery = 0;
    } else if (isCodRule) {
      codFee = ruleAmount;
      toBePaidNow = 0;
      toBePaidOnDelivery =
        totalOrderValueAfterDiscount + codFee + shippingAmount;
    } else if (rule.amount_type === PAYMENT_TYPES.FIXED) {
      toBePaidNow = ruleAmount;

      toBePaidNow = Math.min(toBePaidNow, totalOrderValueAfterDiscount);
      toBePaidOnDelivery =
        Math.max(0, totalOrderValueAfterDiscount - toBePaidNow) +
        shippingAmount;
    } else if (rule.amount_type === PAYMENT_TYPES.PERCENTAGE) {
      toBePaidNow = (totalOrderValueAfterDiscount * ruleAmount) / 100;
      toBePaidOnDelivery =
        Math.max(0, totalOrderValueAfterDiscount - toBePaidNow) +
        shippingAmount;
    }
    const lines = [];
    const orderTotalStr = formatCurrency(totalOrderValue, currencyCode);
    const afterDiscountStr = formatCurrency(
      totalOrderValueAfterDiscount,
      currencyCode,
    );

    lines.push(`Order total: ${orderTotalStr}`);

    if (discountAmount > 0 && discountCode) {
      lines.push(`After ${discountCode} discount: ${afterDiscountStr}`);
    } else if (discountAmount > 0) {
      lines.push(`After discount: ${afterDiscountStr}`);
    }

    if (isFullPercentagePayment(rule)) {
      lines.push(`Pay now: ${formatCurrency(toBePaidNow, currencyCode)}`);
      return lines.join(". ");
    }

    if (isCodRule) {
      lines.push(
        `Pay on delivery: ${formatCurrency(toBePaidOnDelivery, currencyCode)}`,
      );
      const extras = [];
      if (codFee > 0) {
        extras.push(`COD fee: ${formatCurrency(codFee, currencyCode)}`);
      }
      if (shippingAmount > 0) {
        extras.push(`shipping: ${formatCurrency(shippingAmount, currencyCode)}`);
      }
      lines.push(
        extras.length ? `Includes ${extras.join(" and ")}` : "No extra charges",
      );
      return lines.join(". ");
    }

    lines.push(`Pay now: ${formatCurrency(toBePaidNow, currencyCode)}`);
    lines.push(
      `Pay on delivery: ${formatCurrency(toBePaidOnDelivery, currencyCode)}`,
    );

    return lines.join(". ");
  } catch (_) {
    return "Payment option available.";
  }
};

export const handleSimpleFlow = async (
  cart,
  selectedRuleObj,
  isFullPercentage,
  isCOD,
  setIsPartialPaymentCartReadyAndUpdated,
) => {
  try {
    const settings = getSessionValue("settingSession");
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;
    const ruleDiscountCode = selectedRuleObj?.discount_code?.trim();
    const ruleDiscountValueStr = selectedRuleObj?.discount_value || "0";
    const ruleDiscountType = selectedRuleObj?.discount_type || "fixed";
    const ruleDiscountValueNum = parseFloat(ruleDiscountValueStr || 0);

    const currentCartState = get(otpStore)?.currentCartData;
    const currentCartTotalDecimal = (currentCartState?.total_price || 0) / 100;
    const existingCartDiscountValueDecimal =
      ((currentCartState?.total_discount || 0) - giftDiscountCents(currentCartState?.items)) / 100;
    const originalCartTotalDecimal =
      currentCartTotalDecimal + existingCartDiscountValueDecimal;
    let ruleDiscountValue = 0;
    if (ruleDiscountValueNum > 0) {
      if (ruleDiscountType === "percentage") {
        ruleDiscountValue =
          (originalCartTotalDecimal * ruleDiscountValueNum) / 100;
      } else {
        ruleDiscountValue = ruleDiscountValueNum;
      }
    }
    const shouldApplyRuleDiscount =
      ruleDiscountCode &&
      ruleDiscountCode !== "" &&
      (ruleDiscountValue > existingCartDiscountValueDecimal ||
        existingCartDiscountValueDecimal === 0);

    if (shouldApplyRuleDiscount) {
      try { await removeDiscountCodeFromOtpStore(); } catch (_) {}
      await applyDiscountCodeToOtpStore(ruleDiscountCode);
    } else if (ruleDiscountCode && ruleDiscountCode !== "") {
    } else {
      await removeDiscountCodeFromOtpStore();
    }

    const sessionId = getMachineId();
    if (!sessionId) {
      throw new Error("Unable to get machine ID");
    }

    let attributes = {
      _codkSessionId: sessionId,
      // COD-only checkout restriction signal for the payment/delivery functions
      // (empty unless a COD rule opted in); always written to clear stale values.
      _codkCheckoutMode:
        isCOD &&
        (selectedRuleObj?.checkout_cod_only === true ||
          selectedRuleObj?.checkout_cod_only === "true")
          ? "cod_only"
          : "",
      _codkPrepaidDiscount: "",
    };

    if (partialPaymentFlowVersion === 2) {
      const amountType =
        selectedRuleObj?.amount_type != null
          ? selectedRuleObj.amount_type
          : "0";
      const amountValue =
        selectedRuleObj?.amount != null ? selectedRuleObj.amount : "0";
      attributes._codkAmountType = amountType;
      attributes._codkAmountValue = amountValue;
      // Expand flag on => tell the Cart Transform function to use lineExpand
      // (real product at deposit price) instead of the dummy-parent merge.
      if (
        settings?.partialExpandFlowEnabled === true &&
        !isCOD &&
        !isFullPercentage
      ) {
        attributes._codkBundleMode = "expand";
      }
    }

    const effectiveCart = currentCartState || cart || {};
    try {
      const baseCartTotalDecimal =
        typeof effectiveCart?.original_total_price === "number"
          ? effectiveCart.original_total_price / 100
          : ((effectiveCart?.total_price || 0) +
              (effectiveCart?.total_discount || 0)) /
            100;

      const lineLevelDiscountDecimal = (effectiveCart?.items || []).reduce(
        (sum, item) => {
          const hasLineLevelDiscounts =
            item?.line_level_discount_allocations &&
            item.line_level_discount_allocations.length > 0;
          if (!hasLineLevelDiscounts) return sum;
          const cents =
            item?.line_level_total_discount ||
            (item?.line_level_discount_allocations || []).reduce(
              (s, alloc) => s + (alloc?.amount || 0),
              0,
            );
          return sum + cents / 100;
        },
        0,
      );

      const ruleDiscountValueNum = parseFloat(
        String(selectedRuleObj?.discount_value ?? "0"),
      );
      const ruleDiscountType = selectedRuleObj?.discount_type || "";
      const ruleDiscountCode = (selectedRuleObj?.discount_code || "").trim();

      let ruleOrderLevelDiscountAmount = 0;
      if (ruleDiscountCode && ruleDiscountValueNum > 0) {
        ruleOrderLevelDiscountAmount =
          ruleDiscountType === "percentage"
            ? (Math.max(0, baseCartTotalDecimal - lineLevelDiscountDecimal) *
                ruleDiscountValueNum) /
              100
            : ruleDiscountValueNum;
      }

      const ruleOrderLevelDiscount =
        ruleOrderLevelDiscountAmount > 0 && ruleDiscountCode
          ? { amount: ruleOrderLevelDiscountAmount, code: ruleDiscountCode }
          : null;
      attributes._codkPrepaidDiscount = prepaidDiscountAttribute(isFullPercentage, ruleOrderLevelDiscount);
      const codkDiscounts = getCodkDiscounts(
        effectiveCart?.items || [],
        effectiveCart?.cart_level_discount_applications || [],
        { ruleOrderLevelDiscount, skipFreeItems: isFullPercentage || isCOD },
      );
      if (codkDiscounts) {
        attributes._codkDiscounts = codkDiscounts;
      }

      const codkImageURLs = getCodkImageURLs(effectiveCart?.items || []);
      if (codkImageURLs?.trim()) attributes._codkImageURLs = codkImageURLs;
    } catch (_) {}

    if (isFullPercentage) {
      attributes.partial_payment_variants = null;
      attributes._partialPaymentProduct = true;
    } else if (isCOD) {
      attributes.partial_payment_variants = null;
      attributes._partialPaymentProduct = null;
    }
    await executePost({ attributes });
    addCartAttributesWithOtpStore(attributes);

    if (isFullPercentage) {
      await removeAllLineItemsDescription();
    } else if (isCOD && partialPaymentFlowVersion === 2) {
      // Calculate tax info for tax-aware description
      const cart = get(otpStore)?.currentCartData || getSessionValue("shopify_cart");
      const taxInfo = calculateTaxForRule(selectedRuleObj, cart);
      const ruleDescription =
        getDescBundle(selectedRuleObj, cart, taxInfo) || "Payment option selected";
      await updateAllLineItemsDescription(ruleDescription);
    }

    setIsPartialPaymentCartReadyAndUpdated(true);
  } catch (error) {
    throw new Error(`Simple flow failed: ${error.message}`);
  }
};

export const handlePartialPaymentFlow = async (
  cart,
  selectedRuleObj,
  shop,
  selectedRule,
  currencyCode,
  setIsPartialPaymentCartReadyAndUpdated,
  cartTotal,
  orderSummary,
) => {
  try {
    if (!shop) {
      throw new Error("Shop parameter is required");
    }

    if (!selectedRule) {
      throw new Error("Selected rule is required");
    }

    const currentCart = get(otpStore)?.currentCartData;

    if (!currentCart || !currentCart.items) {
      throw new Error("Cart data is missing");
    }

    const originalCartItemsMap = new Map();
    currentCart.items.forEach((item) => {
      const variantId = item.variant_id || item.id;
      if (variantId) originalCartItemsMap.set(variantId.toString(), item.properties || {});
    });
    const items = formatCartItemsForPartial(currentCart.items);
    if (items.length === 0) {
      throw new Error("No valid items found for partial payment");
    }

    const response = await createPartialCart(shop, selectedRule, items);
    const data = response?.data?.cartItems || response?.data;

    if (!data || !Array.isArray(data)) {
      throw new Error("Invalid response from partial cart creation");
    }

    setLocalValue("partialCartData", data);

    const ruleDescription = generateRuleDescription(
      selectedRuleObj,
      cartTotal,
      orderSummary,
      currencyCode,
    );

    const cartItems = transformToCartLineItems(
      data,
      currencyCode,
      ruleDescription,
    );

    if (cartItems.length === 0) {
      throw new Error("Failed to transform cart items");
    }

    const cartItemsWithTransferredProperties = cartItems.map((cartItem) => {
      const partialDataItem = data.find((d) => d.variantId === cartItem.id);
      if (partialDataItem?.originalVariantId) {
        const originalProperties = originalCartItemsMap.get(
          String(partialDataItem.originalVariantId),
        );
        if (originalProperties && Object.keys(originalProperties).length > 0) {
          return {
            ...cartItem,
            properties: { ...(cartItem.properties || {}), ...originalProperties },
          };
        }
      }
      return cartItem;
    });
    if (otpStoreActions.patchCurrentCartData) {
      const patchedItems = cartItemsWithTransferredProperties.map((item) => {
        const partialInfo = data.find((d) => d.variantId === item.id);
        return {
          variant_id: item.id,
          id: item.id,
          quantity: item.quantity,
          title: partialInfo?.title || "Partial Payment Item",
          presentment_price: partialInfo?.cost || 0,
          price: (partialInfo?.cost || 0) * 100, // Shopify uses cents usually, but otpStore might use decimals
          properties: item.properties,
          image: partialInfo?.imageUrl || "",
        };
      });

      otpStoreActions.patchCurrentCartData({
        items: patchedItems,
        total_price: patchedItems.reduce(
          (sum, item) => sum + item.presentment_price * item.quantity,
          0,
        ),
      });
    }
    if (selectedRuleObj?.discount_code) {
      await applyDiscountCodeToOtpStore(selectedRuleObj.discount_code);
    } else {
      await removeDiscountCodeFromOtpStore();
    }
    const partialPaymentVariantIds = data
      .map((item) => item?.variantId)
      .filter((id) => id != null)
      .map((id) => Number(id))
      .filter((n) => !isNaN(n));
    const sessionId = getMachineId();
    if (!sessionId) {
      throw new Error("Unable to get machine ID");
    }

    const attributes = {
      _codkSessionId: sessionId,
      partial_payment_variants: JSON.stringify(partialPaymentVariantIds),
      _partialPaymentProduct: true,
    };
    addCartAttributesWithOtpStore(attributes);

    setIsPartialPaymentCartReadyAndUpdated(true);
  } catch (error) {
    throw new Error(`Partial payment flow failed: ${error.message}`);
  }
};

export const formatCartItemsForPartial = (items) => {
  if (!Array.isArray(items)) return [];
  return items
    .filter((item) => item && item.variant_id) // Filter out invalid items
    .map((item) => ({
      cost: safeParseFloat(item.presentment_price),
      totalQuantity: Math.max(1, safeParseFloat(item.quantity)), // Ensure minimum quantity of 1
      title: item.title || "Unknown Product",
      imageUrl: item.image || "",
      variantId: item.variant_id.toString(),
    }));
};

export const transformToCartLineItems = (
  items,
  currencyCode,
  ruleDescription = "",
) => {
  if (!Array.isArray(items)) return [];
  return items
    .filter((item) => item && item.variantId) // Filter out invalid items
    .map((item) => {
      const quantity = Math.max(1, safeParseFloat(item.totalQuantity));

      return {
        id: item.variantId,
        quantity: quantity,
        properties: {
          description: ruleDescription || "Partial payment option selected",
        },
      };
    });
};

export const hasRuleDiscount = (rule) => {
  if (!rule) return false;
  return Boolean(rule.discount_code && safeParseFloat(rule.discount_value) > 0);
};

export const hasOrderSummaryDiscount = (orderSummary) => {
  if (!orderSummary?.discountDetails) return false;
  return Boolean(
    orderSummary.discountDetails.code &&
    safeParseFloat(orderSummary.discountDetails.value) > 0,
  );
};

export const handlePaymentSubmit = async (
  isFullPercentage,
  isCOD,
  selectedRule,
  ruleSets,
  setIsPartialLoading,
  setError,
  setIsPartialPaymentCartReadyAndUpdated,
  handleSkip,
  setStep,
  cartTotal,
  orderSummary,
) => {
  const otpState = get(otpStore);
  setError("");
  setIsPartialLoading(true);

  try {
    if (!selectedRule) {
      throw new Error("Please select a payment option");
    }

    if (!Array.isArray(ruleSets) || ruleSets.length === 0) {
      throw new Error("No payment options available");
    }

    const selectedRuleObj = ruleSets.find((rule) => rule.id === selectedRule);
    if (!selectedRuleObj) {
      throw new Error("Selected payment option is no longer available");
    }

    const shop =
      (typeof window !== "undefined" &&
        window.parent &&
        window.parent !== window &&
        window.parent.Shopify?.shop) ||
      (typeof window !== "undefined" && window.Shopify?.shop) ||
      null;
    if (!shop) {
      throw new Error("Shop information not available");
    }

    const cart = get(otpStore)?.currentCartData;

    if (!cart || !cart.items || cart.items.length === 0) {
      throw new Error("Your cart is empty");
    }

    const currencyCode =
      (typeof window !== "undefined" &&
        window.Shopify &&
        typeof window.Shopify.currency === "object" &&
        /** @type {{ active?: string }} */ (window.Shopify.currency)?.active) ||
      DEFAULT_VALUES.CURRENCY_CODE;
    const isSimpleFlow = isFullPercentage || isCOD;

    if (isSimpleFlow) {
      await handleSimpleFlow(
        cart,
        selectedRuleObj,
        isFullPercentage,
        isCOD,
        setIsPartialPaymentCartReadyAndUpdated,
      );
      otpStoreActions.setIsCartManipulationProcessCompleted(true);
      const nextStep = await getCurrentStep();
      setStep(nextStep);
    } else {
      await handlePartialPaymentFlow(
        cart,
        selectedRuleObj,
        shop,
        selectedRule,
        currencyCode,
        setIsPartialPaymentCartReadyAndUpdated,
        cartTotal,
        orderSummary,
      );

      const nextStep = await getCurrentStep();
      setStep(nextStep);
    }
  } catch (error) {
    const errorMessage =
      error.message || "An unexpected error occurred. Please try again.";
    setError(errorMessage);
  } finally {
    setTimeout(() => {
      setIsPartialLoading(false);
    }, 100);
  }
};

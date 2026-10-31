import {
  createCodOrder,
  createRazorpayOrder,
  verifyRazorpayPayment,
  getRouteUrl,
} from "./api.js";
import { clearCart } from "./cartService.js";
import { UPSELL_PROPERTY } from "./upsellService.js";
import { FREE_GIFT_PROPERTY } from "./freeGiftService.js";
import { executePost } from "./otpService.js";
import {
  getSessionValue,
  getNoEmailPlaceholder,
} from "../utilities/otpUtils.js";
import { getShopDomain, getMachineId } from "../utils/helpers.js";
import { getCampaignAttributionPayload, isMetaConversionEnabled } from "../utils/campaignAttribution.js";

import { postToParent } from "../utils/parentMessaging";
function readCookieFromDoc(doc, name) {
  try {
    const all = doc && typeof doc.cookie === "string" ? doc.cookie : "";
    if (!all) return "";
    const parts = all.split("; ");
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (!p) continue;
      const eq = p.indexOf("=");
      if (eq <= 0) continue;
      const k = p.slice(0, eq);
      if (k === name) return decodeURIComponent(p.slice(eq + 1));
    }
    return "";
  } catch (_e) {
    return "";
  }
}

function readCookie(name) {
  try {
    if (typeof document !== "undefined") {
      const v = readCookieFromDoc(document, name);
      if (v) return v;
    }
  } catch (_e) {}
  try {
    if (typeof window !== "undefined" && window.parent?.document) {
      return readCookieFromDoc(window.parent.document, name);
    }
  } catch (_e) {}
  return "";
}

function readLocalStorage(key) {
  try {
    if (typeof window !== "undefined" && window.parent?.localStorage) {
      const v = window.parent.localStorage.getItem(key);
      if (v && String(v).trim()) return String(v).trim();
    }
  } catch (_e) {}
  try {
    if (typeof localStorage !== "undefined") {
      const v = localStorage.getItem(key);
      if (v && String(v).trim()) return String(v).trim();
    }
  } catch (_e) {}
  return "";
}

function requestMetaAttributionFromParent() {
  try {
    if (typeof window !== "undefined" && window.parent && window.parent !== window) {
      postToParent({ type: "CODK_REQUEST_META_ATTRIBUTION" });
    }
  } catch (_e) {}
}

function getInjectedMetaClickData() {
  try {
    const w = typeof window !== "undefined" ? window : null;
    const inj = w && /** @type {any} */ (w).__codk_meta_click_data;
    if (!inj || typeof inj !== "object") return null;
    return inj;
  } catch (_e) {
    return null;
  }
}

/** Page URL for Meta CAPI `event_source_url` — prefer top window when same-origin, else self or referrer. */
function resolveEventSourceUrl() {
  try {
    if (typeof window === "undefined" || !window.location) return "";
    if (window.parent && window.parent !== window) {
      try {
        const h = String(window.parent.location.href);
        if (h && /^https?:/i.test(h)) return h;
      } catch (_crossOrigin) {
        // Cross-origin iframe: cannot read parent location
      }
    }
    const selfHref = String(window.location.href);
    if (selfHref && /^https?:/i.test(selfHref)) return selfHref;
  } catch (_e) {}
  try {
    if (typeof document !== "undefined" && document.referrer) {
      const r = String(document.referrer).trim();
      if (r && /^https?:/i.test(r)) return r;
    }
  } catch (_e2) {}
  return "";
}

/** Wait briefly for parent (storefront) to reply with fbp/fbc via postMessage — needed when iframe is cross-origin. */
async function waitForMetaClickDataFromParent(maxWaitMs = 400) {
  requestMetaAttributionFromParent();
  const start = typeof performance !== "undefined" ? performance.now() : Date.now();
  const budget = () =>
    (typeof performance !== "undefined" ? performance.now() : Date.now()) - start;
  while (budget() < maxWaitMs) {
    const d = getMetaClickData();
    if (d.fbp || d.fbc) return;
    await new Promise((r) => setTimeout(r, 40));
  }
}

function getMetaClickData() {
  const inj = getInjectedMetaClickData();
  const pick = (k) => {
    const v = inj && inj[k] != null ? String(inj[k]).trim() : "";
    return v || null;
  };

  /** Same-session ad params (utm, fbclid, …); meta_click_data.fbclid used to miss URL-only fbclid. */
  const campaign = getCampaignAttributionPayload();
  const campaignFbclid =
    campaign && campaign.fbclid != null && String(campaign.fbclid).trim()
      ? String(campaign.fbclid).trim()
      : "";

  const fbp =
    pick("fbp") ||
    readCookie("_fbp") ||
    readLocalStorage("codk_meta_fbp") ||
    "";
  const fbc =
    pick("fbc") ||
    readCookie("_fbc") ||
    readLocalStorage("codk_meta_fbc") ||
    "";
  const fbclid =
    pick("fbclid") ||
    readLocalStorage("codk_meta_fbclid") ||
    campaignFbclid ||
    "";
  const eventSourceUrl =
    pick("event_source_url") ||
    readLocalStorage("codk_meta_event_source_url") ||
    resolveEventSourceUrl() ||
    "";

  const uaFromInj = pick("client_user_agent");
  const ua =
    uaFromInj ||
    (typeof navigator !== "undefined" && navigator.userAgent
      ? String(navigator.userAgent)
      : "");

  return {
    fbp: fbp || null,
    fbc: fbc || null,
    fbclid: fbclid || null,
    event_source_url: eventSourceUrl || null,
    client_user_agent: ua || null,
  };
}

export function resolveShippingAddress(otpState, cartData) {
  try {
    if (typeof window.parent !== "undefined" && window.parent.sessionStorage) {
      const storedAddressStr = window.parent.sessionStorage.getItem(
        "cod_king_selected_address",
      );
      if (storedAddressStr) return JSON.parse(storedAddressStr);
    }
  } catch (_e) {}
  const selectedAddressId = otpState?.selectedAddress;
  const addresses = otpState?.shippingAddresses || [];
  if (selectedAddressId !== undefined && addresses.length > 0) {
    const found =
      addresses[selectedAddressId] ||
      addresses.find((addr) => addr.id === selectedAddressId) ||
      addresses[0];
    if (found) return found;
  }
  const cartAttributes = cartData?.attributes || {};
  const selectedAddressStr = cartAttributes._selectedAddress;
  if (selectedAddressStr) {
    try {
      const parsed = JSON.parse(selectedAddressStr);
      return {
        first_name: parsed.firstName || parsed.first_name || "",
        last_name: parsed.lastName || parsed.last_name || "",
        address1: parsed.address1 || "",
        address2: parsed.address2 || "",
        city: parsed.city || "",
        province: parsed.province || parsed.state || "",
        zip: parsed.zip || parsed.postal_code || "",
        country: parsed.country || "India",
      };
    } catch (_e) {}
  }

  return null;
}

export function normalizeShippingAddress(addr) {
  return {
    first_name: addr.first_name || addr.firstName || "",
    last_name: addr.last_name || addr.lastName || "",
    address1: addr.address1 || addr.address_1 || "",
    address2: addr.address2 || addr.address_2 || "",
    city: addr.city || "",
    province: addr.province || addr.state || addr.province_code || "",
    zip: addr.zip || addr.postal_code || addr.postalCode || "",
    country: addr.country || addr.country_code || "India",
  };
}

export function prepareCartItems(items) {
  return items.map((item) => ({
    variant_id: item.variant_id || item.id,
    quantity: item.quantity || 1,
    line_level_discount_allocations: item.line_level_discount_allocations || [],
    ...(item.properties?.[UPSELL_PROPERTY] === "true"
      ? { properties: { [UPSELL_PROPERTY]: "true" } }
      : {}),
    ...(item.properties?.[FREE_GIFT_PROPERTY]
      ? { properties: { [FREE_GIFT_PROPERTY]: String(item.properties[FREE_GIFT_PROPERTY]) } }
      : {}),
  }));
}

/**
 * Get customer email from all available sources (session, localStorage, store).
 * Used so buyer identity always has email when user has provided it.
 */
function getCustomerEmailFromStorage() {
  const fromSession =
    getSessionValue("customer-email") ||
    getSessionValue("cod_king_customer_email");
  if (fromSession && String(fromSession).trim())
    return String(fromSession).trim();
  try {
    if (typeof window !== "undefined" && window.parent?.sessionStorage) {
      const parent =
        window.parent.sessionStorage.getItem("customer-email") ||
        window.parent.sessionStorage.getItem("cod_king_customer_email");
      if (parent && String(parent).trim()) return String(parent).trim();
    }
    if (typeof window !== "undefined" && window.sessionStorage) {
      const self =
        window.sessionStorage.getItem("customer-email") ||
        window.sessionStorage.getItem("cod_king_customer_email");
      if (self && String(self).trim()) return String(self).trim();
    }
    if (typeof localStorage !== "undefined") {
      const local =
        localStorage.getItem("customer-email") ||
        localStorage.getItem("cod_king_customer_email");
      if (local && String(local).trim()) return String(local).trim();
    }
  } catch (_e) {}
  return "";
}

export function getBuyerIdentity(otpState) {
  const verifiedData = getSessionValue("verifiedNumberData") || {};
  const emailFromStorage = getCustomerEmailFromStorage();
  const phone =
    verifiedData.otpVerifiedPhoneNumber || otpState?.otpData?.phoneNumber || "";
  let email =
    (verifiedData.email && String(verifiedData.email).trim()) ||
    (otpState?.verifiedEmail && String(otpState.verifiedEmail).trim()) ||
    (otpState?.buyerIdentity?.email &&
      String(otpState.buyerIdentity.email).trim()) ||
    emailFromStorage ||
    "";
  email = email.trim();
  if (!email && phone) {
    email = getNoEmailPlaceholder(phone) || "";
  }
  return {
    phone,
    email,
  };
}

export function getShippingRateDetails(
  selectedShippingRate,
  manualShippingCharge = 0,
) {
  const manual = parseFloat(manualShippingCharge);
  const override = !isNaN(manual) && manual > 0 ? manual : null;

  // A per-rule manual charge is authoritative — it is what the popup showed, so
  // it has to be what the order's shipping line says. With no Shopify rate to
  // borrow a handle from (redirect-only stores), synthesise one.
  if (!selectedShippingRate) {
    return override === null
      ? null
      : { handle: "codk-manual-shipping", title: "Shipping", price: override };
  }
  return {
    handle: selectedShippingRate.handle,
    title: selectedShippingRate.title,
    price: override !== null ? override : selectedShippingRate.price || 0,
  };
}

/**
 * Normalize a numeric value to rupees.
 * Values > 10000 are assumed to be in paise.
 * @param {number|string} v - The value to normalize
 * @returns {number}
 */
export function toRupees(v) {
  const n = typeof v === "number" ? v : parseFloat(v) || 0;
  return n > 10000 ? n / 100 : n;
}

export function convertIfCents(value) {
  if (value >= 10 && value < 1000000) {
    const converted = value / 100;
    if (converted < 10000 && converted >= 0.01 && converted < 100) {
      return Math.round(converted * 100) / 100;
    }
  }
  return value;
}

function validateCartData(cartData) {
  if (!cartData || !cartData.items || cartData.items.length === 0) {
    throw new Error("Cart is empty");
  }
}

function getValidatedShippingAddress(otpState, cartData) {
  const shippingAddress = resolveShippingAddress(otpState, cartData);
  if (!shippingAddress || !shippingAddress.address1) {
    throw new Error(
      "Shipping address is required. Please select an address first.",
    );
  }
  const normalized = normalizeShippingAddress(shippingAddress);
  if (!normalized.address1 || !normalized.city) {
    throw new Error(
      "Shipping address is incomplete. Please ensure address and city are provided.",
    );
  }
  return normalized;
}

/**
 * Maps browser Meta attribution to Shopify cart note attribute keys.
 * Server reads these on the order (note_attributes) for Meta CAPI remaining_balance.
 */
export function getMetaClickCartAttributePayload() {
  if (!isMetaConversionEnabled()) return {};
  const m = getMetaClickData();
  /** @type {Record<string, string>} */
  const o = {};
  if (m.fbp) o._fbp = m.fbp;
  if (m.fbc) o._fbc = m.fbc;
  if (m.fbclid) o._fbclid = m.fbclid;
  if (m.event_source_url) o._eventSourceUrl = m.event_source_url;
  if (m.client_user_agent) o._clientUserAgent = m.client_user_agent;
  return o;
}

/** Wait for postMessage/cookies, then return cart attributes to merge with _codkSessionId, etc. */
export async function buildMetaAttributionAttributesForCart() {
  if (!isMetaConversionEnabled()) return {};
  await waitForMetaClickDataFromParent(1200);
  return getMetaClickCartAttributePayload();
}

export async function completeCodOrder({
  otpState,
  selectedRule,
  ruleSets,
  currencyCode,
  selectedShippingRate,
  manualShippingCharge = 0,
  otpStoreActions,
}) {
  const cartData = otpState?.currentCartData;
  validateCartData(cartData);

  const metaEnabled = isMetaConversionEnabled();
  if (metaEnabled) {
    await waitForMetaClickDataFromParent(1200);
  }

  const normalizedAddress = getValidatedShippingAddress(otpState, cartData);
  const buyerIdentity = getBuyerIdentity(otpState);
  const cartItems = prepareCartItems(cartData.items);
  const shopDomain = getShopDomain();

  // Extract COD fee
  let codFee = null;
  if (selectedRule) {
    const selectedRuleObj = ruleSets.find(
      (r) => String(r.id) === String(selectedRule),
    );
    if (
      selectedRuleObj &&
      selectedRuleObj.amount_type === "cod" &&
      selectedRuleObj.amount > 0
    ) {
      codFee = selectedRuleObj.amount;
    }
  }

  const shippingRateDetails = getShippingRateDetails(
    selectedShippingRate,
    manualShippingCharge,
  );

  const verifiedNumberData = getSessionValue("verifiedNumberData") || {};
  const verificationStatus = !!(verifiedNumberData && verifiedNumberData.isOTPVerified);

  const metaClickData = metaEnabled ? getMetaClickData() : {};
  const clientSessionId = getMachineId() || "";

  const response = await createCodOrder({
    shop_domain: shopDomain,
    cart_data: {
      items: cartItems,
      currency_code: cartData.currency_code || currencyCode,
      cart_level_discount_applications:
        cartData.cart_level_discount_applications || [],
    },
    shipping_address: normalizedAddress,
    buyer_identity: buyerIdentity,
    cod_fee: codFee,
    shipping_rate_details: shippingRateDetails,
    verification_status: verificationStatus,
    client_session_id: clientSessionId,
    meta_click_data: metaClickData,
    campaign_attribution: metaEnabled ? getCampaignAttributionPayload() : {},
  });

  if (response.success && response.order) {
    // Publish to Shopify Web Pixel before clearing cart, so attribution stored
    // in sessionStorage / cart attributes is still readable. The web pixel
    // (cod-king-web-pixel) subscribes to "cod_order_placed" to fire Google Ads
    // and Meta conversions for orders that bypass Shopify checkout.
    // Cross-origin iframe → bridge via parent storefront postMessage.
    try {
      let attribution = {};
      try {
        const raw =
          (typeof window !== "undefined" &&
            window.parent &&
            window.parent !== window &&
            window.parent.sessionStorage?.getItem("codk_campaign_attribution")) ||
          (typeof sessionStorage !== "undefined" &&
            sessionStorage.getItem("codk_campaign_attribution")) ||
          "";
        attribution = raw ? JSON.parse(raw) : {};
      } catch (_attrErr) {}

      const pixelPayload = {
        orderId: response.order.id || response.order.number || null,
        totalPrice:
          response.order.total_price ?? response.order.totalPrice ?? null,
        currencyCode:
          response.order.currency ||
          cartData.currency_code ||
          currencyCode ||
          null,
        email: buyerIdentity?.email || null,
        attribution,
      };
     const shopifyAnalyticsPublish = (window).Shopify?.analytics?.publish || (window)?.parent?.Shopify?.analytics?.publish || (window).parent[0]?.Shopify?.analytics?.publish || (window).parent[1]?.Shopify?.analytics?.publish  || (window).parent[2]?.Shopify?.analytics?.publish 
          typeof window !== "undefined"
            ? /** @type {((name: string, data: unknown) => void) | undefined} */ (
                /** @type {any} */ (window).Shopify?.analytics?.publish
              )
            : undefined;
        if (typeof shopifyAnalyticsPublish === "function") {
          shopifyAnalyticsPublish("cod_order_placed", pixelPayload);
        }
    } catch (_pixelErr) {
      /* never block order completion on pixel firing */
    }

    // Clear cart
    try {
      // await new Promise((res) => {
      //   setTimeout(res,200000)
      // })
      await clearCart();
      // Restore _otpVerifiedPhoneNumber, _codkSessionId and _codkCountryCode on the empty cart (they are removed by clear)
      const verifiedData = getSessionValue("verifiedNumberData") || {};
      const phone = buyerIdentity.phone || "";
      const sessionId = getMachineId() || "";
      const countryCode =
        verifiedData.countryCode || otpState?.countryCode || "";
      if (phone || sessionId || countryCode) {
        try {
          await executePost({
            attributes: {
              ...(phone && { _otpVerifiedPhoneNumber: phone }),
              ...(sessionId && { _codkSessionId: sessionId }),
              ...(countryCode && { _codkCountryCode: countryCode }),
            },
          });
        } catch (_e) {}
      }
      otpStoreActions.setCurrentCartData(null);
    } catch (_clearError) {}

    return {
      success: true,
      message: `Order #${response.order.number} created successfully!`,
      orderNumber: response.order.number ? String(response.order.number) : null,
      orderStatusUrl: response.order.order_status_url || null,
    };
  }

  throw new Error(response.error || "Failed to create order");
}

// ========================================
// RAZORPAY PAYMENT
// ========================================

/**
 * Calculate the payment amount for Razorpay based on the selected rule.
 * @param {Object} selectedRuleObj - The selected rule object
 * @param {Object} orderSummary - Order summary with total, taxAmount, shippingCost
 * @returns {number} Payment amount in rupees
 */
export function calculateRazorpayPaymentAmount(selectedRuleObj, orderSummary) {
  const rawTotal = orderSummary?.total;
  const rawTax = orderSummary?.taxAmount;
  const rawShipping = orderSummary?.shippingCost ?? 0;

  // Normalize to rupees
  const baseTotalRupees = toRupees(rawTotal);
  const taxAmountRupees = toRupees(rawTax);
  const shippingCostRupees = toRupees(rawShipping);

  // Full total for Razorpay
  const fullTotal =
    Math.round((baseTotalRupees + taxAmountRupees + shippingCostRupees) * 100) /
    100;

  // For legacy partial-rule calculation
  let baseTotal = convertIfCents(
    typeof rawTotal === "number" ? rawTotal : parseFloat(rawTotal) || 0,
  );
  let taxAmount = convertIfCents(
    typeof rawTax === "number" ? rawTax : parseFloat(rawTax) || 0,
  );

  let paymentAmount = 0;

  if (selectedRuleObj.amount_type === "percentage") {
    const percentage = parseFloat(selectedRuleObj.amount) || 0;
    paymentAmount =
      percentage === 100 ? baseTotal : (baseTotal * percentage) / 100;
  } else if (selectedRuleObj.amount_type === "fixed") {
    const ruleAmount = parseFloat(selectedRuleObj.amount) || 0;
    if (ruleAmount >= 10 && ruleAmount < 1000000) {
      const converted = ruleAmount / 100;
      const isWholeNumber = ruleAmount % 1 === 0;
      const remainder = (ruleAmount * 100) % 100;
      const hasStandardCents = remainder === 0 || remainder === 50;
      if (
        (isWholeNumber || hasStandardCents) &&
        converted < 10000 &&
        converted >= 0.01
      ) {
        paymentAmount = converted;
      } else {
        paymentAmount = ruleAmount;
      }
    } else {
      paymentAmount = ruleAmount;
    }
  } else {
    paymentAmount = baseTotal;
  }

  // Add proportional tax
  if (taxAmount > 0) {
    const taxProportion =
      selectedRuleObj.amount_type === "percentage" &&
      selectedRuleObj.amount !== "100"
        ? parseFloat(selectedRuleObj.amount) / 100
        : 1;
    paymentAmount += taxAmount * taxProportion;
  }

  // Add shipping
  const shippingCost = orderSummary?.shippingCost || 0;
  if (shippingCost > 0) {
    paymentAmount += shippingCost;
  }

  // Round to 2 decimal places
  paymentAmount = Math.round(paymentAmount * 100) / 100;

  // Final safeguard: convert from paise if clearly in paise
  if (paymentAmount >= 1000 && paymentAmount < 1000000) {
    const converted = paymentAmount / 100;
    if (converted >= 10 && converted < 10000 && paymentAmount % 1 === 0) {
      paymentAmount = Math.round(converted * 100) / 100;
    }
  }

  return { paymentAmount, fullTotalWithTaxAndShipping: fullTotal };
}

/**
 * Initiate Razorpay payment flow.
 * @param {Object} params
 * @returns {Promise<Object>} razorpayEmbedOptions for the RazorpayEmbed component
 */
export async function initiateRazorpayPayment({
  otpState,
  selectedRule,
  ruleSets,
  currencyCode,
  orderSummary,
  selectedShippingRate,
  manualShippingCharge = 0,
}) {
  const cartData = otpState?.currentCartData;
  validateCartData(cartData);

  const selectedRuleObj = ruleSets.find(
    (r) => String(r.id) === String(selectedRule),
  );
  if (!selectedRuleObj) throw new Error("Please select a payment option");
  if (selectedRuleObj.amount_type === "cod") {
    throw new Error("Please use Complete Order button for COD payments");
  }

  const shippingAddress = resolveShippingAddress(otpState, cartData);
  if (!shippingAddress || !shippingAddress.address1) {
    throw new Error(
      "Shipping address is required. Please select an address first.",
    );
  }

  const normalizedAddress = normalizeShippingAddress(shippingAddress);
  const buyerIdentity = getBuyerIdentity(otpState);
  const { fullTotalWithTaxAndShipping } = calculateRazorpayPaymentAmount(
    selectedRuleObj,
    orderSummary,
  );
  const cartItems = prepareCartItems(cartData.items);
  const shopDomain = getShopDomain();
  const routeUrl = getRouteUrl();
  const returnUrl = typeof window !== "undefined" ? window.location.href : "";
  const callbackUrl = routeUrl
    ? `${routeUrl}/api/razorpay_orders/callback?shop=${encodeURIComponent(shopDomain || "")}`
    : "";

  const shippingRateDetails = getShippingRateDetails(
    selectedShippingRate,
    manualShippingCharge,
  );

  const razorpayOrderResponse = await createRazorpayOrder({
    shop_domain: shopDomain,
    cart_data: {
      items: cartItems,
      currency_code: cartData.currency_code || currencyCode,
      cart_level_discount_applications:
        cartData.cart_level_discount_applications || [],
    },
    shipping_address: normalizedAddress,
    buyer_identity: buyerIdentity,
    payment_amount: fullTotalWithTaxAndShipping,
    selected_rule_id: selectedRule,
    return_url: returnUrl,
    shipping_rate_details: shippingRateDetails,
  });

  if (
    !razorpayOrderResponse.success ||
    !razorpayOrderResponse.razorpay_order_id
  ) {
    throw new Error(
      razorpayOrderResponse.error || "Failed to create payment order",
    );
  }
  if (!razorpayOrderResponse.key_id)
    throw new Error("Missing Razorpay key ID in response");
  if (!razorpayOrderResponse.amount)
    throw new Error("Missing amount in response");

  const customerName =
    `${normalizedAddress.first_name} ${normalizedAddress.last_name}`.trim() ||
    "Customer";

  return {
    key: razorpayOrderResponse.key_id,
    amount: razorpayOrderResponse.amount,
    currency: razorpayOrderResponse.currency || "INR",
    name: shopDomain?.replace(".myshopify.com", "") || "Merchant",
    description: "Payment for order",
    order_id: razorpayOrderResponse.razorpay_order_id,
    ...(callbackUrl ? { callback_url: callbackUrl } : {}),
    prefill: {
      name: customerName,
      email: buyerIdentity.email || "",
      contact: buyerIdentity.phone
        ? buyerIdentity.phone.replace(/\+/g, "")
        : "",
    },
  };
}

/**
 * Verify Razorpay payment and create Shopify order.
 * @param {Object} response - Razorpay success response
 * @param {Object} otpStoreActions - Store actions
 * @returns {Promise<{ success: boolean, message: string, orderNumber?: string | null, orderStatusUrl?: string | null }>}
 */
export async function verifyRazorpayAndCreateOrder(response, otpStoreActions) {
  // Filter out browser-native events
  if (
    response &&
    typeof response === "object" &&
    "isTrusted" in response &&
    !response.razorpay_payment_id &&
    !response.razorpay_order_id
  ) {
    return { success: false, message: "" };
  }

  const shopDomain = getShopDomain();
  const razorpayPaymentId =
    response?.razorpay_payment_id || response?.razorpayPaymentId;
  const razorpayOrderId =
    response?.razorpay_order_id || response?.razorpayOrderId;
  const razorpaySignature =
    response?.razorpay_signature || response?.razorpaySignature;

  if (!razorpayPaymentId || !razorpayOrderId || !razorpaySignature) {
    throw new Error(
      `Missing payment details in response: ${JSON.stringify(response)}`,
    );
  }

  const verifyResponse = await verifyRazorpayPayment({
    shop_domain: shopDomain,
    razorpay_payment_id: razorpayPaymentId,
    razorpay_order_id: razorpayOrderId,
    razorpay_signature: razorpaySignature,
  });

  if (verifyResponse.success && verifyResponse.order) {
    try {
      await clearCart();
      // Restore _otpVerifiedPhoneNumber, _codkSessionId and _codkCountryCode on the empty cart (they are removed by clear)
      const verifiedData = getSessionValue("verifiedNumberData") || {};
      const phone = verifiedData.otpVerifiedPhoneNumber || "";
      const sessionId = getMachineId() || "";
      const countryCode = verifiedData.countryCode || "";
      if (phone || sessionId || countryCode) {
        try {
          await executePost({
            attributes: {
              ...(phone && { _otpVerifiedPhoneNumber: phone }),
              ...(sessionId && { _codkSessionId: sessionId }),
              ...(countryCode && { _codkCountryCode: countryCode }),
            },
          });
        } catch (_e) {}
      }
      otpStoreActions.setCurrentCartData(null);
    } catch (_clearError) {}

    return {
      success: true,
      message: `Order #${verifyResponse.order.number} created successfully!`,
      orderNumber: verifyResponse.order.number
        ? String(verifyResponse.order.number)
        : null,
      orderStatusUrl: verifyResponse.order.order_status_url || null,
    };
  }

  throw new Error(
    verifyResponse.error ||
      verifyResponse.message ||
      "Failed to verify payment",
  );
}

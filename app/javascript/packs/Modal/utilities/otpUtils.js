// otpUtils.js
import CountryCode from "../../Components/CountryCode";
import useOtpStore from "../stores/otpStore";
import { handleCustomeShopifyLogin } from "../services/customerCredentialService";
import { getCart } from "../services/otpService";
import { sendErrorToAPI } from "../services/errorReporter";
import { createLightweightGraphQLClient } from "../services/lightweightGraphQLClient";
import { normalizeProvince, normalizePhoneE164 } from "./addressValidation";
const settings = getSessionValue("settingSession");
export const MAX_TRY_PHONE_NO_CHANGE = 3;
export const SERVER_ERROR_TEXT =
  settings?.tooManyAttemptsText ||
  "Too many attemps. Please select other payment options.";
export const WRONG_PHONE_TEXT = "Invalid mobile number.";
export const WRONG_CALLING_COUNTRY_CODE_TEXT = "Wrong country code.";
export const DID_NOT_RECEIVE_OTP_TEXT =
  settings?.retryInText || "Didn't receive the Code? Retry in ";
export const CHANGE_LINK_TEXT = "Change";
export const RESEND_LINK_TEXT = settings?.resendText || "Resend";
export const OTP_SENT_TEXT = "Code was sent to";
export const FAILED_TO_VERIFY_OTP =
  settings?.failedToVerifyText || "Failed to verify OTP. Please try again.";
export const VERIFYING_TEXT = settings?.verifyingText || "Verifying";
export const PHONE_PLACE_HOLDER =
  settings?.phonePlaceholder || "Enter phone number";
export const PLEASE_ENTER_VALID_PHONE_NUMBER =
  settings?.invalidPhoneText || "Please enter a valid phone number.";
export const VERIFY_MOBILE_NUMBER =
  settings?.verifyMobileText || "Verify Mobile Number";
export const ENTER_CODE_SEND_TO =
  settings?.enterCodeText || "Enter the code sent to ";
export const CODK_MAX_RETRY_TEXT = "Maximum retry limit reached";
export const CODK_OTP_CARD_CLASS_DEFAULT = "codk-otpw-container";
export const SLIDE_LEFT_CLASS = "codk-slide-left";
export const SLIDE_RIGHT_CLASS = "codk-slide-right";
export const CODK_OTP_VERIFY_CARD_CLASS = "codk-otpw-verify-card";
export const CODK_OTP_VERIFY_CARD_WRAPPER_CLASS =
  "codk-otpw-verify-card-warapper";
export const CODK_OTP_WRAPPER_CLASS = "codk-otpw-otp";

export const CODK_OTP_VERIFY_BTN_WRAPPER_CLASS = "codk-otpw-verify";
export const CODK_OTP_VERIFY_BTN_CLASS = "codk-otpw-verify-btn-div";
export const OTP_VERIFIED_TEXT =
  settings?.redirectText ||
  "OTP Verified! You're all set. Redirecting to checkout...";
export const settingsMap = {
  enable_pre_order_otp: "enablePreOrderOtp",
  otp_wait_time: "otpWaitTimeInCodKSettings",
  max_retries: "maxTriesInCodKSettings",
  country_code_list: "countryCodeList",
  pre_invalid_otp_msg: "wrongOtpText",
  pre_verify_button_label: "verifyBtnText",
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
  variant_pick_condition: "variantPickCondition",
  brand_logo_url: "brandLogoUrl",
  quick_onboarding_visited: "quickOnboardingVisited",
  user_journey: "userJourney",
  pre_v2_overwrite_popup_condition: "preV2OverwritePopupCondition",
  pre_v2_cart_drawer_layout_selectors: "preV2CartDrawerLayoutSelectors",
  partial_payment_flow_version: "partialPaymentFlowVersion",
  partial_expand_flow_enabled: "partialExpandFlowEnabled",
  shopify_visitor_app_id: "shopifyVisitorAppId",
  conversion_tracking: "conversionTracking",
  // settingSession is built by projecting the API response through this map, so
  // anything missing here never reaches the widget. Keep in sync with
  // notifik-svelte-app/src/utils/settingsMapper.js.
  pre_proceed_button_label: "preProceedButtonLabel",
  pre_v2_no_rule_qualified_message: "preV2NoRuleQualifiedMessage",
  hide_for_unverified_orders: "hideForUnverifiedOrders",
  promo_banner_show: "promoBannerShow",
  promo_banner_text: "promoBannerText",
  promo_banner_color: "promoBannerColor",
  promo_text_color: "promoTextColor",
  show_offer_and_reward: "showOfferAndReward",
  pre_v2_show_tax_info: "preV2ShowTaxInfo",
  pre_v2_show_shipping_info: "preV2ShowShippingInfo",
  is_tax_included_with_product: "isTaxIncludedWithProduct",
  persistent_signin: "persistentSignin",
  revert_discount: "revertDiscount",
  web_ux_version: "webUxVersion",
  optimized_buy_now: "optimizedBuyNow",
  codking_loading: "codkingLoading",
  active_discounts: "activeDiscounts",
  pixel_id: "pixelId",
  pixel_test_event_id: "pixelTestEventId",
  shop_updated_at: "shopUpdatedAt",
  cod_form_config: "codFormConfig",
};

export const COD_FORM_DEFAULT_PLACEHOLDERS = {
  name: "e.g. Rahul Sharma",
  pincode: "e.g. 110001",
  city: "e.g. New Delhi",
  state: "e.g. Delhi",
  email: "e.g. rahul@gmail.com",
  address1: "e.g. MG Road, Sector 14",
  address2: "e.g. Flat 302, Green Apartments",
};

export const COD_FORM_DEFAULT_GST = {
  enabled: false,
  label: "GST Number",
  placeholder: "e.g. 22AAAAA0000A1Z5",
  required: false,
};

export const getCodFormConfig = (settings) => {
  const cfg = settings?.codFormConfig || settings?.cod_form_config || {};
  const labels = cfg.labels || {};
  const placeholders = cfg.placeholders || {};
  const gst = cfg.gst || {};
  return {
    labels: Object.fromEntries(
      Object.keys(COD_FORM_DEFAULT_PLACEHOLDERS).map((key) => [
        key,
        (labels[key] && String(labels[key]).trim()) || "",
      ])
    ),
    placeholders: Object.fromEntries(
      Object.entries(COD_FORM_DEFAULT_PLACEHOLDERS).map(([key, fallback]) => [
        key,
        (placeholders[key] && String(placeholders[key]).trim()) || fallback,
      ])
    ),
    gst: {
      enabled: gst.enabled === true,
      required: gst.required === true,
      label:
        (gst.label && String(gst.label).trim()) || COD_FORM_DEFAULT_GST.label,
      placeholder:
        (gst.placeholder && String(gst.placeholder).trim()) ||
        COD_FORM_DEFAULT_GST.placeholder,
    },
  };
};

export const resetTimer = (
  setTimer,
  otpWaitTimeInCodKSettings,
  timer,
  forceReset = false,
) => {
  const timerSizeInSeconds = otpWaitTimeInCodKSettings
    ? otpWaitTimeInCodKSettings
    : 60;
  if (!timer) {
    setTimer(timerSizeInSeconds);
  }
  if (forceReset) {
    setTimer(timerSizeInSeconds);
  }
};

function uuidv4() {
  // Backs getMachineId(), which is used for device identity — same CSPRNG
  // requirement as the other id generators in this bundle.
  const rng =
    typeof globalThis !== "undefined" && globalThis.crypto ? globalThis.crypto : null;
  if (rng && typeof rng.randomUUID === "function") return rng.randomUUID();
  if (rng && typeof rng.getRandomValues === "function") {
    const bytes = new Uint8Array(16);
    rng.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0"));
    return `${hex.slice(0,4).join("")}-${hex.slice(4,6).join("")}-${hex.slice(6,8).join("")}-${hex.slice(8,10).join("")}-${hex.slice(10,16).join("")}`;
  }
  throw new Error("Secure random source unavailable; cannot generate id");
}
export function getMachineId() {
  let machineId = getSessionValue("MachineId");
  if (!machineId) {
    machineId = uuidv4();
    setSessionValue("MachineId", machineId);
  }
  return machineId;
}

// Utility function to get country code from calling code
export const getCountryCode = (countryCallingCode) => {
  const filterCountry = CountryCode.filter(
    (country) => country.label == countryCallingCode,
  );
  return filterCountry[0].value;
};

// Utility function to check if a number is valid
export const isValidNumber = (text) => {
  const re = /^[0-9\b]+$/;
  return re.test(text);
};

export const populateCallingCodeList = (text) => {
  return text;
};

export function setSessionValue(key, object) {
  try {
    const jsonString = JSON.stringify(object);
    // Store the JSON string in sessionStorage with the provided key
    sessionStorage.setItem(key, jsonString);
  } catch (error) {
    console.error("Error storing verified number in sessionStorage:", error);
  }
}
export function getSessionValue(key) {
  try {
    //key = verifiedNumberData
    // Retrieve the JSON string from sessionStorage
    const jsonString = sessionStorage?.getItem(key);
    // If the key does not exist, return null
    if (!jsonString) {
      return null;
    }
    // Parse the JSON string back into an object
    return JSON?.parse(jsonString);
  } catch (error) {
    console.error("Error retrieving sessionStorage:", error);
    return null;
  }
}

export function removeSessionValue(key) {
  try {
    // Remove the item from sessionStorage by key
    sessionStorage.removeItem(key);
  } catch (error) {
    console.error(`Error removing key "${key}" from sessionStorage:`, error);
  }
}

export function setLocalValue(key, object) {
  try {
    const jsonString = JSON.stringify(object);
    localStorage.setItem(key, jsonString);
  } catch (error) {
    console.error("Error storing data in localStorage:", error);
  }
}

export function getLocalValue(key) {
  try {
    const jsonString = localStorage?.getItem(key);
    if (!jsonString) {
      return null;
    }
    return JSON?.parse(jsonString);
  } catch (error) {
    console.error("Error retrieving data from localStorage:", error);
    return null;
  }
}

export function removeLocalValue(key) {
  try {
    // Remove the item from localStorage by key
    localStorage.removeItem(key);
  } catch (error) {
    console.error(`Error removing key "${key}" from localStorage:`, error);
  }
}

export function generatePassword() {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const passwordLength = 20;

  // This value becomes the customer's Shopify account password, so it must come
  // from a CSPRNG. Math.random() is a seeded PRNG whose internal state can be
  // recovered from a few observed outputs, which would make every password
  // generated afterwards in the same page predictable.
  const rng =
    typeof globalThis !== "undefined" && globalThis.crypto ? globalThis.crypto : null;
  if (!rng || typeof rng.getRandomValues !== "function") {
    // Fail closed rather than silently falling back to a predictable source.
    throw new Error("Secure random source unavailable; cannot generate account password");
  }

  // Rejection sampling: plain modulo would make the first (256 % 62) characters
  // of the alphabet more likely than the rest.
  const limit = 256 - (256 % chars.length);
  const buffer = new Uint8Array(passwordLength);
  let password = "";

  while (password.length < passwordLength) {
    rng.getRandomValues(buffer);
    for (let i = 0; i < buffer.length && password.length < passwordLength; i++) {
      if (buffer[i] < limit) password += chars[buffer[i] % chars.length];
    }
  }

  return password;
}

export function checkShippingConditions() {
  const preOrderOtpResponse = getSessionValue("preOrderOtpResponse");
  const settings = getSessionValue("settingSession");

  // Case 1: Login flow enabled and no shipping address available
  if (
    settings?.preIsLoginEnabled === true &&
    settings?.isPrefilledAddressEnabled === true &&
    (!preOrderOtpResponse?.shippingAddress ||
      !preOrderOtpResponse?.shippingAddress.length)
  ) {
    debugLog(
      "Login flow and prefilled address are enabled, but no shipping address available.",
    );
    setSessionValue("customer-id", preOrderOtpResponse?.customerId);
    setSessionValue("customer-email", preOrderOtpResponse?.email);
    return { success: true, nextStep: 4 }; // Add address
  }

  // Case 2: Login flow enabled and shipping address exists
  if (
    settings?.preIsLoginEnabled === true &&
    settings?.isPrefilledAddressEnabled === true &&
    preOrderOtpResponse?.shippingAddress?.length > 0
  ) {
    debugLog(
      "Login flow and prefilled address are enabled, and shipping address exists.",
    );
    setSessionValue("shipping_addresses", preOrderOtpResponse?.shippingAddress);
    setSessionValue("customer-id", preOrderOtpResponse?.customerId);
    setSessionValue("customer-email", preOrderOtpResponse?.email);
    return { success: true, nextStep: 3 }; // View address
  }

  // Case 3: Prefilled address enabled but login flow disabled
  if (
    settings?.preIsLoginEnabled === false &&
    settings?.isPrefilledAddressEnabled === true
  ) {
    if (preOrderOtpResponse?.shippingAddress?.length > 0) {
      debugLog(
        "Prefilled address enabled, login flow disabled, and shipping address exists.",
      );
      setSessionValue(
        "shipping_addresses",
        preOrderOtpResponse.shippingAddress,
      );
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setSessionValue("customer-email", preOrderOtpResponse?.email);
      return { success: true, nextStep: 3 }; // View address
    } else {
      debugLog(
        "Prefilled address enabled, login flow disabled, but no shipping address available.",
      );
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setSessionValue("customer-email", preOrderOtpResponse?.email);
      return { success: true, nextStep: 4 }; // Add address
    }
  }

  // Case 4: Prefilled address and login flow both disabled
  if (
    settings?.preIsLoginEnabled === false &&
    settings?.isPrefilledAddressEnabled === false
  ) {
    debugLog("Prefilled address and login flow are both disabled.");
    return { success: true, nextStep: 5 }; // Proceed to verified tick mark
  }

  // Case 5: Partial payment enabled and prefilled address enabled
  if (
    settings?.partialPaymentEnabled === true &&
    settings?.isPrefilledAddressEnabled === true
  ) {
    if (preOrderOtpResponse?.shippingAddress?.length > 0) {
      debugLog(
        "Partial payment and prefilled address are enabled, and shipping address exists.",
      );
      setSessionValue(
        "shipping_addresses",
        preOrderOtpResponse.shippingAddress,
      );
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setSessionValue("customer-email", preOrderOtpResponse?.email);
      return { success: true, nextStep: 3 }; // Proceed to view address
    } else {
      debugLog(
        "Partial payment and prefilled address are enabled, but no shipping address available.",
      );
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setSessionValue("customer-email", preOrderOtpResponse?.email);
      return { success: true, nextStep: 4 }; // Add address
    }
  }

  // Case 6: Partial payment enabled and prefilled address disabled
  if (
    settings?.partialPaymentEnabled === true &&
    settings?.isPrefilledAddressEnabled === false
  ) {
    debugLog("Partial payment enabled, but prefilled address is disabled.");
    setSessionValue("customer-id", preOrderOtpResponse?.customerId);
    setSessionValue("customer-email", preOrderOtpResponse?.email);
    return { success: true, nextStep: 5 }; // Proceed to verified tick
  }

  // Case 7: Partial payment and login flow both disabled
  if (
    settings?.partialPaymentEnabled === false &&
    settings?.preIsLoginEnabled === false
  ) {
    debugLog("Partial payment and login flow are both disabled.");
    return { success: true, nextStep: 5 }; // Proceed to verified tick mark
  }

  // Default case
  debugLog("Default condition met.");
  return { success: true, nextStep: 5 };
}

// Determines the next step based on various settings and response states
export function getNextStep(state, settingSession, preOrderOtpResponse) {
  if (state?.settings?.preIsLoginEnabled) {
    const { email, password } = preOrderOtpResponse?.customerLogin || {};
    if (email && password) {
      setSessionValue("CustomerCredential", { email, password });
      state.setCustomerCredentialAvailability(true);
      return async () => {
        const loginResult = await handleCustomeShopifyLogin(email, password);
        return loginResult.success ? loginResult.nextStep : 6;
      };
    }
    state.setCustomerCredentialAvailability(false);
    return () => 6;
  }

  return checkShippingConditions().nextStep;
}

export const checkCartPage = () => {
  const currentUrl = window.location.pathname;
  return currentUrl.includes("/cart");
};

export const checkProductPage = () => {
  const currentUrl = window.location.pathname; // Get the current URL path

  return currentUrl.includes("/product");
};

/**
 * Get storefront cart ID from token
 * @param {string} token - Cart token
 * @returns {string|null} - Storefront cart ID or null
 */
/**
 * Create cart using minimal mutation directly (same as error fallback)
 */
const createCartWithMinimalMutation = async (lines, cartAttributes) => {
  const settings = getSessionValue("settingSession");
  const shopifyDomain = window.Shopify?.shop;
  const storefrontToken = settings?.storeFrontToken;

  if (!shopifyDomain || !storefrontToken) {
    throw new Error("Shopify configuration not found");
  }

  const client = createLightweightGraphQLClient(shopifyDomain, storefrontToken);

  const CART_CREATE_MIN_MUTATION = `
    mutation CartCreate($lines: [CartLineInput!]!, $cartAttributes: [AttributeInput!]!) {
      cartCreate(input: { lines: $lines, attributes: $cartAttributes }) {
        cart {
          id
          checkoutUrl
          attributes { key value }
          discountCodes {
            code
            applicable
          }
          lines(first: 10) {
            edges {
              node {
                id
                quantity
                cost {
                  totalAmount { amount currencyCode }
                  amountPerQuantity { amount currencyCode }
                  subtotalAmount { amount currencyCode }
                }
                discountAllocations {
                  discountedAmount {
                    amount
                    currencyCode
                  }
                }
              }
            }
          }
          cost {
            totalAmount { amount currencyCode }
            subtotalAmount { amount currencyCode }
            totalTaxAmount { amount currencyCode }
            totalDutyAmount { amount currencyCode }
          }
          discountAllocations {
            discountedAmount {
              amount
              currencyCode
            }
          }
        }
        userErrors { field message }
      }
    }
  `;

  const { data } = await client.mutateWithCacheClear(CART_CREATE_MIN_MUTATION, {
    lines,
    cartAttributes,
  });

  if (data?.cartCreate?.userErrors?.length) {
    console.error("CartCreate (min) userErrors:", data.cartCreate.userErrors);
    throw new Error(
      data.cartCreate.userErrors[0]?.message || "Cart creation failed",
    );
  }

  if (data?.cartCreate?.cart) {
    return data.cartCreate.cart;
  }

  throw new Error("Cart creation failed");
};

/**
 * Check if cart has BOGO items
 */
export const hasBOGOItems = (cartItems) => {
  if (!cartItems || cartItems.length === 0) return false;
  return cartItems.some((item) => {
    if (item?.isBOGODiscount === true) return true;
    const finalLinePrice = item?.final_line_price || 0;
    const finalPrice = item?.final_price || 0;
    if (finalLinePrice === 0 || finalPrice === 0) {
      const hasDiscountAllocations =
        item?.line_level_discount_allocations?.length > 0 ||
        item?.discount_allocations?.length > 0;
      if (hasDiscountAllocations) return true;
    }
    return false;
  });
};

/**
 * Get free variant IDs from cart items with counts
 */
export const getFreeVariantIds = (cartItems) => {
  const freeItems = (cartItems || []).filter((item) => {
    const finalLinePrice = item?.final_line_price || 0;
    const finalPrice = item?.final_price || 0;
    return finalLinePrice === 0 || finalPrice === 0;
  });

  if (freeItems.length === 0) return "";

  const variantCountMap = new Map();
  freeItems.forEach((item) => {
    const variantId = item?.variant_id || item?.id;
    if (variantId != null) {
      const quantity = item?.quantity || 1;
      variantCountMap.set(
        variantId,
        (variantCountMap.get(variantId) || 0) + quantity,
      );
    }
  });

  return Array.from(variantCountMap.entries())
    .map(([variantId, count]) => `${variantId}:${count}`)
    .join(",");
};

/**
 * Check if cart has any free products (price = 0)
 */
export const hasFreeProducts = (cartItems) => {
  if (!cartItems || cartItems.length === 0) return false;
  return cartItems.some((item) => {
    const finalLinePrice = item?.final_line_price || 0;
    const finalPrice = item?.final_price || 0;
    return finalLinePrice === 0 || finalPrice === 0;
  });
};

/**
 * Calculate rule-level discount value
 */
export const calculateRuleLevelDiscount = (rule, originalCartTotalDecimal) => {
  const ruleDiscountValue = parseFloat(rule?.discount_value || 0);
  const ruleDiscountType = rule?.discount_type || "";
  const ruleDiscountCode = rule?.discount_code || "";

  if (ruleDiscountValue <= 0 || !ruleDiscountCode) return 0;

  if (ruleDiscountType === "percentage") {
    return (originalCartTotalDecimal * ruleDiscountValue) / 100;
  } else {
    return ruleDiscountValue;
  }
};

/**
 * Filter rules eligible for partial payment
 */
export const PartialPaymentFilteredRules = () => {
  try {
    const rules = getSessionValue("ruleSets");
    if (!Array.isArray(rules)) return [];

    return rules.filter((rule) => {
      const amountType = rule?.amount_type;
      const amountNum = rule?.amount != null ? Number(rule.amount) : null;
      const minRaw = rule?.min_cart_range;
      const maxRaw = rule?.max_cart_range;
      const min = minRaw != null ? Number(minRaw) : null;
      const max = maxRaw != null ? Number(maxRaw) : null;
      let totalNum = NaN;
      try {
        const currentCartData = useOtpStore.getState().currentCartData;
        if (
          currentCartData &&
          typeof currentCartData.total_price === "number"
        ) {
          totalNum = currentCartData.total_price / 100;
        }
      } catch (_) {}

      if (amountType === "cod") return false;
      if (amountType === "percentage" && amountNum === 100) return false;

      if (!Number.isNaN(totalNum)) {
        if (min != null && !Number.isNaN(min) && min > 0 && totalNum < min)
          return false;
        if (max != null && !Number.isNaN(max) && max > 0 && totalNum > max)
          return false;
      }
      return true;
    });
  } catch (e) {
    console.error("PartialPaymentFilteredRules: failed to parse ruleSets", e);
    return [];
  }
};

/**
 * Compare discount value from created cart with actual discount value
 */
const compareDiscountValues = (createdCart, actualDiscountValue) => {
  try {
    const actualDiscount = Number(actualDiscountValue);
    if (Number.isNaN(actualDiscount) || actualDiscount === 0) return null;

    let createdCartDiscount = 0;
    if (createdCart?.lines?.edges?.length > 0) {
      createdCartDiscount = createdCart.lines.edges.reduce((total, edge) => {
        const line = edge?.node;
        if (line?.discountAllocations?.length > 0) {
          const lineDiscount = line.discountAllocations.reduce(
            (sum, allocation) =>
              sum + Number(allocation?.discountedAmount?.amount || 0),
            0,
          );
          return total + lineDiscount;
        }
        return total;
      }, 0);
    }

    if (
      createdCartDiscount === 0 &&
      createdCart?.discountAllocations?.length > 0
    ) {
      createdCartDiscount = createdCart.discountAllocations.reduce(
        (sum, allocation) =>
          sum + Number(allocation?.discountedAmount?.amount || 0),
        0,
      );
    }

    const discountMatches =
      Math.abs(actualDiscount - createdCartDiscount) < 0.01;
    let source = "none";
    if (createdCartDiscount > 0) {
      source = createdCart?.lines?.edges?.some(
        (e) => e.node?.discountAllocations?.length > 0,
      )
        ? "line_discountAllocations"
        : "cart_discountAllocations";
    }

    return {
      matches: discountMatches,
      actualDiscount,
      createdCartDiscount,
      source,
      discountObjects: {
        lineDiscountAllocations: [], // Simplified for now
        cartDiscountAllocations: createdCart?.discountAllocations || [],
      },
    };
  } catch (e) {
    console.error("compareDiscountValues error:", e);
    return null;
  }
};

/**
 * Create Storefront carts for each eligible partial payment rule
 */
// export const createCartsForEligibleRules = async (forceRefresh = true) => {
//   setSessionValue("partial_payment_cart_results", null);
//   const results = [];

//   try {
//     const otpStore = useOtpStore.getState();
//     const currentCartData = otpStore?.currentCartData;
//     const eligibleRules = PartialPaymentFilteredRules();

//     if (!eligibleRules.length || !currentCartData?.items?.length) {
//       setSessionValue("partial_payment_cart_results", []);
//       return results;
//     }

//     const cartItems = currentCartData.items;
//     const lines = cartItems.map((item) => ({
//       quantity: item?.quantity ?? 1,
//       merchandiseId: `gid://shopify/ProductVariant/${
//         item?.variant_id || item?.id
//       }`,
//     }));

//     const actualDiscountValue = currentCartData?.total_discount
//       ? String(currentCartData.total_discount / 100)
//       : "0";

//     const rawDiscountCodes = (currentCartData?.discount_codes || [])
//       .map((dc) => (typeof dc === "string" ? dc : dc?.code))
//       .filter((code) => code && typeof code === "string");

//     const actualDiscountCodes =
//       Number(actualDiscountValue) > 0 ? rawDiscountCodes : [];
//     const freeVariantsValue = getFreeVariantIds(cartItems);
//     const hasBOGO = hasBOGOItems(cartItems);

//     const getCodkImageURLs = (items = []) => {
//       try {
//         const variantImageMap = new Map();
//         (items || []).forEach((item) => {
//           const variantId = item?.variant_id || item?.id;
//           if (variantId == null) return;

//           let imageURL =
//             item?.image || item?.image_url || item?.imageUrl || null;
//           if (!imageURL && item?.featured_image) {
//             if (typeof item.featured_image === "string") {
//               imageURL = item.featured_image;
//             } else if (item.featured_image?.url) {
//               imageURL = item.featured_image.url;
//             }
//           }
//           if (
//             imageURL &&
//             typeof imageURL === "string" &&
//             !variantImageMap.has(variantId)
//           ) {
//             variantImageMap.set(variantId, imageURL);
//           }
//         });

//         const entries = [];
//         variantImageMap.forEach((url, variantId) => {
//           entries.push(`${variantId}:${encodeURIComponent(url)}`);
//         });
//         return entries.join(",");
//       } catch (e) {
//         return "";
//       }
//     };

//     const getCodkDiscounts = (
//       items = [],
//       cartLevelDiscountApplications = [],
//       options = {},
//     ) => {
//       const discountEntries = [];

//       // Line-level discounts per variant (true line-level only)
//       const variantDiscountMap = new Map(); // variantId -> { discountCents, code }
//       (items || []).forEach((item) => {
//         const variantId = item?.variant_id || item?.id;
//         if (variantId == null) return;

//         const hasLineLevelDiscounts =
//           item?.line_level_discount_allocations &&
//           item.line_level_discount_allocations.length > 0;
//         if (!hasLineLevelDiscounts) return;

//         const lineDiscountCents =
//           item?.line_level_total_discount ||
//           (item?.line_level_discount_allocations || []).reduce(
//             (sum, alloc) => sum + (alloc?.amount || 0),
//             0,
//           );

//         const discountCode =
//           item?.line_level_discount_allocations?.[0]?.discount_application
//             ?.title ||
//           item?.line_level_discount_allocations?.[0]?.discount_application
//             ?.code ||
//           "";

//         if (lineDiscountCents > 0) {
//           const current = variantDiscountMap.get(variantId) || {
//             discountCents: 0,
//             code: "",
//           };
//           variantDiscountMap.set(variantId, {
//             discountCents: current.discountCents + lineDiscountCents,
//             code: current.code || discountCode,
//           });
//         }
//       });

//       variantDiscountMap.forEach((data, variantId) => {
//         const discountDecimal = data.discountCents / 100;
//         const entry = data.code
//           ? `${variantId}:${discountDecimal}|${data.code}`
//           : `${variantId}:${discountDecimal}`;
//         discountEntries.push(entry);
//       });

//       // Existing order-level discount from cart-level applications
//       let existingOrderLevelDiscountCents = 0;
//       let existingOrderLevelCode = "";
//       if (
//         cartLevelDiscountApplications &&
//         cartLevelDiscountApplications.length > 0
//       ) {
//         existingOrderLevelDiscountCents = cartLevelDiscountApplications.reduce(
//           (sum, d) => sum + (d?.total_allocated_amount || 0),
//           0,
//         );
//         existingOrderLevelCode =
//           cartLevelDiscountApplications[0]?.title ||
//           cartLevelDiscountApplications[0]?.code ||
//           "";
//       }
//       const existingOrderLevelDiscountDecimal =
//         existingOrderLevelDiscountCents / 100;

//       // Rule override (decimal)
//       const ruleOrder = options?.ruleOrderLevelDiscount || null;
//       const ruleAmount = Number(ruleOrder?.amount || 0);
//       const ruleCode = (ruleOrder?.code || "").trim();

//       let finalOrderLevelAmount = existingOrderLevelDiscountDecimal;
//       let finalOrderLevelCode = existingOrderLevelCode;
//       if (
//         ruleAmount > finalOrderLevelAmount ||
//         (ruleAmount === finalOrderLevelAmount && ruleCode)
//       ) {
//         finalOrderLevelAmount = ruleAmount;
//         finalOrderLevelCode = ruleCode || finalOrderLevelCode;
//       }

//       if (finalOrderLevelAmount > 0) {
//         const entry = finalOrderLevelCode
//           ? `orderLevel:${finalOrderLevelAmount}|${finalOrderLevelCode}`
//           : `orderLevel:${finalOrderLevelAmount}`;
//         discountEntries.push(entry);
//       }

//       return discountEntries.join(",");
//     };

//     const cartCreationPromises = eligibleRules.map(async (rule) => {
//       const amountType = rule?.amount_type ?? "0";
//       const amountValue = rule?.amount ?? "0";

//       const originalCartTotalDecimal =
//         typeof currentCartData?.original_total_price === "number"
//           ? currentCartData.original_total_price / 100
//           : ((currentCartData?.total_price || 0) +
//               (currentCartData?.total_discount || 0)) /
//             100;

//       const totalLineLevelDiscountDecimal = (cartItems || []).reduce(
//         (sum, item) => {
//           const hasLineLevelDiscounts =
//             item?.line_level_discount_allocations &&
//             item.line_level_discount_allocations.length > 0;
//           if (!hasLineLevelDiscounts) return sum;
//           const cents =
//             item?.line_level_total_discount ||
//             (item?.line_level_discount_allocations || []).reduce(
//               (s, alloc) => s + (alloc?.amount || 0),
//               0,
//             );
//           return sum + cents / 100;
//         },
//         0,
//       );

//       // Compute rule-set order-level discount (decimal), percentage base AFTER line-level discounts
//       const ruleDiscountValueNum = parseFloat(
//         String(rule?.discount_value ?? "0"),
//       );
//       const ruleDiscountType = rule?.discount_type || "";
//       const ruleDiscountCode = (rule?.discount_code || "").trim();
//       let ruleOrderLevelDiscountAmount = 0;
//       if (ruleDiscountCode && ruleDiscountValueNum > 0) {
//         ruleOrderLevelDiscountAmount =
//           ruleDiscountType === "percentage"
//             ? (Math.max(
//                 0,
//                 originalCartTotalDecimal - totalLineLevelDiscountDecimal,
//               ) *
//                 ruleDiscountValueNum) /
//               100
//             : ruleDiscountValueNum;
//       }

//       const ruleOrderLevelDiscount =
//         ruleOrderLevelDiscountAmount > 0 && ruleDiscountCode
//           ? { amount: ruleOrderLevelDiscountAmount, code: ruleDiscountCode }
//           : null;

//       const codkDiscounts = getCodkDiscounts(
//         cartItems,
//         currentCartData?.cart_level_discount_applications || [],
//         { ruleOrderLevelDiscount },
//       );
//       const codkImageURLs = getCodkImageURLs(cartItems);
//       const partialDummyVariantId =
//         typeof sessionStorage !== "undefined"
//           ? sessionStorage.getItem("partialDummyVariantId")
//           : null;

//       const cartAttributes = [
//         { key: "_codkAmountType", value: String(amountType) },
//         { key: "_codkAmountValue", value: String(amountValue) },
//         {
//           key: "_codkFinalDiscountValue",
//           value: actualDiscountValue,
//         },
//       ];

//       if (freeVariantsValue) {
//         cartAttributes.push({
//           key: "_codkFreeVariants",
//           value: freeVariantsValue,
//         });
//       }

//       if (codkDiscounts) {
//         cartAttributes.push({ key: "_codkDiscounts", value: codkDiscounts });
//       }
//       if (codkImageURLs) {
//         cartAttributes.push({ key: "_codkImageURLs", value: codkImageURLs });
//       }
//       if (partialDummyVariantId) {
//         cartAttributes.push({
//           key: "_partial_product_variant",
//           value: partialDummyVariantId,
//         });
//       }

//       try {
//         const cart = await createCartWithMinimalMutation(lines, cartAttributes);
//         const createdCartDiscountCodes = (cart?.discountCodes || [])
//           .map((dc) => (typeof dc === "string" ? dc : dc?.code))
//           .filter(Boolean);

//         const isAutomaticDiscount =
//           actualDiscountCodes.length === 0 && Number(actualDiscountValue) > 0;
//         const discountCodesMatchBase =
//           actualDiscountCodes.length === createdCartDiscountCodes.length &&
//           actualDiscountCodes.length > 0 &&
//           actualDiscountCodes.every((code) =>
//             createdCartDiscountCodes.includes(code),
//           );

//         const discountValueMatch = compareDiscountValues(
//           cart,
//           actualDiscountValue,
//         );
//         const discountCodesMatch = isAutomaticDiscount
//           ? discountValueMatch?.matches === true
//           : actualDiscountCodes.length > 0
//             ? discountCodesMatchBase && discountValueMatch?.matches === true
//             : null;

//         const currentCartTotalDecimal =
//           (currentCartData?.total_price || 0) / 100;
//         const existingCartDiscountValueDecimal = parseFloat(
//           actualDiscountValue || 0,
//         );
//         const originalCartTotalDecimal =
//           currentCartTotalDecimal + existingCartDiscountValueDecimal;
//         const ruleLevelDiscount = calculateRuleLevelDiscount(
//           rule,
//           originalCartTotalDecimal,
//         );

//         const shouldUseRuleDiscount =
//           rule?.discount_code?.trim() &&
//           (ruleLevelDiscount > existingCartDiscountValueDecimal ||
//             existingCartDiscountValueDecimal === 0);

//         const createdCartDiscountValue =
//           discountValueMatch?.createdCartDiscount ?? 0;
//         const discountValueMatches =
//           Math.abs(
//             existingCartDiscountValueDecimal - createdCartDiscountValue,
//           ) < 0.01;
//         const isDiscountActuallyApplied =
//           discountValueMatch?.source !== "none" &&
//           discountValueMatch?.matches === true;

//         const needsDiscountCode =
//           !hasBOGO &&
//           !isDiscountActuallyApplied &&
//           !discountValueMatches &&
//           !shouldUseRuleDiscount &&
//           Number(actualDiscountValue) > 0;

//         return {
//           ruleId: rule?.id,
//           ruleName: rule?.rule_name,
//           cart,
//           discountCodesMatch,
//           actualDiscountCodes,
//           createdCartDiscountCodes,
//           actualDiscountValue,
//           discountValueMatch: discountValueMatch?.matches ?? false,
//           createdCartDiscountValue,
//           discountSource: discountValueMatch?.source ?? "none",
//           needsDiscountCode,
//           shouldUseRuleDiscount,
//         };
//       } catch (err) {
//         console.error(
//           `[createCartsForEligibleRules] Error for rule ${rule?.id}:`,
//           err,
//         );
//         return {
//           ruleId: rule?.id,
//           ruleName: rule?.rule_name,
//           error: String(err),
//         };
//       }
//     });

//     const results = await Promise.all(cartCreationPromises);
//     setSessionValue("partial_payment_cart_results", results);
//     return results;
//   } catch (error) {
//     console.error("❌ [createCartsForEligibleRules] Fatal error:", error);
//     setSessionValue("partial_payment_cart_results", []);
//     return [];
//   }
// };

export const getStorefrontCartId = (token) => {
  if (!token || typeof token !== "string") {
    debugLog("Invalid or missing cart token");
    return null;
  }
  return `gid://shopify/Cart/${token}`;
};

export const formatCurrency = (amount, currencyCode = "INR") => {
  try {
    const formatted = new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: currencyCode,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(amount);
    // Remove .00 for whole numbers
    return formatted.replace(/\.00$/, "");
  } catch (error) {
    console.error("Currency formatting error:", error);
    const fallback = `${currencyCode} ${amount}`;
    return fallback.replace(/\.00$/, "");
  }
};

export const getCurrentStep = async () => {
  const state = useOtpStore.getState();
  const settings = getSessionValue("settingSession");
  const session = getSessionValue("verifiedNumberData");
  let currentStepKey;
  const {
    enablePreOrderOtp,
    isPrefilledAddressEnabled,
    partialPaymentEnabled,
    preIsLoginEnabled,
  } = settings;

  const isOtpVerified = !!(session && session.isOTPVerified);
  const {
    isPrefilledAddressCompleted,
    isPartialPaymentCartReadyAndUpdated,
    isLoginProcessCompleted,
    orderSummaryTotalQuantity,
  } = state;

  const steps = {
    OTP_VERIFICATION: "OTP_VERIFICATION",
    CUSTOMER_LOGIN: "CUSTOMER_LOGIN",
    SHIPPING_ADDRESS: "SHIPPING_ADDRESS",
    PARTIAL_PAYMENT: "PARTIAL_PAYMENT",
    REDIRECTION_TO_CHECKOUT: "REDIRECTION_TO_CHECKOUT",
  };

  const mapping = {
    OTP_VERIFICATION: 1,
    CUSTOMER_LOGIN: 6,
    SHIPPING_ADDRESS: 3,
    PARTIAL_PAYMENT: 7,
    REDIRECTION_TO_CHECKOUT: 5,
  };

  const handlePreLoginEnabled = async (preIsLoginEnabled) => {
    if (preIsLoginEnabled) {
      const { email, password } =
        getSessionValue("preOrderOtpResponse")?.customerLogin || {};
      if (email && password) {
        setSessionValue("CustomerCredential", { email, password });
        state.setCustomerCredentialAvailability(true);
        const loginResult = await handleCustomeShopifyLogin(email, password);
        if (loginResult.success) {
          state.setIsLoginProcessCompleted(true);
          if (orderSummaryTotalQuantity === 0) {
            window.location.href = `https://${window.Shopify.shop}/account`;
            return;
          } else if (orderSummaryTotalQuantity > 0) {
            return getMappedStep();
          }
        } else {
          state.setCustomerCredentialAvailability(false);
          state.setIsLoginProcessCompleted(false);
          currentStepKey = steps.CUSTOMER_LOGIN;
          return currentStepKey;
        }
      } else {
        state.setCustomerCredentialAvailability(false);
        state.setIsLoginProcessCompleted(false);
        currentStepKey = steps.CUSTOMER_LOGIN;
        return currentStepKey;
      }
    }
  };

  async function getMappedStep() {
    const latestState = useOtpStore.getState();
    const {
      isPrefilledAddressCompleted,
      isPartialPaymentCartReadyAndUpdated,
      isLoginProcessCompleted,
    } = latestState;
    if (enablePreOrderOtp && !isOtpVerified) {
      currentStepKey = steps.OTP_VERIFICATION;
    } else if (preIsLoginEnabled && !isLoginProcessCompleted) {
      return await handlePreLoginEnabled(preIsLoginEnabled);
    } else if (isPrefilledAddressEnabled && !isPrefilledAddressCompleted) {
      currentStepKey = steps.SHIPPING_ADDRESS;
    } else if (partialPaymentEnabled && !isPartialPaymentCartReadyAndUpdated) {
      currentStepKey = steps.PARTIAL_PAYMENT;
    } else {
      currentStepKey = steps.REDIRECTION_TO_CHECKOUT;
    }
    return currentStepKey;
  }

  currentStepKey = await getMappedStep();

  return mapping[currentStepKey];
};
export const debugLog = (...args) => {
  const settingSession = getSessionValue("settingSession");
  if (settingSession?.debug == true) {
    console.log(...args);
  } else {
    process.env.DEBUG_MODE == true && console.log(...args);
  }
};

export function stableStringify(obj) {
  if (Array.isArray(obj)) {
    return `[${obj.map(stableStringify).join(",")}]`;
  } else if (obj && typeof obj === "object") {
    const keys = Object.keys(obj).sort();
    return `{${keys
      .map((k) => `"${k}":${stableStringify(obj[k])}`)
      .join(",")}}`;
  } else {
    return JSON.stringify(obj);
  }
}

function simpleHash(str) {
  let hash = 5381;
  for (let i = 0; i < str.length; i++) {
    hash = (hash * 33) ^ str.charCodeAt(i);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export async function hashJsonObject(obj) {
  const jsonString = stableStringify(obj);
  return simpleHash(jsonString);
}

export function simplifyCartItems(cartItems) {
  return cartItems.map((item) => ({
    product_id: item.product_id?.toString(),
    variant_id: item.variant_id.toString(),
    title: item.title,
    quantity: item.quantity,
    price: Math.round(item.price / 100), // assuming price is in cents
    featured_image: item.featured_image?.url || null,
  }));
}

export function getDeviceType() {
  const ua = navigator.userAgent;
  if (/tablet|ipad|playbook|silk/i.test(ua)) return "Tablet";
  if (/mobile|android|iphone|ipod|blackberry|iemobile|opera mini/i.test(ua))
    return "Mobile";
  return "Desktop";
}

export async function getCartItemsOrRefetch() {
  try {
    let cartData = await getCart();

    if (cartData?.items?.length > 0) {
      return cartData.items;
    }

    // Retry with force fetch
    debugLog(
      "Initial cartData.items not found, retrying with getCart(true)...",
    );
    cartData = await getCart(true);

    if (cartData?.items?.length > 0) {
      debugLog("Items found after retry with getCart(true)");
      return cartData.items;
    }

    return []; // Final fallback
  } catch (error) {
    console.error("Error fetching cart data:", error);
    return [];
  }
}

export function getVariantIdQuantityAndProperties() {
  const settings = getSessionValue("settingSession");
  const variantPickCondition = settings?.variantPickCondition;
  debugLog("variantPickCondition", variantPickCondition);

  let methodUsed = null;

  const storeVariantStrategy = {
    "1b86a7-cc.myshopify.com": 3,
    "mavani-fashion.myshopify.com": 3,
  };

  const currentShop = window?.Shopify?.shop || window.location.hostname;
  const preferredMethod = storeVariantStrategy[currentShop] || null;

  const getQuantity = () => {
    const quantityInput =
      document.querySelector('quantity-input input[name="quantity"]') ||
      document.querySelector('[name="quantity"]');
    if (quantityInput && quantityInput.value) {
      return parseInt(quantityInput.value, 10) || 1;
    }
    return 1;
  };

  // NEW: Function to get all properties from form inputs
  const getProperties = () => {
    const properties = {};

    // Look for property inputs with name format like "properties[Custom Text]"
    const propertyInputs = document.querySelectorAll(
      'input[name^="properties["], textarea[name^="properties["], select[name^="properties["]',
    );

    propertyInputs.forEach((input) => {
      const name = input.name;
      const match = name.match(/properties\[([^\]]+)\]/);
      if (match && input.value.trim()) {
        const propertyName = match[1];
        properties[propertyName] = input.value.trim();
      }
    });

    // Also check for data-property attributes (some themes use this)
    const dataPropertyInputs = document.querySelectorAll("[data-property]");
    dataPropertyInputs.forEach((input) => {
      const propertyName = input.getAttribute("data-property");
      if (propertyName && input.value && input.value.trim()) {
        properties[propertyName] = input.value.trim();
      }
    });

    // Check for line item properties in forms
    const form = document.querySelector('form[action*="/cart/add"]');
    if (form) {
      const formData = new FormData(form);
      for (let [key, value] of formData.entries()) {
        if (key.startsWith("properties[") && value.trim()) {
          const match = key.match(/properties\[([^\]]+)\]/);
          if (match) {
            properties[match[1]] = value.trim();
          }
        }
      }
    }

    return properties;
  };

  const getFromURL = () => {
    const urlParams = new URLSearchParams(window.location.search);
    const variantIdFromURL = urlParams.get("variant");
    if (variantIdFromURL) {
      const id = parseInt(variantIdFromURL, 10);
      const qty = getQuantity();
      const props = getProperties();
      debugLog(
        "✅ Variant ID from URL:",
        id,
        "Quantity:",
        qty,
        "Properties:",
        props,
      );
      methodUsed = 1;
      return { variantID: id, quantity: qty, properties: props };
    }
    return null;
  };

  const getFromShopifyAnalytics = () => {
    try {
      const metaVariantId = window?.ShopifyAnalytics?.meta?.selectedVariantId;
      if (metaVariantId) {
        const id = parseInt(metaVariantId, 10);
        const qty = getQuantity();
        const props = getProperties();
        debugLog(
          "✅ Variant ID from ShopifyAnalytics.meta:",
          id,
          "Quantity:",
          qty,
          "Properties:",
          props,
        );
        methodUsed = 2;
        return { variantID: id, quantity: qty, properties: props };
      }
    } catch (e) {
      console.warn("⚠️ Error accessing ShopifyAnalytics.meta:", e);
    }
    return null;
  };

  const getFromInputNameId = () => {
    const variantIdInput = document.querySelector('[name="id"]');
    if (variantIdInput && variantIdInput.value) {
      const id = parseInt(variantIdInput.value, 10);
      const qty = getQuantity();
      const props = getProperties();
      debugLog(
        "✅ Variant ID from input[name='id']:",
        id,
        "Quantity:",
        qty,
        "Properties:",
        props,
      );
      methodUsed = 3;
      return { variantID: id, quantity: qty, properties: props };
    }
    return null;
  };

  const getFromAcceleratedCheckout = () => {
    const acceleratedCheckout = document.querySelector(
      "shopify-accelerated-checkout",
    );
    if (acceleratedCheckout) {
      const variantParams = acceleratedCheckout.getAttribute("variant-params");
      if (variantParams) {
        try {
          const variantArray = JSON.parse(variantParams);
          if (
            Array.isArray(variantArray) &&
            variantArray.length > 0 &&
            variantArray[0].id
          ) {
            const id = parseInt(variantArray[0].id, 10);
            const qty = getQuantity();
            const props = getProperties();
            debugLog(
              "✅ Variant ID from shopify-accelerated-checkout:",
              id,
              "Quantity:",
              qty,
              "Properties:",
              props,
            );
            methodUsed = 4;
            return { variantID: id, quantity: qty, properties: props };
          }
        } catch (error) {
          console.error("❌ Error parsing variant-params JSON:", error);
        }
      }
    }
    return null;
  };

  const getFromSelectNameId = () => {
    const variantSelect = document.querySelector('select[name="id"]');
    if (variantSelect && variantSelect.value) {
      const id = parseInt(variantSelect.value, 10);
      const qty = getQuantity();
      const props = getProperties();
      debugLog(
        "✅ Variant ID from <select name='id'>:",
        id,
        "Quantity:",
        qty,
        "Properties:",
        props,
      );
      methodUsed = 5;
      return { variantID: id, quantity: qty, properties: props };
    }
    return null;
  };

  const strategies = {
    1: getFromURL,
    2: getFromShopifyAnalytics,
    3: getFromInputNameId,
    4: getFromAcceleratedCheckout,
    5: getFromSelectNameId,
  };

  // ✅ Step 0: Always prefer URL if found
  const urlResult = getFromURL();
  if (urlResult) return urlResult;

  // 🔒 Step 1: Forced method from setting
  if (variantPickCondition >= 1 && variantPickCondition <= 5) {
    const forced = strategies[variantPickCondition]?.();
    if (forced) return forced;
    console.warn(
      `⚠️ Forced method ${variantPickCondition} from setting failed.`,
    );
  } else {
    // 🛠️ Step 2: Preferred method by store strategy
    if (preferredMethod && strategies[preferredMethod]) {
      const result = strategies[preferredMethod]();
      if (result) return result;
      console.warn(
        `⚠️ Preferred method ${preferredMethod} for ${currentShop} failed. Trying others.`,
      );
    }

    // 🔁 Step 3: Try all other strategies
    for (const step of [2, 3, 4, 5]) {
      if (step === preferredMethod) continue;
      const result = strategies[step]();
      if (result) return result;
    }
  }

  // ❌ Nothing worked
  console.warn("❌ Variant ID could not be determined.");
  return { variantID: null, quantity: 1, properties: {} };
}

export function checkImageAspectRatio(imageUrl) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "Anonymous"; // Helps with CORS issues for some images
    img.onload = function () {
      const { width, height } = img;
      if (width === height) {
        resolve("Square image");
      } else if (width > height) {
        resolve("Wide image");
      } else {
        resolve("Tall image");
      }
    };
    img.onerror = function () {
      reject(new Error("Failed to load the image."));
    };
    img.src = imageUrl;
  });
}

export const isIPhone = /iPhone/i.test(navigator.userAgent);

// Fallback function to get machine details from browser APIs
export const getMachineDetailsFromBrowser = async () => {
  try {
    const fallbackData = {
      data: {
        ip: null,
        country_code: null,
        country_name: null,
        city: null,
        region: null,
        timezone: null,
        source: "browser_fallback",
      },
    };

    // Try to get IP using WebRTC (if available)
    if (window.RTCPeerConnection) {
      try {
        const pc = new RTCPeerConnection({
          iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
        });

        pc.createDataChannel("");
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        // This is a simplified approach - in practice, you'd need to parse the ICE candidates
        // For now, we'll use other browser APIs
      } catch (rtcError) {
        debugLog("WebRTC method failed:", rtcError);
      }
    }

    // Get timezone from browser
    if (Intl && Intl.DateTimeFormat) {
      const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      fallbackData.data.timezone = timezone;

      // Try to extract country from timezone
      if (timezone) {
        const timezoneParts = timezone.split("/");
        if (timezoneParts.length > 1) {
          const region = timezoneParts[0];
          // Map some common timezone regions to countries
          const regionToCountry = {
            America: "US",
            Europe: "GB",
            Asia: "IN",
            Africa: "ZA",
            Australia: "AU",
            Pacific: "NZ",
          };

          if (regionToCountry[region]) {
            fallbackData.data.country_code = regionToCountry[region];
            fallbackData.data.country_name = getCountryName(
              regionToCountry[region],
            );
          }
        }
      }
    }

    // Get language/locale information
    if (navigator.language) {
      const locale = navigator.language;
      const countryCode = locale.split("-")[1];
      if (countryCode && countryCode.length === 2) {
        fallbackData.data.country_code = countryCode.toUpperCase();
        fallbackData.data.country_name = getCountryName(
          countryCode.toUpperCase(),
        );
      }
    }

    // Get additional browser info
    if (navigator.userAgent) {
      // You could parse user agent for additional location hints
      debugLog("User agent available for additional parsing");
    }

    // Only return if we got some useful data
    if (fallbackData.data.country_code || fallbackData.data.timezone) {
      debugLog("Browser fallback successful", fallbackData);
      return fallbackData;
    }

    return null;
  } catch (error) {
    console.error("Error in browser fallback:", error);
    return null;
  }
};

// Helper function to get country name from country code
const getCountryName = (countryCode) => {
  const countryNames = {
    US: "United States",
    GB: "United Kingdom",
    IN: "India",
    ZA: "South Africa",
    AU: "Australia",
    NZ: "New Zealand",
    CA: "Canada",
    DE: "Germany",
    FR: "France",
    IT: "Italy",
    ES: "Spain",
    BR: "Brazil",
    MX: "Mexico",
    JP: "Japan",
    CN: "China",
    KR: "South Korea",
    SG: "Singapore",
    AE: "United Arab Emirates",
    SA: "Saudi Arabia",
    EG: "Egypt",
    NG: "Nigeria",
    KE: "Kenya",
    GH: "Ghana",
    MA: "Morocco",
    TN: "Tunisia",
    DZ: "Algeria",
    LY: "Libya",
    SD: "Sudan",
    ET: "Ethiopia",
    UG: "Uganda",
    TZ: "Tanzania",
    ZW: "Zimbabwe",
    BW: "Botswana",
    NA: "Namibia",
    ZM: "Zambia",
    MW: "Malawi",
    MZ: "Mozambique",
    MG: "Madagascar",
    MU: "Mauritius",
    SC: "Seychelles",
    KM: "Comoros",
    DJ: "Djibouti",
    SO: "Somalia",
    ER: "Eritrea",
    SS: "South Sudan",
    CF: "Central African Republic",
    TD: "Chad",
    NE: "Niger",
    ML: "Mali",
    BF: "Burkina Faso",
    CI: "Ivory Coast",
    LR: "Liberia",
    SL: "Sierra Leone",
    GN: "Guinea",
    GW: "Guinea-Bissau",
    GM: "Gambia",
    SN: "Senegal",
    MR: "Mauritania",
    CV: "Cape Verde",
    ST: "São Tomé and Príncipe",
    GQ: "Equatorial Guinea",
    GA: "Gabon",
    CG: "Republic of the Congo",
    CD: "Democratic Republic of the Congo",
    AO: "Angola",
    CM: "Cameroon",
    BI: "Burundi",
    RW: "Rwanda",
    UG: "Uganda",
    TZ: "Tanzania",
    ZW: "Zimbabwe",
    BW: "Botswana",
    NA: "Namibia",
    ZM: "Zambia",
    MW: "Malawi",
    MZ: "Mozambique",
    MG: "Madagascar",
    MU: "Mauritius",
    SC: "Seychelles",
    KM: "Comoros",
    DJ: "Djibouti",
    SO: "Somalia",
    ER: "Eritrea",
    SS: "South Sudan",
    CF: "Central African Republic",
    TD: "Chad",
    NE: "Niger",
    ML: "Mali",
    BF: "Burkina Faso",
    CI: "Ivory Coast",
    LR: "Liberia",
    SL: "Sierra Leone",
    GN: "Guinea",
    GW: "Guinea-Bissau",
    GM: "Gambia",
    SN: "Senegal",
    MR: "Mauritania",
    CV: "Cape Verde",
    ST: "São Tomé and Príncipe",
    GQ: "Equatorial Guinea",
    GA: "Gabon",
    CG: "Republic of the Congo",
    CD: "Democratic Republic of the Congo",
    AO: "Angola",
    CM: "Cameroon",
    BI: "Burundi",
    RW: "Rwanda",
  };

  return countryNames[countryCode] || countryCode;
};

// export const preCreateCartsForEligibleRules = async () => {
//   const settings = getSessionValue("settingSession");
//   const partialPaymentEnabled = settings?.partialPaymentEnabled === true;
//   const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

//   if (partialPaymentFlowVersion !== 2) {
//     return; // Skip if partial payment is not enabled or not using flow version 2
//   }

//   try {
//     // Set loading state before starting cart creation
//     // useOtpStore.getState().setIsCreatingCarts(true);

//     // Use currentCartData from OTP store (current cart)
//     const otpStore = useOtpStore.getState();
//     let currentCart = otpStore.currentCartData;

//     // If currentCartData is not available, fetch it
//     if (!currentCart || !currentCart.items || currentCart.items.length === 0) {
//       debugLog("🔄 Current cart data not available, fetching from Shopify...");
//       try {
//         currentCart = await getCart(true);
//         if (currentCart) {
//           // Save to OTP store
//           otpStore.setCurrentCartData(currentCart);
//           debugLog("✅ Fetched and saved current cart data");
//         }
//       } catch (initError) {
//         console.warn("⚠️ Failed to fetch current cart:", initError);
//       }
//     }

//     // Wait for cart to be ready before creating carts
//     let cartReady = false;
//     let retryCount = 0;
//     const maxRetries = 20; // 20 * 200ms = 4 seconds max wait

//     while (!cartReady && retryCount < maxRetries) {
//       const currentCartData = useOtpStore.getState().currentCartData;
//       const cartItems = currentCartData?.items || [];

//       if (cartItems.length > 0) {
//         cartReady = true;
//         debugLog("✅ Cart is ready for cart creation");
//         break;
//       }

//       retryCount++;
//       debugLog(
//         `⏳ Waiting for cart to be ready... (attempt ${retryCount}/${maxRetries})`
//       );
//       await new Promise((resolve) => setTimeout(resolve, 200));
//     }

//     if (!cartReady) {
//       console.warn(
//         "⚠️ Cart not ready after waiting, proceeding anyway - carts may fail to create"
//       );
//     }

//     // Clear any cached results to ensure fresh cart creation
//     setSessionValue("partial_payment_cart_results", null);
//     debugLog(
//       "🟡 No cached results found, calling createCartsForEligibleRules..."
//     );

//     const cartResults = await createCartsForEligibleRules(true);

//     // Verify that carts were actually created
//     if (!cartResults || cartResults.length === 0) {
//       console.warn(
//         "⚠️ [preCreateCartsForEligibleRules] No cart results returned. This might indicate:",
//         {
//           eligibleRulesCount: PartialPaymentFilteredRules()?.length || 0,
//           cartItemsCount:
//             useOtpStore.getState()?.currentCartData?.items?.length || 0,
//           cartReady: !!useOtpStore.getState()?.currentCartData,
//         }
//       );
//     } else {
//       debugLog(
//         "✅ Pre-created cart results for eligible rules:",
//         cartResults.length,
//         "rules (with discount codes)"
//       );
//     }

//     // Ensure results are saved even if empty (to prevent infinite retries)
//     if (cartResults) {
//       setSessionValue("partial_payment_cart_results", cartResults);
//     }
//   } catch (error) {
//     console.error("❌ Error pre-creating cart results:", error);
//     // Set empty array to prevent infinite retries
//     setSessionValue("partial_payment_cart_results", null);
//     // Don't throw - allow flow to continue even if pre-creation fails
//   } finally {
//     // Clear loading state after cart creation completes (success or failure)
//     // useOtpStore.getState().setIsCreatingCarts(false);
//   }
// };

// Save discount summary in session storage
export const saveDiscountSummaryToSession = async (
  totalDiscount,
  discountName,
) => {
  try {
    const sanitizedTotal = isNaN(parseFloat(totalDiscount))
      ? 0
      : parseFloat(totalDiscount);
    const sanitizedName = (discountName || "").toString();

    setSessionValue("codk_discount_summary", {
      totalDiscount: sanitizedTotal,
      discountName: sanitizedName,
    });

    debugLog("Saved discount summary to session", {
      totalDiscount: sanitizedTotal,
      discountName: sanitizedName,
    });
  } catch (error) {
    console.error("Failed to save discount summary to session:", error);
  }
};

export const buildBuyerIdentityPayload = (selected, phone) => {
  const e164Phone = normalizePhoneE164(phone);
  return {
    email: selected.email,
    phone: e164Phone || null,
    countryCode: "IN",
    deliveryAddressPreferences: [
      {
        deliveryAddress: {
          address1: selected.address1,
          address2: selected.address2 || "",
          city: selected.city,
          province: normalizeProvince(selected.state),
          country: "India",
          zip: String(selected.zip || "").trim(),
          firstName: selected.first_name || null,
          lastName: selected.last_name || null,
          phone: e164Phone || null,
        },
      },
    ],
  };
};

const redirectToCheckout = () => {
  debugLog("🚀 Redirecting to checkout...");
  setTimeout(() => {
    window.location.href = "/checkout";
  }, 0);
};

export const handleCheckoutError = (error) => {
  console.error("❌ Error during checkout redirect:", error);
  sendErrorToAPI(error, "handleCheckoutError", "error", {
    operation: "handleCheckoutError",
  });

  // Reset loading state
  useOtpStore.getState().setOtpData({ isLoading: false });

  // Fail safe redirect
  setTimeout(() => {
    window.location.href = "/checkout";
  }, 0);
};

// export const redirectOtpStoreToCheckout = async function () {
//   try {
//     const { currentCartData } = useOtpStore.getState();
//     if (!currentCartData) {
//       throw new Error("Cart data is missing");
//     }

//     setSessionValue("codk-current-cart", currentCartData);
//     const settings = getSessionValue("settingSession");
//     const shopifyDomain = window.Shopify?.shop;
//     const storefrontToken = settings?.storeFrontToken;

//     if (!shopifyDomain || !storefrontToken) {
//       throw new Error("Shopify configuration not found");
//     }

//     // 1. Prepare the Lines (Items)
//     const lines = (currentCartData.items || []).map((item) => ({
//       merchandiseId: `gid://shopify/ProductVariant/${
//         item.variant_id || item.id
//       }`,
//       quantity: item.quantity || 1,
//       attributes: Object.entries(item.properties || {})
//         .filter(([key, value]) => value !== null && value !== undefined)
//         .map(([key, value]) => ({
//           key,
//           value: String(value),
//         })),
//     }));

//     // 2. Prepare the Buyer Identity (Address & Email)
//     let buyerIdentity = null;
//     if (currentCartData.buyerIdentity) {
//       const sourceIdentity = currentCartData.buyerIdentity;
//       const address =
//         sourceIdentity.deliveryAddressPreferences?.[0]?.deliveryAddress;

//       // Ensure phone number is in E.164 format (starts with +) for Shopify
//       const formatPhone = (phone) => {
//         if (!phone) return null;
//         let cleanPhone = String(phone).replace(/[^0-9+]/g, "");
//         if (!cleanPhone.startsWith("+")) {
//           cleanPhone = `+${cleanPhone}`;
//         }
//         return cleanPhone;
//       };

//       if (address) {
//         buyerIdentity = {
//           email: sourceIdentity.email,
//           phone: formatPhone(sourceIdentity.phone),
//           deliveryAddressPreferences: [
//             {
//               deliveryAddress: {
//                 address1: address.address1,
//                 address2: address.address2 || "",
//                 city: address.city,
//                 province: address.province || address.state,
//                 country: address.country || "India",
//                 zip: address.zip,
//                 firstName: address.firstName || address.first_name,
//                 lastName: address.lastName || address.last_name,
//                 phone: formatPhone(address.phone || sourceIdentity.phone),
//               },
//             },
//           ],
//         };
//       }
//     }

//     // 3. Prepare Cart Attributes & Note
//     const attributes = Object.entries({
//       _codkSessionId: getMachineId(),
//       ...(currentCartData.attributes || {}),
//     })
//       .filter(([key, value]) => value !== null && value !== undefined)
//       .map(([key, value]) => ({
//         key,
//         value: String(value),
//       }));

//     console.log("attributes", attributes);

//     // 4. The GraphQL Mutation
//     // const query = `
//     //   mutation cartCreate($input: CartInput!) {
//     //     cartCreate(input: $input) {
//     //       cart {
//     //         id
//     //         checkoutUrl
//     //       }
//     //       userErrors {
//     //         field
//     //         message
//     //       }
//     //     }
//     //   }
//     // `;

//     // 4. Updated GraphQL Mutation to include full cart details
//     const query = `
//           mutation cartCreate($input: CartInput!) {
//             cartCreate(input: $input) {
//               cart {
//                 id
//                 checkoutUrl
//                 totalQuantity

//                 # --- GLOBAL CART ATTRIBUTES ---
//                 # These are the attributes for the entire order
//                 attributes {
//                   key
//                   value
//                 }

//                 # --- LINE ITEMS AND THEIR ATTRIBUTES ---
//                 # This shows properties specific to each individual product
//                 lines(first: 50) {
//                   nodes {
//                     id
//                     quantity
//                     attributes {
//                       key
//                       value
//                     }
//                     merchandise {
//                       ... on ProductVariant {
//                         title
//                         sku
//                         price {
//                           amount
//                           currencyCode
//                         }
//                       }
//                     }
//                   }
//                 }

//                 # --- FINANCIALS ---
//                 cost {
//                   totalAmount { amount currencyCode }
//                   subtotalAmount { amount currencyCode }
//                 }

//                 # --- BUYER DATA ---
//                 buyerIdentity {
//                   email
//                   phone
//                   deliveryAddressPreferences {
//                     ... on MailingAddress {
//                       address1
//                       city
//                       province
//                       zip
//                       country
//                     }
//                   }
//                 }
//               }
//               userErrors {
//                 field
//                 message
//               }
//             }
//           }
//         `;

//     const variables = {
//       input: {
//         lines,
//         attributes,
//         note: currentCartData.note || "",
//         discountCodes: (currentCartData.discount_codes || []).map((dc) =>
//           typeof dc === "string" ? dc : dc.code
//         ),
//         ...(buyerIdentity && { buyerIdentity }),
//       },
//     };

//     debugLog("📡 Sending single GraphQL Cart Create request...", variables);

//     const client = createLightweightGraphQLClient(
//       shopifyDomain,
//       storefrontToken
//     );

//     const result = await client.mutateWithCacheClear(query, variables);
//     const cartCreated = result.data?.cartCreate?.cart;
//     const checkoutUrl = cartCreated?.checkoutUrl;
//     if (checkoutUrl) {
//       setSessionValue("codk-created-cart", result);
//       debugLog("🚀 Cart created successfully, redirecting to:", checkoutUrl);
//       window.location.href = checkoutUrl;
//     } else {
//       const errorMsg =
//         result.data?.cartCreate?.userErrors?.[0]?.message ||
//         "GraphQL Cart Creation Failed";
//       throw new Error(errorMsg);
//     }
//   } catch (error) {
//     handleCheckoutError(error);
//   }
// };

import { redirectOtpStoreToCheckout } from "../services/redirectOtpStoreToCheckoutService";

export { redirectOtpStoreToCheckout };

export const addCartAttributesWithOtpStore = (attributes) => {
  const otpStore = useOtpStore.getState();
  if (otpStore.patchCurrentCartData) {
    const currentAttributes = otpStore.currentCartData?.attributes || {};
    otpStore.patchCurrentCartData({
      attributes: {
        ...currentAttributes,
        ...attributes,
      },
    });
    debugLog("[OtpStore] Synced cart attributes patch", attributes);
  }
};

/**
 * Apply discount code in otpStore using patchCurrentCartData
 * @param {string} discountCode - Code to apply
 */
export const applyDiscountCodeToOtpStore = (discountCode) => {
  const otpStore = useOtpStore.getState();
  if (otpStore.patchCurrentCartData) {
    otpStore.patchCurrentCartData({
      discount_codes: [{ code: discountCode, applicable: true }],
    });
    debugLog("[OtpStore] Synced discount code application patch", discountCode);
  }
};

/**
 * Remove all discount codes in otpStore using patchCurrentCartData
 */
export const removeDiscountCodeFromOtpStore = () => {
  const otpStore = useOtpStore.getState();
  const currentCartData = otpStore.currentCartData;
  if (otpStore.patchCurrentCartData && currentCartData) {
    otpStore.patchCurrentCartData({
      discount_codes: [],
      total_discount: 0,
      total_price:
        (currentCartData.total_price || 0) +
        (currentCartData.total_discount || 0),
    });
    debugLog("[OtpStore] Synced discount code removal patch");
  }
};

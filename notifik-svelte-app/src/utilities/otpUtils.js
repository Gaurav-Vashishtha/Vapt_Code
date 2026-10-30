import { get } from "svelte/store";
import { getCart } from "../services/otpService.js";
import {
  getSessionValue,
  setSessionValue,
  removeSessionValue,
  setCustomerEmail,
  getSettings,
} from "../services/sessionService.js";
import {
  getMachineId as getMachineIdFromHelper,
  setLocalValue as setLocalValueFromHelper,
  getLocalValue as getLocalValueFromHelper,
  getShopDomain as getShopDomainFromHelper,
} from "../utils/helpers.js";
import { getCurrentStep as getCurrentStepFromUtils } from "../utils/stepUtils.js";
import { preCreateCartsForEligibleRules as preCreateCarts } from "../utils/partialPaymentUtils.js";
import { sendErrorToAPI } from "../services/errorReporter.js";
import { otpStore, otpStore as otpStoreActions } from "../stores/otpStore.js";

// Re-exports
export const getMachineId = () => getMachineIdFromHelper();
export {
  getSessionValue,
  setSessionValue,
  removeSessionValue,
  setCustomerEmail,
};
export const setLocalValue = (key, value) =>
  setLocalValueFromHelper(key, value);
export const getLocalValue = (key) => getLocalValueFromHelper(key);
export const getShopDomain = () => getShopDomainFromHelper();
export const getCurrentStep = () => getCurrentStepFromUtils();
export const preCreateCartsForEligibleRules = () => preCreateCarts();
// export const saveDiscountSummaryToSession = async (totalDiscount, discountName) =>
//   await saveDiscountSummaryToSessionPP(totalDiscount, discountName);

export const saveDiscountSummaryToSession = async (
  totalDiscount = 0,
  discountName = "",
) => {
  try {
    const sanitizedTotal = isNaN(parseFloat(String(totalDiscount)))
      ? 0
      : parseFloat(String(totalDiscount));
    const sanitizedName = (discountName || "").toString();

    setSessionValue("codk_discount_summary", {
      totalDiscount: sanitizedTotal,
      discountName: sanitizedName,
    });

    // ⚡ REMOVED: preCreateCartsForEligibleRules() call
    // Cart pre-creation is now handled by OrderSummaryCard component after cart is ready
    // This ensures cart is definitely ready before creating carts (avoids timing issues)
  } catch (error) {}
};
// Constants
const settings = getSessionValue("settingSession");
export const PLEASE_ENTER_VALID_PHONE_NUMBER =
  settings?.invalidPhoneText || "Please enter a valid phone number.";

// Functions
export const populateCallingCodeList = (text) => {
  return text;
};

export function generatePassword() {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const passwordLength = 8;
  let password = "";

  for (let i = 0; i < passwordLength; i++) {
    const randomIndex = Math.floor(Math.random() * chars.length);
    password += chars[randomIndex];
  }

  return password;
}

export async function getCartItemsOrRefetch() {
  try {
    let cartData = await getCart();

    if (cartData?.items?.length > 0) {
      return cartData.items;
    }

    // Retry with force fetch
    cartData = await getCart(true);

    if (cartData?.items?.length > 0) {
      return cartData.items;
    }

    return []; // Final fallback
  } catch (error) {
    return [];
  }
}

/**
 * Placeholder email when none provided: no-email-{phoneDigits}@gmail.com
 * @param {string} phone - Phone number (e.g. +91 6295529286 or 916295529286)
 * @returns {string|null} e.g. no-email-916295529286@gmail.com or null if no digits
 */
export function getNoEmailPlaceholder(phone) {
  const digits = (phone || "").replace(/\D/g, "");
  return digits ? `no-email-${digits}@gmail.com` : null;
}

/**
 * Whether an email is a generated placeholder (e.g. no-email-916...@gmail.com)
 * rather than a real address supplied by the customer.
 * @param {string} email
 * @returns {boolean}
 */
export function isNoEmailPlaceholder(email) {
  if (!email || typeof email !== "string") return false;
  return /^no-?email[-_]?\d*@/i.test(email.trim());
}

/**
 * Whether the email field is mandatory (pre_email_mandatory setting). When true,
 * a missing email is left blank instead of being filled with a placeholder.
 * @param {object} [settings] - Optional settings; falls back to session settings.
 * @returns {boolean}
 */
export function isPreEmailMandatory(settings) {
  const s = settings || getSettings() || {};
  return (
    s.preEmailMandatory === true ||
    s.preEmailMandatory === "true" ||
    s.pre_email_mandatory === true ||
    s.pre_email_mandatory === "true"
  );
}

/** Get email for buyer identity from session (customer-email or cod_king_customer_email). */
function getSessionEmailForBuyerIdentity() {
  const fromIframe =
    getSessionValue("customer-email") ||
    getSessionValue("cod_king_customer_email") ||
    null;
  if (fromIframe) return fromIframe;
  if (
    typeof window !== "undefined" &&
    window.parent &&
    window.parent !== window &&
    window.parent.sessionStorage
  ) {
    try {
      return (
        window.parent.sessionStorage.getItem("customer-email") ||
        window.parent.sessionStorage.getItem("cod_king_customer_email") ||
        null
      );
    } catch (_) {}
  }
  return null;
}

export const normalizePhoneForShopify = (phone) => {
  if (!phone || typeof phone !== "string") return phone;
  const digits = phone.replace(/\D/g, "");
  // India: 91 + 0 + 10 digits → 91 + 10 digits (E.164)
  if (digits.length === 13 && /^910\d{10}$/.test(digits)) {
    const e164 = "91" + digits.slice(3);
    return phone.startsWith("+") ? `+${e164}` : e164;
  }
  return phone;
};


/**
 * @param {object} selected - Selected address
 * @param {string} phone - Verified phone number
 * @param {string|null} [emailFromStore] - Email from otpStore (preferred over session)
 */
export const buildBuyerIdentityPayload = (
  selected,
  phone,
  emailFromStore = null,
) => {
  let email =
    selected?.email ||
    emailFromStore ||
    getSessionEmailForBuyerIdentity() ||
    "";
  email = String(email).trim();
  if (isPreEmailMandatory()) {
    if (!email || isNoEmailPlaceholder(email)) {
      email = null;
    }
  } else if (!email) {
    email = getNoEmailPlaceholder(phone) || null;
  }
  return {
    email,
    phone: phone,
    countryCode: "IN",
    deliveryAddressPreferences: [
      {
        deliveryAddress: {
          address1: selected.address1,
          address2: selected.address2 || "",
          city: selected.city,
          province: selected.state,
          country: "India",
          zip: selected.zip,
          firstName: selected.first_name || null,
          lastName: selected.last_name,
          phone: phone,
        },
      },
    ],
  };
};

export const getStorefrontCartId = (token) => {
  if (!token || typeof token !== "string") {
    return null;
  }
  return `gid://shopify/Cart/${token}`;
};

const IFRAME_ID = "codk-full-modal-svelte";

export const notifyParentToDestroyIframe = () => {
  if (
    typeof window === "undefined" ||
    !window.parent ||
    window.parent === window
  ) {
    return;
  }

  try {
    // Existing listeners close modal on this string message
    window.parent.postMessage("codk-close-modal", "*");
    // Give the parent a moment to run closeModal (which still references iframe)
    setTimeout(() => {
      window.parent.postMessage(
        { type: "CODK_DESTROY_IFRAME", iframeId: IFRAME_ID, source: "codk" },
        "*",
      );
    }, 250);
  } catch (error) {}
};

export const handleCheckoutError = (error) => {
  sendErrorToAPI(error, "handleCheckoutError", "error", {
    operation: "handleCheckoutError",
  });

  otpStoreActions.setOtpData({ isLoading: false });

  if (typeof window !== "undefined") {
    import("../utils/helpers.js")
      .then(({ redirectToCheckout }) => redirectToCheckout("/checkout"))
      .catch(() => {
        // Last-resort fallback if helpers fail to load
        notifyParentToDestroyIframe();
        window.top.location.href = "/checkout";
      });
  }
};

const patchCart = (patch) => {
  try {
    otpStore.patchCurrentCartData?.(patch);
  } catch (error) {}
};

export const addCartAttributesWithOtpStore = (attributes = {}) => {
  const state = get(otpStore);
  const currentAttributes = state.currentCartData?.attributes || {};
  patchCart({
    attributes: {
      ...currentAttributes,
      ...attributes,
    },
  });
};

export const applyDiscountCodeToOtpStore = (discountCode) => {
  if (!discountCode) return;
  patchCart({
    discount_codes: [{ code: discountCode, applicable: true }],
  });
};

export const removeDiscountCodeFromOtpStore = () => {
  const state = get(otpStore);
  const currentCartData = state.currentCartData;
  if (!currentCartData) return;
  patchCart({
    discount_codes: [],
    total_discount: 0,
    total_price:
      (currentCartData.total_price || 0) +
      (currentCartData.total_discount || 0),
  });
};

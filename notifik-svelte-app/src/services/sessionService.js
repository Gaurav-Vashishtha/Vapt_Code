import { mapSettingsToCamel } from "../utils/settingsMapper.js";
import { getShopDomain as getShopDomainFromHelper } from "../utils/helpers.js";

export const getShopDomain = () => getShopDomainFromHelper();

/**
 * Session Storage Service
 *
 * Centralized session storage management
 * Matches notifik-js-app session storage patterns
 */

const DEBUG_MODE = true;
const stringifyValue = (value) =>
  typeof value === "string" ? value : JSON.stringify(value);

const getParentSessionStorage = () => {
  if (
    typeof window !== "undefined" &&
    window.parent &&
    window.parent !== window &&
    window.parent.sessionStorage
  ) {
    return window.parent.sessionStorage;
  }
  return null;
};

/**
 * Get value from sessionStorage
 * @param {string} key - Storage key
 * @param {any} defaultValue - Default value if key doesn't exist
 * @returns {any} Stored value or default
 */
export const getSessionValue = (key, defaultValue = null) => {
  if (typeof window === "undefined" || typeof sessionStorage === "undefined") {
    return defaultValue;
  }

  try {
    const parentStorage = getParentSessionStorage();

    const readValue = (storage) => {
      if (!storage) return null;
      const stored = storage.getItem(key);
      if (stored === null) {
        return null;
      }
      try {
        return JSON.parse(stored);
      } catch (e) {
        return stored;
      }
    };

    const parentValue = readValue(parentStorage);
    if (parentValue !== null) {
      return parentValue;
    }

    const iframeValue = readValue(sessionStorage);
    return iframeValue !== null ? iframeValue : defaultValue;
  } catch (error) {

    return defaultValue;
  }
};

/**
 * Set value in sessionStorage
 * @param {string} key - Storage key
 * @param {any} value - Value to store (will be JSON stringified)
 * @returns {boolean} Success status
 */
export const setSessionValue = (key, value) => {
  if (typeof window === "undefined" || typeof sessionStorage === "undefined") {
    return false;
  }

  let success = false;
  try {
    const stringValue = stringifyValue(value);
    sessionStorage.setItem(key, stringValue);
    success = true;
  } catch (error) {

  }

  try {
    const parentStorage = getParentSessionStorage();
    if (parentStorage) {
      parentStorage.setItem(key, stringifyValue(value));
      success = true;
    }
  } catch (error) {

  }

  return success;
};

/**
 * Clear value from sessionStorage
 * @param {string} key - Storage key
 * @returns {boolean} Success status
 */
export const clearSessionValue = (key) => {
  if (typeof window === "undefined" || typeof sessionStorage === "undefined") {
    return false;
  }

  let success = false;
  try {
    sessionStorage.removeItem(key);
    success = true;
  } catch (error) {

  }

  try {
    const parentStorage = getParentSessionStorage();
    if (parentStorage) {
      parentStorage.removeItem(key);
      success = true;
    }
  } catch (error) {

  }

  if (success) {
  }
  return success;
};

// Backwards compatibility alias (React app uses removeSessionValue)
export const removeSessionValue = clearSessionValue;

/**
 * Set OTP verification flag
 * @param {string} phoneNumber - Verified phone number
 * @param {boolean} isVerified - Verification status
 * @returns {boolean} Success status
 */
export const setOTPVerified = (phoneNumber, isVerified = true) => {
  const verifiedData = {
    otpVerifiedPhoneNumber: phoneNumber,
    isOTPVerified: isVerified,
    verifiedAt: new Date().toISOString(),
  };
  return setSessionValue("verifiedNumberData", verifiedData);
};

/**
 * Clear OTP verification flag
 * @returns {boolean} Success status
 */
export const clearOTPVerified = () => {
  return clearSessionValue("verifiedNumberData");
};

const OTP_SKIP_KEY = "codk_user_skipped_otp";
const LEGACY_OTP_SKIP_KEY = "cod_king_skip_otp";

/**
 * Set skip OTP flag
 * @param {boolean} skipped - Skip status
 * @returns {boolean} Success status
 */
export const setOTPSkipped = (skipped = true) => {
  const latest = setSessionValue(OTP_SKIP_KEY, skipped);
  // Clean up legacy key to avoid stale data
  clearSessionValue(LEGACY_OTP_SKIP_KEY);
  return latest;
};

/**
 * Get settings from sessionStorage
 * @returns {Object|null} Settings object or null
 */
export const getSettings = () => {
  const settings = getSessionValue("settingSession", null);
  if (!settings) return null;
  return mapSettingsToCamel(settings);
};

/**
 * Set settings in sessionStorage
 * @param {Object} settings - Settings object
 * @returns {boolean} Success status
 */
export const setSettings = (settings) => {
  if (!settings) {
    return setSessionValue("settingSession", settings);
  }
  const normalizedSettings = mapSettingsToCamel(settings);
  return setSessionValue("settingSession", normalizedSettings);
};

/**
 * Feature flag: "Optimized Buy Now" (instant popup / optimistic summary /
 * cart-free OTP step / parallel payment rules). Default OFF — when off the
 * widget behaves exactly as before. Toggled from the app settings admin
 * (setting: optimized_buy_now). Reads settingSession directly and accepts
 * either snake_case or camelCase so it works regardless of mapping state.
 * @returns {boolean}
 */
export const isOptimizedBuyNowEnabled = () => {
  try {
    const s = getSessionValue("settingSession", null) || {};
    const v = s.optimizedBuyNow ?? s.optimized_buy_now;
    return v === true || v === "true";
  } catch {
    return false;
  }
};

/**
 * Escape hatch for stores that build the Buy Now cart themselves: with
 * `window._codkBuyNowSkip = true` the initial Buy Now stays read-only — no
 * clear.js, add.js or update.js, just cart.js — in both the optimized and the
 * normal flow. Read from the iframe and from the storefront that hosts it,
 * since the theme sets it on the parent window.
 */
export const isBuyNowCartSkipEnabled = () => {
  const isOn = (value) => value === true || value === "true";
  try {
    if (typeof window === "undefined") return false;
    if (isOn(window._codkBuyNowSkip)) return true;
    const parent = window.parent;
    if (parent && parent !== window && isOn(parent._codkBuyNowSkip)) return true;
  } catch {
    // cross-origin parent — treat as not set
  }
  return false;
};

/**
 * Get shipping addresses from sessionStorage
 * @returns {Array} Array of shipping addresses
 */
export const getShippingAddresses = () => {
  return getSessionValue("shipping_addresses", []);
};

const repersistFromSession = () => {
  if (typeof window === "undefined") return;
  import("./persistentSigninStorage.js")
    .then(({ savePersistentData, buildPersistentPayload, isPersistentSigninEnabled }) => {
      const settings = getSessionValue("settingSession");
      if (!isPersistentSigninEnabled(settings)) return null;
      const payload = buildPersistentPayload({
        verifiedNumberData: getSessionValue("verifiedNumberData"),
        preOrderOtpResponse: getSessionValue("preOrderOtpResponse"),
        shipping_addresses: getSessionValue("shipping_addresses"),
        customer_email: getSessionValue("customer-email"),
        customer_id: getSessionValue("customer-id"),
        cod_king_selected_address: getSessionValue("cod_king_selected_address"),
      });
      return savePersistentData(null, settings, payload);
    })
    .catch(() => {});
};

/**
 * Set shipping addresses in sessionStorage
 * @param {Array} addresses - Array of shipping addresses
 * @returns {boolean} Success status
 */
export const setShippingAddresses = (addresses) => {
  const result = setSessionValue("shipping_addresses", addresses);

  const preOrderOtpResponse = getSessionValue("preOrderOtpResponse");
  if (preOrderOtpResponse && typeof preOrderOtpResponse === "object") {
    setSessionValue("preOrderOtpResponse", {
      ...preOrderOtpResponse,
      shippingAddress: addresses,
    });
  }

  repersistFromSession();
  return result;
};

/**
 * Get selected address ID
 * @returns {string|null} Selected address ID or null
 */
export const getSelectedAddressId = () => {
  const selectedAddress = getSessionValue("cod_king_selected_address");
  return selectedAddress?.id || null;
};

/**
 * Set selected address
 * @param {Object} address - Address object
 * @returns {boolean} Success status
 */
export const setSelectedAddress = (address) => {
  const result = setSessionValue("cod_king_selected_address", address);
  try {
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("codk-address-updated"));
    }
  } catch (_) {}
  repersistFromSession();
  return result;
};

/**
 * Get customer email
 * @returns {string|null} Customer email or null
 *
 * ⚡ CRITICAL: Checks BOTH iframe and parent window sessionStorage
 * React app stores in parent window's sessionStorage, so we need to check there first
 */
export const getCustomerEmail = () => {
  // First check parent window's sessionStorage (where React app stores it)
  if (
    typeof window !== "undefined" &&
    window.parent &&
    window.parent.sessionStorage
  ) {
    try {
      const parentEmail =
        window.parent.sessionStorage.getItem("customer-email");

      if (parentEmail) {
        return parentEmail;
      } else {
      }
    } catch (error) {

    }
  } else {
  }

  // Fallback to iframe sessionStorage
  const iframeEmail = getSessionValue("customer-email", null);

  if (iframeEmail) {
  } else {
  }

  return iframeEmail;
};

/**
 * Set customer email in session (iframe + parent) and localStorage so it persists
 * across tab close and is available for buyer identity / order confirmation.
 * Uses keys: customer-email, cod_king_customer_email.
 *
 * @param {string} email - Customer email
 * @returns {boolean} Success status
 */
export const setCustomerEmail = (email) => {
  const value = email && String(email).trim();
  if (!value) return false;

  const keys = ["customer-email", "cod_king_customer_email"];

  // Session: iframe + parent (matching React app)
  let sessionSaved = false;
  for (const key of keys) {
    if (setSessionValue(key, value)) sessionSaved = true;
  }
  const parentStorage = getParentSessionStorage();
  if (parentStorage) {
    try {
      for (const key of keys) parentStorage.setItem(key, value);
      sessionSaved = true;
    } catch (_e) {}
  }

  // localStorage: persist across tab close so email is available after reload
  let localSaved = false;
  if (typeof localStorage !== "undefined") {
    try {
      for (const key of keys) localStorage.setItem(key, value);
      localSaved = true;
    } catch (_e) {}
  }

  return sessionSaved || localSaved;
};

/**
 * Set pre-order OTP response
 * @param {Object} response - OTP response object
 * @returns {boolean} Success status
 */
export const setPreOrderOtpResponse = (response) => {
  return setSessionValue("preOrderOtpResponse", response);
};

/**
 * Set address completion flag
 * @param {boolean} completed - Completion status
 * @returns {boolean} Success status
 */
export const setAddressCompleted = (completed = true) => {
  return setSessionValue("isPrefilledAddressCompleted", completed);
};

/**
 * Reset cart revert completion flag
 */
// export const resetCartRevertIsComplete = () => {
//   removeSessionValue("codk_cart_revert_is_complete");
// };

/**
 * Reset order summary completion flag
 */
export const resetOrderSummaryComplete = () => {
  removeSessionValue("codk_order_summary_complete");
};

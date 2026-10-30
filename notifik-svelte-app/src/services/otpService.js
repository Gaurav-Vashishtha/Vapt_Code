import {
  fetchIpAddress,
  sendCode as apiSendCode,
  verifyCode as apiVerifyCode,
  ssoCheck as apiSsoCheck,
  getRouteUrl,
  fetchPartialRuleSets as apiFetchPartialRuleSets,
  fetchRtoDecision as apiFetchRtoDecision,
} from "./api.js";
import {
  getMachineId,
  simplifyCartItems,
  getShopifyRootPath,
  getLocalValue,
  getShopDomain,
} from "../utils/helpers.js";
import { cartFetch } from "../utils/shopifyCartApi.js";
import {
  getSessionValue,
  setSessionValue,
  removeSessionValue,
  setCustomerEmail,
} from "./sessionService.js";
import { sendErrorToAPI } from "./errorReporter.js";
import { clearCart } from "./cartService.js";
import { stripExcludedFromCart } from "./couponCart.js";
import { emitShopifyVisitorIdentify } from "../utils/shopifyVisitor.js";
import { get } from "svelte/store";
import { otpStore } from "../stores/otpStore.js";

const FAILED_TO_VERIFY_OTP = "Failed to verify OTP";

export const IS_BUY_NOW_BUTTON = () =>
  (typeof window !== "undefined" &&
    (window.sessionStorage?.getItem("cod_king_isBuyNow") === "true" ||
      (window.parent &&
        window.parent !== window &&
        window.parent.sessionStorage?.getItem("cod_king_isBuyNow") ===
          "true"))) ||
  false;

export const fetchMachineDetails = async () => {
  try {
    const cachedMachineDetails = getSessionValue("machineDetails");
    if (cachedMachineDetails) {
      return cachedMachineDetails;
    }

    const ip = await fetchIpAddress();
    const response = {
      data: {
        ip: ip,
        country: getLocalValue("defaultCountry") || "IN",
      },
    };

    setSessionValue("machineDetails", response);
    return response;
  } catch (error) {
    sendErrorToAPI(error, "url_fetchMachineDetails", "error");
    throw error;
  }
};

export const sendOtpRequest = async ({
  countryCode,
  phoneNumber,
  countryCallingCode,
  ipAddress,
  deviceId,
  shop,
  mode = "SMS",
  device_type = "mobile",
  cartDetails,
}) => {
  try {
    const cartFilteredData = simplifyCartItems(cartDetails);

    return await apiSendCode({
      country_code: countryCode,
      phone: phoneNumber,
      ip_address: ipAddress || "",
      device_id: deviceId,
      shop: shop || getShopDomain(),
      mode: mode,
      cart_details: cartFilteredData,
    });
  } catch (error) {
    sendErrorToAPI(error, "otpService.sendOtpRequest", "error");
    throw error;
  }
};

/**
 * Builds a failure response object so callers always get a consistent shape.
 */
const failureResponse = (status, statusText, error) => ({
  ok: false,
  status: status ?? 0,
  statusText: statusText ?? error?.message ?? "Unknown error",
  error: error ?? null,
  json: () => Promise.resolve(null),
  text: () => Promise.resolve(""),
  responseText: "",
});

// export const executePost = (data, retryCount = 0) => {
//   const MAX_RETRIES = 3;
//   const root = getShopifyRootPath();
//   const url = `${root}cart/update.js`;

//   return new Promise((resolve) => {
//     const xhr = new XMLHttpRequest();
//     xhr.open("POST", url, true);
//     xhr.setRequestHeader("Content-Type", "application/json");
//     xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest");
//     xhr.setRequestHeader(
//       "Cache-Control",
//       "no-cache, no-store, must-revalidate",
//     );
//     xhr.setRequestHeader("Pragma", "no-cache");

//     xhr.onload = function () {
//       if (xhr.status >= 200 && xhr.status < 300) {
//         let parsedData = null;
//         try {
//           parsedData = xhr.responseText ? JSON.parse(xhr.responseText) : {};
//         } catch (e) {
//           parsedData = {};
//         }
//         resolve({
//           ok: true,
//           status: xhr.status,
//           statusText: xhr.statusText,
//           json: () => Promise.resolve(parsedData),
//           text: () => Promise.resolve(xhr.responseText),
//           responseText: xhr.responseText,
//           ...parsedData,
//         });
//         return;
//       }
//       const err = new Error(
//         `Error updating cart: ${xhr.statusText || xhr.status}`,
//       );
//       if (
//         retryCount < MAX_RETRIES &&
//         (xhr.status === 409 || xhr.status === 429)
//       ) {
//         setTimeout(
//           () => {
//             executePost(data, retryCount + 1).then(resolve);
//           },
//           250 * (retryCount + 1),
//         );
//       } else {
//         sendErrorToAPI(err, "executePost.updateCart", "error", {
//           status: xhr.status,
//           statusText: xhr.statusText,
//         });
//         resolve(failureResponse(xhr.status, xhr.statusText, err));
//       }
//     };

//     xhr.onerror = function () {
//       const err = new Error("Network error updating cart");
//       if (retryCount < MAX_RETRIES) {
//         setTimeout(
//           () => {
//             executePost(data, retryCount + 1).then(resolve);
//           },
//           250 * (retryCount + 1),
//         );
//       } else {
//         sendErrorToAPI(err, "executePost.updateCart", "error");
//         resolve(failureResponse(0, err.message, err));
//       }
//     };

//     xhr.ontimeout = function () {
//       const err = new Error("Timeout updating cart");
//       if (retryCount < MAX_RETRIES) {
//         setTimeout(
//           () => {
//             executePost(data, retryCount + 1).then(resolve);
//           },
//           250 * (retryCount + 1),
//         );
//       } else {
//         sendErrorToAPI(err, "executePost.updateCart", "error");
//         resolve(failureResponse(0, err.message, err));
//       }
//     };

//     xhr.timeout = 10000;
//     xhr.send(JSON.stringify(data));
//   });
// };

export const executePost = async (data, retryCount = 0) => {
  const MAX_RETRIES = 3;
  const root = getShopifyRootPath();
  const url = `${root}cart/update.js`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "Cache-Control": "no-cache, no-store, must-revalidate",
        Pragma: "no-cache",
      },
      body: JSON.stringify(data),

      // 🔥 Critical for reload/navigation cases
      keepalive: false,

      // Needed for timeout handling
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    let parsedData = {};
    try {
      parsedData = await response.clone().json();
    } catch (e) {
      parsedData = {};
    }

    if (response.ok) {
      return {
        ok: true,
        status: response.status,
        statusText: response.statusText,
        json: () => Promise.resolve(parsedData),
        text: () => response.text(),
        ...parsedData,
      };
    }

    // Retry only for 409 / 429
    if (
      retryCount < MAX_RETRIES &&
      (response.status === 409 || response.status === 429)
    ) {
      await new Promise((r) => setTimeout(r, 250 * (retryCount + 1)));
      return executePost(data, retryCount + 1);
    }

    const err = new Error(
      `Error updating cart: ${response.statusText || response.status}`,
    );

    sendErrorToAPI(err, "executePost.updateCart", "error", {
      status: response.status,
      statusText: response.statusText,
    });

    return failureResponse(response.status, response.statusText, err);
  } catch (error) {
    clearTimeout(timeoutId);

    // Retry on network failure
    if (retryCount < MAX_RETRIES) {
      await new Promise((r) => setTimeout(r, 250 * (retryCount + 1)));
      return executePost(data, retryCount + 1);
    }

    sendErrorToAPI(error, "executePost.updateCart", "error");

    return failureResponse(0, error.message, error);
  }
};
export const getCurrentStep = async () => {
  try {
    const { getCurrentStep } = await import("../utils/stepUtils.js");
    return getCurrentStep();
  } catch (e) {
    return 2;
  }
};

const addLineAttribute = async (
  codkCartOtpVerifiedPhoneNo,
  isCodkOtpVerifed,
  attrsResp,
  widgetState,
  opts = {},
) => {
  const settings = getSessionValue("settingSession") || {};
  const { setStep, setIsLoading, setError } = widgetState;

  const lineIndex =
    attrsResp.items?.findIndex((item) => item.variant_id || item.id) + 1 || 1;
  const quantity = attrsResp.items?.[0]?.quantity || 1;
  const existingProps = attrsResp.items?.[0]?.properties || {};

  const payload = {
    line: lineIndex,
    quantity: quantity,
    properties: {
      ...existingProps,
      _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
      _codkSessionId: getMachineId(),
    },
  };

  try {
    setIsLoading(true);
    const root = getShopifyRootPath();
    const response = await fetch(`${root}cart/change.js`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorData = await response.json();
      setError("Failed to update cart line attribute");
      throw new Error(errorData.message || "Failed cart line update");
    }

    const data = await response.json();

    const emailFromResponse =
      getSessionValue("preOrderOtpResponse")?.email ||
      getSessionValue("customer-email");
    const verifiedNumber = {
      otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
      isOTPVerified: true,
      countryCode: "IN",
      ...(emailFromResponse && { email: String(emailFromResponse).trim() }),
    };
    setSessionValue("verifiedNumberData", verifiedNumber);

    const emailForVisitor =
      verifiedNumber.email ||
      getSessionValue("customer-email") ||
      getSessionValue("preOrderOtpResponse")?.email;
    emitShopifyVisitorIdentify({
      phone: codkCartOtpVerifiedPhoneNo,
      email: emailForVisitor,
      countryCallingCode: opts?.countryCallingCode,
    });

    const nextStep = await getCurrentStep();
    setStep(nextStep);
    setIsLoading(false);

    try {
      const {
        savePersistentData,
        buildPersistentPayload,
        isPersistentSigninEnabled,
      } = await import("./persistentSigninStorage.js");
      const settings = getSessionValue("settingSession");
      const shopDomain = getShopDomain();
      if (isPersistentSigninEnabled(settings) && shopDomain) {
        const payload = buildPersistentPayload({
          verifiedNumberData: verifiedNumber,
          preOrderOtpResponse: getSessionValue("preOrderOtpResponse"),
          shipping_addresses: getSessionValue("shipping_addresses"),
          customer_email: getSessionValue("customer-email"),
          customer_id: getSessionValue("customer-id"),
          cod_king_selected_address: getSessionValue(
            "cod_king_selected_address",
          ),
        });
        await savePersistentData(shopDomain, settings, payload);
      }
    } catch (_e) {}

    return { success: true, data };
  } catch (error) {
    setError("Network error while adding line attribute");
    setIsLoading(false);
    sendErrorToAPI(error, "addLineAttribute.change", "error");
    return { success: false, error: "Network error" };
  }
};

const addCartAttribute = async (
  codkCartOtpVerifiedPhoneNo,
  isCodkOtpVerifed,
  widgetState,
  opts = {},
) => {
  const attributes = {
    _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
    _codkSessionId: getMachineId(),
  };

  try {
    const response = await executePost({ attributes });
    const responseData = await response.json();
    return await addLineAttribute(
      codkCartOtpVerifiedPhoneNo,
      isCodkOtpVerifed,
      responseData,
      widgetState,
      opts,
    );
  } catch (error) {
    widgetState?.setIsLoading?.(false);
    widgetState?.setError?.("Failed to update cart attributes");
    throw error;
  }
};

export const verifyOtpRequest = async ({
  countryCode,
  countryCallingCode,
  phoneNumber,
  ipAddress,
  deviceId,
  shop, // Added shop
  otp,
  mode,
  widgetState,
}) => {
  try {
    const data = await apiVerifyCode({
      country_code: countryCode,
      phone: phoneNumber,
      ip_address: ipAddress || "",
      device_id: deviceId,
      shop: shop || getShopDomain(), // Use passed shop or fallback
      otp,
      mode,
    });

    setSessionValue("preOrderOtpResponse", data);

    if (data?.sso_session_token) {
      setSessionValue("ssoValidatedToken", data.sso_session_token);
    }

    if (data?.email && String(data.email).trim()) {
      setCustomerEmail(String(data.email).trim());
      otpStore.setVerifiedEmail(String(data.email).trim());
    }

    if (data.verification) {
      return addCartAttribute(phoneNumber, data.verification, widgetState, {
        countryCallingCode,
      });
    } else {
      throw new Error("OTP verification failed"); // Trigger catch block
    }
  } catch (error) {
    widgetState.setIsLoading(false);
    widgetState.setError(FAILED_TO_VERIFY_OTP);
    widgetState.setShowServerErrorText(true);

    error.payload = {
      request: { phone: phoneNumber, otp, mode },
    };
    sendErrorToAPI(error, "otpService.verifyOtpRequest", "error");
    throw error;
  }
};

/**
 * Attempt SSO auto-login by checking if a valid codk_sso cookie exists.
 * If valid, sets session data and cart attributes as if OTP was verified.
 * Returns { success: true, phone } or { success: false }.
 */
export const attemptSsoAutoLogin = async (widgetState) => {
  console.log("[SSO] Attempting auto-login...");
  try {
    const shop = getShopDomain();
    if (!shop) {
      console.log("[SSO] No shop domain found, skipping");
      return { success: false };
    }

    const result = await apiSsoCheck(shop);

    if (!result.valid) {
      console.log(
        "[SSO] No valid session found, reason:",
        result.reason || "unknown",
      );
      return { success: false };
    }

    console.log("[SSO] Valid session found for phone:", result.phone);

    // Store OTP response in session (same shape as verify response)
    const ssoOtpResponse = {
      verification: true,
      status: "success",
      sso_auto_login: true,
      ...(result.sso_session_token && {
        sso_session_token: result.sso_session_token,
      }),
      ...(result.shippingAddress && {
        shippingAddress: result.shippingAddress,
      }),
      ...(result.customerLogin && { customerLogin: result.customerLogin }),
    };
    setSessionValue("preOrderOtpResponse", ssoOtpResponse);

    if (result.customerLogin?.email) {
      setCustomerEmail(String(result.customerLogin.email).trim());
    }

    // Set shipping addresses if returned
    if (result.shippingAddress && result.shippingAddress.length > 0) {
      setSessionValue("shipping_addresses", result.shippingAddress);
      console.log(
        "[SSO] Pre-filled",
        result.shippingAddress.length,
        "shipping addresses",
      );
    }

    // Set cart attributes (same as normal OTP verify flow)
    const phone = result.phone;
    console.log("[SSO] Setting cart attributes for phone:", phone);
    await addCartAttribute(phone, true, widgetState);

    console.log("[SSO] Auto-login complete for phone:", phone);
    return { success: true, phone, countryCode: result.country_code };
  } catch (error) {
    console.log("[SSO] Auto-login failed:", error.message);
    sendErrorToAPI(error, "otpService.attemptSsoAutoLogin", "warn");
    return { success: false };
  }
};

let cacheHitCount = 0;
let shopifyCallCount = 0;

const updateOtpStoreCartData = async (cartData, { force = false } = {}) => {
  if (!cartData) return;

  try {
    const { otpStore } = await import("../stores/otpStore.js");
    if (!otpStore?.setCurrentCartData) {
      return;
    }

    const currentCartData = get(otpStore)?.currentCartData;
    const isSameToken = currentCartData?.token === cartData?.token;
    const isSameItemCount =
      (currentCartData?.items?.length || 0) === (cartData?.items?.length || 0);

    if (force || !isSameToken || !isSameItemCount) {
      otpStore.setCurrentCartData(cartData);
    }
  } catch (_error) {}
};

const readCartFromOtpStore = async () => {
  try {
    const { otpStore } = await import("../stores/otpStore.js");
    const storeSnapshot = get(otpStore);
    return storeSnapshot?.currentCartData || null;
  } catch (_error) {
    return null;
  }
};

const resolveCachedCart = async (sessionKey) => {
  const storeCart = await readCartFromOtpStore();
  if (storeCart) {
    cacheHitCount++;
    return storeCart;
  }

  const cachedCart = getSessionValue(sessionKey);
  if (cachedCart) {
    cacheHitCount++;
    await updateOtpStoreCartData(cachedCart);
    return cachedCart;
  }

  return null;
};

const triggerCartSyncIfNeeded = async (cartData, cachedCart) => {
  try {
    const { updateCartIfNeeded } = await import("./cartService.js");
    if (typeof updateCartIfNeeded === "function") {
      await updateCartIfNeeded(cartData, cachedCart);
    }
  } catch (_error) {}
};

const needsOtpAttributeBackfill = (cartData) => {
  try {
    const verifiedData = getSessionValue("verifiedNumberData");
    const isOtpVerified = !!verifiedData?.isOTPVerified;
    const verifiedPhone = verifiedData?.otpVerifiedPhoneNumber;
    if (!isOtpVerified || !verifiedPhone) return false;

    const attrs = cartData?.attributes || {};
    const hasOtpPhone =
      attrs._otpVerifiedPhoneNumber != null &&
      String(attrs._otpVerifiedPhoneNumber).trim() !== "";
    const hasSessionId =
      attrs._codkSessionId != null &&
      String(attrs._codkSessionId).trim() !== "";

    return !(hasOtpPhone && hasSessionId);
  } catch (_e) {
    return false;
  }
};

export const backfillOtpAttributesToCart = async (cartData) => {
  if (!needsOtpAttributeBackfill(cartData)) return cartData;

  const verifiedData = getSessionValue("verifiedNumberData");
  const verifiedPhone = verifiedData?.otpVerifiedPhoneNumber;
  if (!verifiedPhone) return cartData;

  const existingAttrs = cartData?.attributes || {};
  const payload = {
    attributes: {
      ...existingAttrs,
      _otpVerifiedPhoneNumber: verifiedPhone,
      _codkSessionId: getMachineId(),
    },
  };

  try {
    const resp = await executePost(payload);
    if (!resp?.ok) return cartData;

    // Refetch once to return authoritative cart with updated attributes
    const refreshResp = await cartFetch(`cart.js?v=${new Date().getTime()}`, {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });
    if (!refreshResp.ok) return cartData;
    return await refreshResp.json();
  } catch (_e) {
    return cartData;
  }
};

/**
 * Startup-safe sync: ensures OTP cart attributes exist even if popup flow is muted
 * and no screen calls getCart(). Intended for app bootstrap/page-load hooks.
 */
export const ensureOtpCartAttributesSyncedOnStartup = async () => {
  try {
    const verifiedData = getSessionValue("verifiedNumberData");
    if (!verifiedData?.isOTPVerified || !verifiedData?.otpVerifiedPhoneNumber) {
      return { skipped: true, reason: "otp_not_verified_in_session" };
    }

    const response = await cartFetch(`cart.js?v=${new Date().getTime()}`, {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });
    if (!response.ok) return { skipped: true, reason: "cart_fetch_failed" };

    const cartData = await response.json();
    const updatedCart = await backfillOtpAttributesToCart(cartData);

    setSessionValue("shopify_cart", updatedCart);
    await updateOtpStoreCartData(updatedCart, { force: true });
    return { skipped: false, synced: true };
  } catch (_e) {
    return { skipped: true, reason: "startup_sync_error" };
  }
};

export async function getCart(init = false, retryCount = 0) {
  const MAX_RETRIES = 5;
  const SESSION_KEY = "shopify_cart";

  if (!init) {
    const cachedCart = await resolveCachedCart(SESSION_KEY);
    return cachedCart || (await getCart(true, retryCount));
  }

  try {
    shopifyCallCount++;
    const response = await cartFetch(`cart.js?v=${new Date().getTime()}`, {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });

    if (!response.ok) {
      throw new Error(`Fetch failed: ${response.status}`);
    }

    let cartData = await response.json();
    cartData = await backfillOtpAttributesToCart(cartData);
    const cachedCart = getSessionValue(SESSION_KEY);

    // Strip any coupon whose exception product is in the cart BEFORE the store
    // (and UI) sees it, so an excluded coupon never renders in its applied state
    // — the load gate waits for update.js to clear it.
    const cleaned = await stripExcludedFromCart(cartData);
    if (cleaned) cartData = await backfillOtpAttributesToCart(cleaned);

    await triggerCartSyncIfNeeded(cartData, cachedCart);
    setSessionValue(SESSION_KEY, cartData);
    await updateOtpStoreCartData(cartData, { force: true });

    return cartData;
  } catch (error) {
    if (retryCount + 1 < MAX_RETRIES) {
      return await getCart(true, retryCount + 1);
    }
    return null;
  }
}

export const createCustomerLogin = async ({
  shopifyCustomerId,
  email,
  password,
  phone,
  shopifyDomain,
}) => {
  try {
    const routeUrl = getRouteUrl();
    const response = await fetch(
      `${routeUrl}/order_confirmations/create_customer_login`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          shopifyCustomerId,
          email,
          password,
          phone,
          shopifyDomain,
        }),
      },
    );

    if (response.ok) {
      return await response.json();
    } else {
      const err = new Error("Error creating customer login.");
      throw err;
    }
  } catch (error) {
    sendErrorToAPI(error, "createCustomerLogin", "error");
    throw error;
  }
};

export const createPartialCart = async (
  shopifyDomain,
  cartRuleId,
  inputCart = [],
) => {
  const routeUrl = getRouteUrl();
  const url = `${routeUrl}/order_confirmations/partial_cart`;
  const headers = {
    "Content-Type": "application/json",
  };

  /** @type {any[]} */
  let normalizedInputCart = [];
  try {
    if (Array.isArray(inputCart)) {
      normalizedInputCart = inputCart;
    } else if (typeof inputCart === "string") {
      const parsed = JSON.parse(inputCart);
      normalizedInputCart = Array.isArray(parsed) ? parsed : [];
    } else if (inputCart && typeof inputCart === "object") {
      normalizedInputCart = [inputCart];
    }
  } catch {
    normalizedInputCart = [];
  }

  const payload = {
    _codkSessionId: getMachineId(),
    shopifyDomain,
    cartRuleId,
    inputCart: normalizedInputCart,
  };

  try {
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const error = new Error(
        `createPartialCart failed with status ${response.status}`,
      );
      throw error;
    }

    const data = await response.json();

    return {
      success: true,
      data: data?.response || data,
    };
  } catch (error) {
    sendErrorToAPI(error, "createPartialCart", "error", {
      operation: "createPartialCart",
      shopifyDomain,
      cartRuleId,
    });
    return {
      success: false,
      error: error.message,
    };
  }
};

export const fetchPartialRuleSets = async (shopifyDomain) => {
  try {
    const response = await apiFetchPartialRuleSets(shopifyDomain);
    return response;
  } catch (error) {
    sendErrorToAPI(error, "otpService.fetchPartialRuleSets", "error");
    throw error;
  }
};

// Unlike the other wrappers this swallows the error instead of rethrowing:
// the RTO gate is fail-open, so a scoring outage must leave payment rules
// visible rather than propagating up and blanking the payment screen.
export const fetchRtoDecision = async (args) => {
  try {
    return await apiFetchRtoDecision(args);
  } catch (error) {
    sendErrorToAPI(error, "otpService.fetchRtoDecision", "error");
    return { success: false, error: error.message, data: null };
  }
};
const DEBUG_MODE = true;

export const debugLog = (msg, data) => {
  if (DEBUG_MODE) {
    if (data) console.log(msg, data);
    else console.log(msg);
  }
};

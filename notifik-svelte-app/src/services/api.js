import { sendErrorToAPI } from "./errorReporter.js";
import { getSessionValue, setSessionValue } from "./sessionService.js";
import { logBackendApiCall, logExternalApiCall } from "../utils/apiLogger.js";
import {
  isNoEmailPlaceholder,
  isPreEmailMandatory,
  getNoEmailPlaceholder,
} from "../utilities/otpUtils.js";

export const getRouteUrl = () => {
  if (
    typeof window !== "undefined" &&
    window.parent &&
    window.parent["codkingRouteUrl"]
  ) {
    return window.parent["codkingRouteUrl"];
  }
  try {
    const settings = getSessionValue("settingSession");
    if (settings?.routeUrl) return settings.routeUrl;
  } catch (_e) {}
  throw new Error(
    "ROUTE_URL not found - ensure notifik_svelte.liquid is loaded",
  );
};

// Blocking call on the OTP -> payment transition, so it gets a tight budget.
const RTO_DECISION_TIMEOUT_MS = 4000;

const fetchWithTimeout = async (url, options = {}, timeout = 30000) => {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
    });
    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    if (error.name === "AbortError")
      throw new Error(
        "Request timeout. Please check your connection and try again.",
      );
    if (error.message?.includes("fetch"))
      throw new Error(
        "Network error. Please check your connection and try again.",
      );
    throw error;
  }
};

const parseApiError = (status, statusText, text) => {
  if (!text) return `API Error: ${status} ${statusText}`;
  try {
    const j = JSON.parse(text);
    return j.message || j.Notes || j.error || text;
  } catch {
    return text;
  }
};

const backendCall = async (method, path, body, meta) => {
  const start = performance.now();
  const url = path.startsWith("http") ? path : `${getRouteUrl()}${path}`;
  const opts = {
    method,
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    ...(body != null && { body: JSON.stringify(body) }),
  };
  try {
    const res = await fetchWithTimeout(url, opts, 30000);
    const dur = Math.round(performance.now() - start);
    if (!res.ok) {
      const text = await res.text();
      const err = new Error(parseApiError(res.status, res.statusText, text));
      logBackendApiCall(
        url,
        method,
        meta.logPayload,
        { status: res.status, error: text },
        dur,
        err,
        meta,
      );
      throw err;
    }
    const data = await res.json();
    logBackendApiCall(url, method, meta.logPayload, data, dur, null, {
      ...meta,
      status: res.status,
    });
    return data;
  } catch (e) {
    logBackendApiCall(
      url,
      method,
      meta.logPayload,
      null,
      Math.round(performance.now() - start),
      e,
      meta,
    );
    throw e;
  }
};

const isValidIP = (ip) => {
  if (!ip || typeof ip !== "string") return false;
  const ipv4Regex = /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
  if (ipv4Regex.test(ip)) {
    const parts = ip.split(".");
    return (
      parts.length === 4 &&
      parts.every((part) => {
        const num = parseInt(part, 10);
        return num >= 0 && num <= 255;
      })
    );
  }
  const ipv6Regex =
    /^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$|^([0-9a-fA-F]{1,4}:)*::([0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{1,4}$/;
  return ipv6Regex.test(ip);
};

export const fetchIpAddress = async () => {
  const cacheKey = "codk_cached_ip_address";
  const ipapiDataKey = "codk_ipapi_data";
  const cacheExpiry = 5 * 60 * 1000;
  try {
    const storedIpapiData = sessionStorage.getItem(ipapiDataKey);
    if (storedIpapiData) {
      try {
        const ipapiData = JSON.parse(storedIpapiData);
        if (
          ipapiData.ip &&
          isValidIP(ipapiData.ip) &&
          Date.now() - (ipapiData.timestamp || 0) < cacheExpiry
        ) {
          try {
            sessionStorage.setItem(
              cacheKey,
              JSON.stringify({
                ip: ipapiData.ip,
                timestamp: ipapiData.timestamp || Date.now(),
              }),
            );
          } catch (e) {}
          return ipapiData.ip;
        }
      } catch (e) {}
    }
    const cached = sessionStorage.getItem(cacheKey);
    if (cached) {
      const { ip, timestamp } = JSON.parse(cached);
      if (isValidIP(ip) && Date.now() - timestamp < cacheExpiry) return ip;
    }
  } catch (e) {}
  const ipApiServices = [
    {
      name: "ipapi.co",
      url: "https://ipapi.co/json/",
      parser: async (r) => (await r.json()).ip,
    },
    {
      name: "api.ipify.org",
      url: "https://api.ipify.org?format=json",
      parser: async (r) => (await r.json()).ip,
    },
    {
      name: "ip-api.com",
      url: "http://ip-api.com/json/",
      parser: async (r) => (await r.json()).query,
    },
  ];
  for (const service of ipApiServices) {
    const startTime = performance.now();
    try {
      const response = await fetchWithTimeout(
        service.url,
        { method: "GET", headers: { Accept: "application/json" } },
        5000,
      );
      const duration = performance.now() - startTime;
      if (response.ok) {
        const ip = await service.parser(response);
        if (ip && isValidIP(ip)) {
          try {
            sessionStorage.setItem(
              cacheKey,
              JSON.stringify({ ip, timestamp: Date.now() }),
            );
          } catch (e) {}
          logExternalApiCall(
            service.url,
            "GET",
            null,
            { ip: ip.substring(0, 2) + "****", service: service.name },
            Math.round(duration),
            null,
            { service: service.name, cached: false },
          );
          return ip;
        }
        logExternalApiCall(
          service.url,
          "GET",
          null,
          null,
          Math.round(duration),
          new Error("Invalid IP"),
          { service: service.name },
        );
      } else {
        logExternalApiCall(
          service.url,
          "GET",
          null,
          null,
          Math.round(duration),
          new Error(`HTTP ${response.status}`),
          { service: service.name, status: response.status },
        );
      }
    } catch (error) {
      logExternalApiCall(
        service.url,
        "GET",
        null,
        null,
        Math.round(performance.now() - startTime),
        error,
        { service: service.name },
      );
    }
  }
  return "";
};

export const sendCode = async (payload) => {
  const startTime = performance.now();
  try {
    const routeUrl = getRouteUrl();
    const url = `${routeUrl}/order_confirmations/pre_order_otp`;
    const response = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(payload),
      },
      30000,
    );
    const duration = performance.now() - startTime;
    if (!response.ok) {
      const errorText = await response.text();
      let msg = parseApiError(response.status, response.statusText, errorText);
      if (response.status === 429)
        msg = "Too many requests. Please try again in a moment.";
      const error = new Error(msg);
      logBackendApiCall(
        url,
        "POST",
        payload,
        { status: response.status, error: errorText },
        Math.round(duration),
        error,
        { endpoint: "pre_order_otp", phase: "user_action" },
      );
      throw error;
    }
    const responseText = await response.text();
    if (!responseText || responseText.trim() === "") {
      const err = new Error("Empty response from server. Please try again.");
      logBackendApiCall(url, "POST", payload, null, Math.round(duration), err, {
        endpoint: "pre_order_otp",
        phase: "user_action",
      });
      throw err;
    }
    let data;
    try {
      data = JSON.parse(responseText);
    } catch (parseError) {
      const err = new Error(
        parseError.message?.includes("Empty")
          ? "Empty response from server. Please try again."
          : "Invalid response from server. Please try again.",
      );
      logBackendApiCall(url, "POST", payload, null, Math.round(duration), err, {
        endpoint: "pre_order_otp",
        phase: "user_action",
      });
      throw err;
    }
    if (data == null) {
      const err = new Error("Invalid response from server. Please try again.");
      logBackendApiCall(url, "POST", payload, null, Math.round(duration), err, {
        endpoint: "pre_order_otp",
        phase: "user_action",
      });
      throw err;
    }
    logBackendApiCall(url, "POST", payload, data, Math.round(duration), null, {
      endpoint: "pre_order_otp",
      phase: "user_action",
      status: response.status,
    });
    // Ask whether this is a returning customer while the shopper types the
    // code; the payment screen reads the answer after verification.
    if (data?.status === "Success") lookupExistingCustomer(payload);
    return data;
  } catch (error) {
    const duration = performance.now() - startTime;
    logBackendApiCall(
      getRouteUrl() + "/order_confirmations/pre_order_otp",
      "POST",
      payload,
      null,
      Math.round(duration),
      error,
      { endpoint: "pre_order_otp", phase: "user_action" },
    );
    sendErrorToAPI(error, "api.sendCode", "error", {
      operation: "sendCode",
      phone: payload.phone ? `${payload.phone.substring(0, 3)}****` : null,
      countryCode: payload.country_code,
    });
    if (error.message?.includes("timeout"))
      throw new Error("Request timed out. Please try again.");
    if (error.message?.includes("network") || error.message?.includes("fetch"))
      throw new Error(
        "Network error. Please check your connection and try again.",
      );
    if (error.message && !error.message.includes("API Error:")) throw error;
    throw new Error(error.message || "Failed to send OTP. Please try again.");
  }
};

export const ssoCheck = async (shop, ssoToken) => {
  const start = performance.now();
  const params = { shop };
  if (ssoToken) params.sso_token = ssoToken;
  const url = `${getRouteUrl()}/order_confirmations/sso_check?${new URLSearchParams(params)}`;
  try {
    const res = await fetchWithTimeout(
      url,
      {
        method: "GET",
        headers: { Accept: "application/json" },
        credentials: "include",
      },
      10000,
    );
    const dur = Math.round(performance.now() - start);
    if (!res.ok) {
      console.log("[SSO] sso_check failed with status:", res.status);
      logBackendApiCall(
        url,
        "GET",
        { shop },
        { status: res.status },
        dur,
        new Error(`HTTP ${res.status}`),
        { endpoint: "sso_check", phase: "background" },
      );
      return { valid: false };
    }
    const data = await res.json();
    console.log("[SSO] sso_check response:", data);
    logBackendApiCall(url, "GET", { shop }, data, dur, null, {
      endpoint: "sso_check",
      phase: "background",
      status: res.status,
    });
    return data;
  } catch (error) {
    console.log("[SSO] sso_check error:", error.message);
    logBackendApiCall(
      url,
      "GET",
      { shop },
      null,
      Math.round(performance.now() - start),
      error,
      { endpoint: "sso_check", phase: "background" },
    );
    return { valid: false };
  }
};

export const ssoLogout = async (shop) => {
  const url = `${getRouteUrl()}/order_confirmations/sso_logout?${new URLSearchParams({ shop })}`;
  try {
    const res = await fetchWithTimeout(
      url,
      {
        method: "DELETE",
        headers: { Accept: "application/json" },
        credentials: "include",
      },
      10000,
    );
    const data = await res.json();
    console.log("[SSO] sso_logout response:", data);
    return data;
  } catch (error) {
    console.log("[SSO] sso_logout error:", error.message);
    return { success: false };
  }
};

export const verifyCode = async (payload) => {
  const start = performance.now();
  const url = `${getRouteUrl()}/order_confirmations/pre_order_otp_verify`;
  try {
    const res = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(payload),
        credentials: "include",
      },
      30000,
    );
    const dur = Math.round(performance.now() - start);
    if (!res.ok) {
      const text = await res.text();
      const err = new Error(parseApiError(res.status, res.statusText, text));
      logBackendApiCall(
        url,
        "POST",
        payload,
        { status: res.status, error: text },
        dur,
        err,
        { endpoint: "pre_order_otp_verify", phase: "user_action" },
      );
      throw err;
    }
    const data = await res.json();
    logBackendApiCall(url, "POST", payload, data, dur, null, {
      endpoint: "pre_order_otp_verify",
      phase: "user_action",
      status: res.status,
    });
    return data;
  } catch (error) {
    sendErrorToAPI(error, "api.verifyCode", "error", {
      operation: "verifyCode",
      phone: payload.phone ? `${payload.phone.substring(0, 3)}****` : null,
      countryCode: payload.country_code,
    });
    if (error.message?.includes("timeout"))
      throw new Error("Request timed out. Please try again.");
    if (error.message?.includes("network") || error.message?.includes("fetch"))
      throw new Error(
        "Network error. Please check your connection and try again.",
      );
    throw error;
  }
};

export const getAddressCount = async (phone, shopifyDomain) => {
  try {
    const data = await backendCall(
      "GET",
      `/order_confirmations/shipping_address_count?${new URLSearchParams({ phone, shopifyDomain })}`,
      null,
      {
        endpoint: "shipping_address_count",
        phase: "user_action",
        logPayload: {
          phone: phone ? `${phone.substring(0, 3)}****` : null,
          shopifyDomain,
        },
      },
    );
    return { success: true, data };
  } catch (error) {
    sendErrorToAPI(error, "api.getAddressCount", "error", {
      operation: "getAddressCount",
      phone: phone ? `${phone.substring(0, 3)}****` : null,
    });
    return { success: false, error: error.message };
  }
};

export const updateCartDetailsForPreCreation = async (cartItems) => {
  const startTime = performance.now();
  const stackLines = new Error().stack?.split("\n").slice(1, 8) || [];
  try {
    const routeUrl = getRouteUrl();
    const shopDomain =
      window["Shopify"]?.shop || window.parent?.["Shopify"]?.shop;
    if (!shopDomain) return null;
    const url = `${routeUrl}/order_confirmations/update_cart_details`;
    const { getMachineId, getDeviceType } = await import("../utils/helpers.js");
    const simplifiedCart = cartItems.map((item) => ({
      variantId: item.variant_id.toString(),
      title: item.title,
      totalQuantity: item.quantity,
      cost: parseFloat(item.presentment_price) || parseFloat(item.price) || 0,
      imageUrl: item.image || item.featured_image?.url,
    }));
    // Signed proof of an earlier OTP verification. Lets the backend track carts of sessions restored
    // by persistent sign-in / SSO, which never send an OTP and so have no pre-order record yet.
    const ssoToken =
      getSessionValue("preOrderOtpResponse")?.sso_session_token ||
      getSessionValue("ssoValidatedToken");
    const requestPayload = {
      device_id: getMachineId(),
      shop: shopDomain,
      device_type: getDeviceType().toLowerCase(),
      cart_details: simplifiedCart,
      ...(typeof ssoToken === "string" && ssoToken && { sso_session_token: ssoToken }),
    };
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(requestPayload),
    });
    const duration = performance.now() - startTime;
    if (!response.ok) {
      logBackendApiCall(
        url,
        "POST",
        requestPayload,
        { status: response.status },
        Math.round(duration),
        new Error(`HTTP ${response.status} ${response.statusText}`),
        {
          endpoint: "update_cart_details",
          phase: "background",
          caller: stackLines[0] || "unknown",
        },
      );
      return null;
    }
    const result = await response.json();
    logBackendApiCall(
      url,
      "POST",
      requestPayload,
      result,
      Math.round(duration),
      null,
      {
        endpoint: "update_cart_details",
        phase: "background",
        status: response.status,
        caller: stackLines[0] || "unknown",
      },
    );
    return result;
  } catch (error) {
    const duration = performance.now() - startTime;
    logBackendApiCall(
      getRouteUrl() + "/order_confirmations/update_cart_details",
      "POST",
      { itemCount: cartItems?.length || 0 },
      null,
      Math.round(duration),
      error,
      {
        endpoint: "update_cart_details",
        phase: "background",
        caller: stackLines[0] || "unknown",
      },
    );
    return null;
  }
};

export const fetchPartialRuleSets = async (shopifyDomain) => {
  const startTime = performance.now();
  try {
    const url = `${getRouteUrl()}/order_confirmations/partial_rule_sets?${new URLSearchParams({ shopifyDomain })}`;
    const response = await fetchWithTimeout(
      url,
      {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      },
      30000,
    );
    const duration = performance.now() - startTime;
    if (!response.ok) {
      const error = new Error(`HTTP error! status: ${response.status}`);
      logBackendApiCall(
        url,
        "GET",
        { shopifyDomain },
        { status: response.status },
        Math.round(duration),
        error,
        { endpoint: "partial_rule_sets", phase: "background" },
      );
      throw error;
    }
    const data = await response.json();
    const rawRuleSets = Array.isArray(data?.rule_sets) ? data.rule_sets : [];
    const cartRules = rawRuleSets.filter((r) => {
      const f = r?.is_cart_rule;
      return f === true || f === "true" || f === 1 || f === "1";
    });
    const filteredRuleSets = cartRules.length > 0 ? cartRules : rawRuleSets;
    logBackendApiCall(
      url,
      "GET",
      { shopifyDomain },
      { ruleSetsCount: filteredRuleSets.length },
      Math.round(duration),
      null,
      {
        endpoint: "partial_rule_sets",
        phase: "background",
        status: response.status,
      },
    );
    return { success: true, data: filteredRuleSets };
  } catch (error) {
    const duration = performance.now() - startTime;
    const url = `${getRouteUrl()}/order_confirmations/partial_rule_sets?${new URLSearchParams({ shopifyDomain })}`;
    logBackendApiCall(
      url,
      "GET",
      { shopifyDomain },
      null,
      Math.round(duration),
      error,
      { endpoint: "partial_rule_sets", phase: "background" },
    );
    return { success: false, error: error.message, data: [] };
  }
};

/**
 * RTO risk decision for the current shopper. Used to gate payment rules that
 * opted into the RTO engine.
 *
 * Deliberately fails open: any error, timeout or malformed body returns
 * { success: false, data: null } and the caller keeps the rule visible. A
 * scoring blip must never silently remove COD for every shopper.
 *
 * Timeout is short on purpose - this sits between OTP verification and the
 * payment screen, so a slow backend degrades to "show the rule" rather than
 * stalling the widget.
 */
export const fetchRtoDecision = async ({
  shopifyDomain,
  phone,
  email,
  zip,
  country,
  cartTotal,
}) => {
  const startTime = performance.now();
  const url = `${getRouteUrl()}/rto/decision`;
  const body = {
    shopify_domain: shopifyDomain || "",
    phone: phone || "",
    email: email || "",
    zip: zip || "",
    country: country || "",
    cart: { total: cartTotal ?? 0 },
  };

  try {
    const response = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(body),
      },
      RTO_DECISION_TIMEOUT_MS,
    );
    const duration = performance.now() - startTime;

    if (!response.ok) {
      const error = new Error(`HTTP error! status: ${response.status}`);
      logBackendApiCall(
        url,
        "POST",
        body,
        { status: response.status },
        Math.round(duration),
        error,
        { endpoint: "rto_decision", phase: "blocking" },
      );
      return { success: false, error: error.message, data: null };
    }

    const data = await response.json();
    if (data?.status !== "Success") {
      logBackendApiCall(
        url,
        "POST",
        body,
        { status: data?.status },
        Math.round(duration),
        new Error(data?.message || "RTO decision returned a non-success status"),
        { endpoint: "rto_decision", phase: "blocking" },
      );
      return { success: false, error: data?.message || "non-success", data: null };
    }

    logBackendApiCall(
      url,
      "POST",
      body,
      { band: data.band, risk_score: data.risk_score, cod_allowed: data.cod_allowed },
      Math.round(duration),
      null,
      { endpoint: "rto_decision", phase: "blocking", status: response.status },
    );
    return { success: true, data };
  } catch (error) {
    const duration = performance.now() - startTime;
    logBackendApiCall(
      url,
      "POST",
      body,
      null,
      Math.round(duration),
      error,
      { endpoint: "rto_decision", phase: "blocking" },
    );
    return { success: false, error: error.message, data: null };
  }
};

export const EXISTING_CUSTOMER_KEY = "codk_existing_customer";
export const phoneKey = (phone) => String(phone || "").replace(/\D/g, "").slice(-10);

const settingOn = (cfg) => !!cfg && (cfg.enabled === true || cfg.enabled === "true");
const ruleNeedsExistingCustomer = (rule) =>
  (rule?.amount_type === "percentage" &&
    parseFloat(rule?.amount) === 100 &&
    settingOn(rule?.repeat_customer_discount)) ||
  (rule?.amount_type === "cod" && settingOn(rule?.cod_cooling_period));

// In-flight lookup, so the payment screen can wait for it instead of asking twice.
let pendingLookup = null;
export const pendingExistingCustomerLookup = (key) =>
  pendingLookup && pendingLookup.key === key ? pendingLookup.promise : null;

/**
 * Fired after a successful OTP send. Stores
 * { phone, existing, lastOrderDate } in the session for the payment screen.
 * Skipped when the shop's rules are known and none use these settings.
 */
export const lookupExistingCustomer = (payload) => {
  const rules = getSessionValue("ruleSets");
  if (Array.isArray(rules) && rules.length && !rules.some(ruleNeedsExistingCustomer)) return null;

  const key = phoneKey(payload?.phone);
  if (!key) return null;
  const promise = fetchExistingCustomer({
    shopifyDomain: payload.shop,
    phone: payload.phone,
    email: getSessionValue("customer-email") || "",
  })
    .then((result) => {
      if (!result?.success) return; // fail-open: no answer means "new customer"
      setSessionValue(EXISTING_CUSTOMER_KEY, {
        phone: key,
        existing: result.data?.existing === true,
        lastOrderDate: result.data?.last_order_date || null,
      });
    })
    .catch(() => {})
    .finally(() => {
      if (pendingLookup?.promise === promise) pendingLookup = null;
    });
  pendingLookup = { key, promise };
  return promise;
};

/**
 * Has this shopper ordered from the shop before? Feeds the repeat-customer
 * discount and the COD cooling period on payment rules. Short timeout: a slow
 * answer degrades to "new customer" instead of stalling the widget.
 */
export const fetchExistingCustomer = async ({ shopifyDomain, phone, email }) => {
  const startTime = performance.now();
  const url = `${getRouteUrl()}/is-existing-customer`;
  const body = {
    shopify_domain: shopifyDomain || "",
    phone: phone || "",
    email: email || "",
  };
  const meta = { endpoint: "is_existing_customer", phase: "blocking" };

  try {
    const response = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(body),
      },
      RTO_DECISION_TIMEOUT_MS,
    );
    const duration = Math.round(performance.now() - startTime);
    if (!response.ok) {
      const error = new Error(`HTTP error! status: ${response.status}`);
      logBackendApiCall(url, "POST", body, { status: response.status }, duration, error, meta);
      return { success: false, error: error.message, data: null };
    }
    const data = await response.json();
    logBackendApiCall(url, "POST", body, { existing: data?.existing }, duration, null, {
      ...meta,
      status: response.status,
    });
    return { success: true, data };
  } catch (error) {
    logBackendApiCall(url, "POST", body, null, Math.round(performance.now() - startTime), error, meta);
    return { success: false, error: error.message, data: null };
  }
};

const cleanAddressForAPI = (address) => {
  if (!address) return address;
  return {
    id: address.id ?? null,
    first_name: address.first_name || "",
    last_name: address.last_name || "",
    phone: address.phone || "",
    address1: address.address1 || "",
    address2: address.address2 || "",
    city: address.city || "",
    province: address.province || "",
    zip: address.zip || "",
    country: address.country || "India",
    country_code: address.country_code || "IN",
    country_code_v2: address.country_code_v2 || "IN",
    province_code: address.province_code || "",
    formatted: address.formatted || "",
    formatted_area: address.formatted_area || "",
    created_at: address.created_at || new Date().toISOString(),
    updated_at: address.updated_at || new Date().toISOString(),
  };
};

export const saveShippingAddress = async ({
  phone,
  email,
  shippingAddresses,
}) => {
  const trimmedEmail = (email && String(email).trim()) || "";
  const resolvedEmail = isPreEmailMandatory()
    ? isNoEmailPlaceholder(trimmedEmail)
      ? ""
      : trimmedEmail
    : trimmedEmail || (phone ? getNoEmailPlaceholder(phone) : "") || "";
  const payload = {
    phone,
    email: resolvedEmail,
    shippingAdrress: Array.isArray(shippingAddresses)
      ? shippingAddresses.map(cleanAddressForAPI)
      : [],
  };
  try {
    const data = await backendCall(
      "POST",
      "/order_confirmations/post_shipping_address",
      payload,
      {
        endpoint: "post_shipping_address",
        phase: "user_action",
        logPayload: payload,
      },
    );
    return { success: true, data };
  } catch (error) {
    return { success: false, error: error.message || "Failed to save address" };
  }
};

export const createDiscountCode = async ({
  shopifyDomain,
  title,
  discountValue,
  type = "amount",
}) => {
  const startTime = performance.now();
  try {
    const routeUrl = getRouteUrl();
    const shopDomain = shopifyDomain || window?.parent?.Shopify?.shop;
    if (!shopDomain) throw new Error("Shopify domain not found");
    const requestData = {
      shopifyDomain: shopDomain,
      title: title || "Flash Sale",
      discountValue: String(discountValue),
      type,
    };
    const url = `${routeUrl}/order_confirmations/create_discount_code?${new URLSearchParams(requestData)}`;
    const response = await fetchWithTimeout(
      url,
      { method: "GET", headers: { Accept: "application/json" } },
      30000,
    );
    const duration = performance.now() - startTime;
    if (!response.ok) {
      const errorText = await response.text();
      const error = new Error(
        parseApiError(response.status, response.statusText, errorText),
      );
      logBackendApiCall(
        url,
        "GET",
        requestData,
        { status: response.status, error: errorText },
        Math.round(duration),
        error,
        { endpoint: "create_discount_code", phase: "user_action" },
      );
      throw error;
    }
    const data = await response.json();
    if (data?.error?.includes("created but code not returned")) {
      logBackendApiCall(
        url,
        "GET",
        requestData,
        data,
        Math.round(duration),
        new Error(data.error),
        {
          endpoint: "create_discount_code",
          phase: "user_action",
          status: response.status,
          partialSuccess: true,
        },
      );
      return { data: { ...data, error: data.error, discountCreated: true } };
    }
    logBackendApiCall(
      url,
      "GET",
      requestData,
      data,
      Math.round(duration),
      null,
      {
        endpoint: "create_discount_code",
        phase: "user_action",
        status: response.status,
      },
    );
    return {
      data: {
        code: data?.code || data?.discount_code || null,
        discountCreated: data?.discountCreated ?? !!data?.code,
        ...data,
      },
    };
  } catch (error) {
    const duration = performance.now() - startTime;
    const routeUrl = getRouteUrl();
    const shopDomain = shopifyDomain || window?.parent?.Shopify?.shop;
    const url = `${routeUrl}/order_confirmations/create_discount_code?${new URLSearchParams({ shopifyDomain: shopDomain || "", title: title || "Flash Sale", discountValue: String(discountValue), type })}`;
    logBackendApiCall(
      url,
      "GET",
      { shopifyDomain: shopDomain, title, discountValue, type },
      null,
      Math.round(duration),
      error,
      { endpoint: "create_discount_code", phase: "user_action" },
    );
    throw error;
  }
};

export const fetchZipDetails = async ({ zip, country_code = "IN" }) => {
  const startTime = performance.now();
  const baseUrl = "https://app.codking.tech";
  const url = `${baseUrl}/order_confirmations/zip_details?${new URLSearchParams({ zip: zip || "", country_code: country_code || "IN" })}`;
  try {
    const response = await fetchWithTimeout(
      url,
      { method: "GET", headers: { Accept: "application/json" } },
      10000,
    );
    const duration = performance.now() - startTime;
    if (!response.ok) {
      logBackendApiCall(
        url,
        "GET",
        { zip: zip?.substring(0, 2) + "****", country_code },
        { status: response.status },
        Math.round(duration),
        new Error(`HTTP ${response.status}`),
        { endpoint: "zip_details", phase: "user_action" },
      );
      return { location: {} };
    }
    const data = await response.json();
    logBackendApiCall(
      url,
      "GET",
      { zip: zip?.substring(0, 2) + "****", country_code },
      data,
      Math.round(duration),
      null,
      {
        endpoint: "zip_details",
        phase: "user_action",
        status: response.status,
      },
    );
    return data;
  } catch (error) {
    logBackendApiCall(
      url,
      "GET",
      { zip: zip?.substring(0, 2) + "****", country_code },
      null,
      Math.round(performance.now() - startTime),
      error,
      { endpoint: "zip_details", phase: "user_action" },
    );
    return { location: {} };
  }
};

const cartPayload = (p) => ({
  ...p,
  cart_data: { itemCount: p.cart_data?.items?.length || 0 },
});

export const createCodOrder = async (payload) =>
  backendCall("POST", "/api/cod_orders", payload, {
    endpoint: "cod_orders",
    phase: "user_action",
    logPayload: cartPayload(payload),
  });

export const calculateTax = async (payload) =>
  backendCall("POST", "/api/tax_calculation/calculate", payload, {
    endpoint: "tax_calculation",
    phase: "background",
    logPayload: cartPayload(payload),
  });

export const createRazorpayOrder = async (payload) =>
  backendCall("POST", "/api/razorpay_orders/create", payload, {
    endpoint: "razorpay_orders_create",
    phase: "user_action",
    logPayload: cartPayload(payload),
  });

export const verifyRazorpayPayment = async (payload) =>
  backendCall("POST", "/api/razorpay_orders/verify", payload, {
    endpoint: "razorpay_orders_verify",
    phase: "user_action",
    logPayload: payload,
  });

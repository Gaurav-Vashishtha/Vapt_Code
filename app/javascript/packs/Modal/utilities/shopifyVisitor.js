import { debugLog, getSessionValue } from "./otpUtils";

/**
 * Built for Shopify (Forms): log visitor-provided email/phone via Shopify.analytics.visitor.
 * Requires SHOPIFY_VISITOR_APP_ID (numeric app id from Admin `app { id }`) in env, exposed as shopify_visitor_app_id in lightweight settings.
 * @see https://shopify.dev/docs/api/web-pixels-api/emitting-data#visitor-api
 */
export function emitShopifyVisitorIdentify({
  phone,
  email,
  countryCallingCode,
} = {}) {
  const visitorFn = window.Shopify?.analytics?.visitor;
  if (typeof visitorFn !== "function") {
    debugLog("Shopify.analytics.visitor not available");
    return false;
  }

  const settings = getSessionValue("settingSession") || {};
  const appId =
    settings.shopifyVisitorAppId ?? settings.shopify_visitor_app_id;
  if (!appId) {
    debugLog("shopifyVisitorAppId missing; skip Visitor API");
    return false;
  }

  const payload = {};
  const trimmedEmail =
    typeof email === "string" && email.trim() ? email.trim() : null;
  if (trimmedEmail) {
    payload.email = trimmedEmail;
  }

  const digitsLocal = String(phone || "").replace(/\D/g, "");
  const cc = String(countryCallingCode || "").replace(/\D/g, "");
  if (digitsLocal) {
    payload.phone = cc ? `+${cc}${digitsLocal}` : String(phone).trim();
  }

  if (!payload.email && !payload.phone) {
    return false;
  }

  try {
    const ok = visitorFn(payload, { appId: String(appId) });
    debugLog("Shopify Visitor API invoked", {
      ok,
      hasEmail: Boolean(payload.email),
      hasPhone: Boolean(payload.phone),
    });
    return ok;
  } catch (e) {
    console.error("[COD] Visitor API error", e);
    return false;
  }
}

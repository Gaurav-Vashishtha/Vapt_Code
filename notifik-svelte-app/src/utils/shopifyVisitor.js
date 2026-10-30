import { getSessionValue } from "../services/sessionService.js";

/**
 * Resolve storefront window (parent when app runs in iframe) for Shopify global.
 * @returns {Window | null}
 */
function getStorefrontWindow() {
  if (typeof window === "undefined") return null;
  try {
    const p = window.parent;
    if (p && p !== window) return p;
  } catch (_e) {
    /* cross-origin */
  }
  return window;
}

function debugVisitor(msg, data) {
  try {
    const s = getSessionValue("settingSession") || {};
    if (s.debug) {
      console.log("[COD visitor]", msg, data ?? "");
    }
  } catch (_e) {}
}

/**
 * Built for Shopify (Forms): log visitor-provided email/phone via Shopify.analytics.visitor.
 * Uses SHOPIFY_VISITOR_APP_ID from lightweight settings (shopify_visitor_app_id → shopifyVisitorAppId).
 * @see https://shopify.dev/docs/api/web-pixels-api/emitting-data#visitor-api
 * @param {{ phone?: string, email?: string, countryCallingCode?: string }} args
 * @returns {boolean}
 */
export function emitShopifyVisitorIdentify({
  phone,
  email,
  countryCallingCode,
} = {}) {
  const storefrontWin = getStorefrontWindow();
  const visitorFn = storefrontWin?.Shopify?.analytics?.visitor;
  if (typeof visitorFn !== "function") {
    debugVisitor("Shopify.analytics.visitor not available");
    return false;
  }

  const settings = getSessionValue("settingSession") || {};
  const appId =
    settings.shopifyVisitorAppId ?? settings.shopify_visitor_app_id;
  if (!appId) {
    debugVisitor("shopifyVisitorAppId missing; skip Visitor API");
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
    const ok = visitorFn(payload, {
      appId: String(appId),
    });
    debugVisitor("Shopify Visitor API invoked", {
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

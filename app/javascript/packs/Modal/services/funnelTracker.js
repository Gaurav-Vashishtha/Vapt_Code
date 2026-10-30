import { getSessionValue } from "../utilities/otpUtils";

let sessionToken = null;
const sentEvents = {};

function generateToken() {
  try {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
      return crypto.randomUUID();
    }
  } catch (_e) {}
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function getSessionToken() {
  if (!sessionToken) {
    sessionToken = generateToken();
  }
  return sessionToken;
}

function isFunnelEnabled() {
  try {
    if (typeof window !== "undefined" && window.__CODKING_FUNNEL__ === false) {
      return false;
    }
    const settings = getSessionValue("settingSession") || {};
    if (
      settings.formFunnelEnabled === false ||
      settings.form_funnel_enabled === false
    ) {
      return false;
    }
    return true;
  } catch (_e) {
    return false;
  }
}

function getShopDomain() {
  try {
    if (typeof window !== "undefined" && window.Shopify && window.Shopify.shop) {
      return window.Shopify.shop;
    }
  } catch (_e) {}
  return null;
}

function emit(eventType, metadata) {
  try {
    if (!isFunnelEnabled()) return;
    if (sentEvents[eventType]) return;

    const shop = getShopDomain();
    if (!shop) return;

    const host = process.env.APP_HOST;
    if (!host) return;

    sentEvents[eventType] = true;

    const body = JSON.stringify({
      shop,
      session_token: getSessionToken(),
      event_type: eventType,
      occurred_at: new Date().toISOString(),
      metadata: metadata && typeof metadata === "object" ? metadata : {},
    });

    fetch(`https://${host}/form_funnel/ingest`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      keepalive: true,
    }).catch(function () {});
  } catch (_e) {}
}

export function trackFormView() {
  emit("form_view");
}

export function trackCheckoutInitiated(metadata) {
  emit("checkout_initiated", metadata);
}

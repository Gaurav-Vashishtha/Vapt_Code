import { getSessionValue } from "../utilities/otpUtils";

let sessionToken = null;
const sentEvents = {};

function generateToken() {
  try {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
      return crypto.randomUUID();
    }
  } catch (_e) {}
  // Prefer the platform UUID generator; fall back to a CSPRNG-backed v4 rather
  // than Math.random(), whose stream is predictable once a few values leak.
  const rng =
    typeof globalThis !== "undefined" && globalThis.crypto ? globalThis.crypto : null;
  if (rng && typeof rng.randomUUID === "function") return rng.randomUUID();
  if (rng && typeof rng.getRandomValues === "function") {
    const bytes = new Uint8Array(16);
    rng.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0"));
    return `${hex.slice(0,4).join("")}-${hex.slice(4,6).join("")}-${hex.slice(6,8).join("")}-${hex.slice(8,10).join("")}-${hex.slice(10,16).join("")}`;
  }
  throw new Error("Secure random source unavailable; cannot generate id");
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

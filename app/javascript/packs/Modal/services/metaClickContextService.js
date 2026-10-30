/**
 * Meta fbp/fbc (and related fields) for cart note attributes. PartialOrderEditJob
 * reads them from the order for Meta CAPI remaining_balance. Mirrors notifik orderService.js.
 */
import { getMachineId, getSessionValue } from "../utilities/otpUtils";

function isMetaConversionEnabled() {
  const s = getSessionValue("settingSession");
  if (s && s.conversionTracking === false) return false;
  return true;
}

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
      window.parent.postMessage({ type: "CODK_REQUEST_META_ATTRIBUTION" }, "*");
    }
  } catch (_e) {}
}

function getInjectedMetaClickData() {
  try {
    const w = typeof window !== "undefined" ? window : null;
    const inj = w && w.__codk_meta_click_data;
    if (!inj || typeof inj !== "object") return null;
    return inj;
  } catch (_e) {
    return null;
  }
}

function resolveEventSourceUrl() {
  try {
    if (typeof window === "undefined" || !window.location) return "";
    if (window.parent && window.parent !== window) {
      try {
        const h = String(window.parent.location.href);
        if (h && /^https?:/i.test(h)) return h;
      } catch (_crossOrigin) {}
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

async function waitForMetaClickDataFromParent(maxWaitMs = 1200) {
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

function readCampaignFbclidFromSession() {
  try {
    const tryParse = (raw) => {
      if (!raw || !String(raw).trim()) return "";
      const o = JSON.parse(String(raw));
      const v = o && o.fbclid != null ? String(o.fbclid).trim() : "";
      return v;
    };
    if (typeof sessionStorage !== "undefined") {
      const a = tryParse(sessionStorage.getItem("codk_campaign_attribution"));
      if (a) return a;
    }
    if (typeof window !== "undefined" && window.parent?.sessionStorage) {
      const b = tryParse(window.parent.sessionStorage.getItem("codk_campaign_attribution"));
      if (b) return b;
    }
  } catch (_e) {}
  return "";
}

function getMetaClickData() {
  const inj = getInjectedMetaClickData();
  const pick = (k) => {
    const v = inj && inj[k] != null ? String(inj[k]).trim() : "";
    return v || null;
  };

  const campaignFbclid = readCampaignFbclidFromSession();

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
    pick("fbclid") || readLocalStorage("codk_meta_fbclid") || campaignFbclid || "";
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

export function getMetaClickCartAttributePayload() {
  if (!isMetaConversionEnabled()) return {};
  const m = getMetaClickData();
  const o = {};
  if (m.fbp) o._fbp = m.fbp;
  if (m.fbc) o._fbc = m.fbc;
  if (m.fbclid) o._fbclid = m.fbclid;
  if (m.event_source_url) o._eventSourceUrl = m.event_source_url;
  if (m.client_user_agent) o._clientUserAgent = m.client_user_agent;
  return o;
}

export async function buildMetaAttributionAttributesForCart() {
  if (!isMetaConversionEnabled()) return {};
  await waitForMetaClickDataFromParent(1200);
  return getMetaClickCartAttributePayload();
}

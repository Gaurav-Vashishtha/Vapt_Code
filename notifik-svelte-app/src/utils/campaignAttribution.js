import { getSessionValue } from "../services/sessionService.js";

/** Whether COD King should attach/send Meta & campaign attribution (mirrors Setting#conversion_tracking, default true). */
export function isMetaConversionEnabled() {
  const s = getSessionValue("settingSession");
  if (s && s.conversionTracking === false) return false;
  return true;
}

/** Query params persisted for COD orders + Meta CAPI (must match CampaignAttributionHelper::ALLOWED_KEYS). */
export const CODK_CAMPAIGN_TRACKED_KEYS = [
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "utm_term",
  "utm_id",
  "campaign_id",
  "ad_id",
  "fbclid",
  "gclid",
  "gbraid",
  "wbraid",
  "gad_campaignid",
  "gad_source",
  "msclkid",
  "twclid",
];

export const CODK_CAMPAIGN_STORAGE_KEY = "codk_campaign_attribution";

function clearCampaignStorage(storage) {
  if (!storage || typeof storage.removeItem !== "function") return;
  try {
    storage.removeItem(CODK_CAMPAIGN_STORAGE_KEY);
  } catch (_e) {}
}

function readSessionLike(storage) {
  if (!storage || typeof storage.getItem !== "function") return {};
  try {
    const raw = storage.getItem(CODK_CAMPAIGN_STORAGE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (_e) {
    return {};
  }
}

function writeSessionLike(storage, obj) {
  if (!storage || typeof storage.setItem !== "function") return;
  if (!isMetaConversionEnabled()) {
    clearCampaignStorage(storage);
    return;
  }
  try {
    storage.setItem(CODK_CAMPAIGN_STORAGE_KEY, JSON.stringify(obj));
  } catch (_e) {}
}

/**
 * Parse tracked params from a query string (?a=b).
 * @param {string} search
 * @returns {Record<string, string>}
 */
export function parseCampaignParamsFromSearch(search) {
  const q = search.startsWith("?") ? search.slice(1) : search;
  const params = new URLSearchParams(q);
  /** @type {Record<string, string>} */
  const out = {};
  for (let i = 0; i < CODK_CAMPAIGN_TRACKED_KEYS.length; i++) {
    const k = CODK_CAMPAIGN_TRACKED_KEYS[i];
    const v = params.get(k);
    if (v != null && String(v).trim()) {
      out[k] = String(v).trim().slice(0, 500);
    }
  }
  return out;
}

/** Merge URL-derived params into storage (new non-empty values override). */
export function mergeCampaignFromSearch(search, storage = sessionStorage) {
  if (!isMetaConversionEnabled()) {
    clearCampaignStorage(storage);
    return;
  }
  const incoming = parseCampaignParamsFromSearch(search || "");
  if (Object.keys(incoming).length === 0) return;
  const prev = readSessionLike(storage);
  writeSessionLike(storage, { ...prev, ...incoming });
}

/** Merge object from parent postMessage into iframe sessionStorage. */
export function persistCampaignFromParentPayload(campaign, storage = sessionStorage) {
  if (!isMetaConversionEnabled()) {
    clearCampaignStorage(storage);
    return;
  }
  if (!campaign || typeof campaign !== "object") return;
  /** @type {Record<string, string>} */
  const slice = {};
  for (let i = 0; i < CODK_CAMPAIGN_TRACKED_KEYS.length; i++) {
    const k = CODK_CAMPAIGN_TRACKED_KEYS[i];
    const v = campaign[k];
    if (v != null && String(v).trim()) slice[k] = String(v).trim().slice(0, 500);
  }
  if (Object.keys(slice).length === 0) return;
  const prev = readSessionLike(storage);
  writeSessionLike(storage, { ...prev, ...slice });
}

function tryParentSessionStorage() {
  try {
    if (typeof window !== "undefined" && window.parent?.sessionStorage) {
      return readSessionLike(window.parent.sessionStorage);
    }
  } catch (_e) {}
  return {};
}

function getInjectedCampaign() {
  try {
    const w = typeof window !== "undefined" ? window : null;
    const inj = w && /** @type {any} */ (w).__codk_campaign_attribution;
    if (!inj || typeof inj !== "object") return {};
    return inj;
  } catch (_e) {
    return {};
  }
}

/** Snapshot for API: merged iframe storage + parent storage + injected + optional URL (same-origin). */
export function getCampaignAttributionPayload() {
  if (!isMetaConversionEnabled()) return {};
  mergeCampaignFromSearch(
    typeof window !== "undefined" && window.location
      ? window.location.search || ""
      : "",
  );

  const selfStored = readSessionLike(
    typeof sessionStorage !== "undefined" ? sessionStorage : null,
  );
  const parentStored = tryParentSessionStorage();
  const injected = getInjectedCampaign();

  /** @type {Record<string, string>} */
  const merged = { ...parentStored, ...selfStored, ...injected };
  /** @type {Record<string, string>} */
  const out = {};
  for (let i = 0; i < CODK_CAMPAIGN_TRACKED_KEYS.length; i++) {
    const k = CODK_CAMPAIGN_TRACKED_KEYS[i];
    const v = merged[k];
    if (v != null && String(v).trim()) out[k] = String(v).trim().slice(0, 500);
  }
  return out;
}

/**
 * Cart note attributes aligned with Rails CampaignAttributionHelper / PartialOrderAttributionCopy
 * (_codk_utm_source, _codk_fbclid, …) so parent + partial orders carry the same keys as Meta fields.
 * @returns {Record<string, string>}
 */
export function getCampaignCartAttributePayload() {
  if (!isMetaConversionEnabled()) return {};
  const p = getCampaignAttributionPayload();
  /** @type {Record<string, string>} */
  const o = {};
  for (let i = 0; i < CODK_CAMPAIGN_TRACKED_KEYS.length; i++) {
    const k = CODK_CAMPAIGN_TRACKED_KEYS[i];
    const v = p[k];
    if (v != null && String(v).trim()) {
      o[`_codk_${k}`] = String(v).trim().slice(0, 500);
    }
  }
  return o;
}

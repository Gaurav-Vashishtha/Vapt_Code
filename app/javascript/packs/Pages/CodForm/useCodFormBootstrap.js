import { useEffect, useState } from "react";
import { codFormApi } from "./api";

/**
 * GET /cod_form/bootstrap, fetched once per page load and shared by every
 * consumer (hub sidebar, Summary card, the module's screens).
 *
 * Returns `null` while loading, then
 *   {moduleEnabled, mode, legacyModeLabel, optinDismissed, tier, gates, usage, currency,
 *    moneyFormat, shopCountry, locales, preview: {assetBase, frameUrl}, failed}
 * This is the only place where the payload is camel-cased; nested maps
 * (gates, usage) are kept exactly as the API sends them.
 *
 * A failed call resolves to `{moduleEnabled: false, failed: true}` so the hub
 * group stays hidden and no existing screen is disturbed.
 */
let cache = null;
let inflight = null;
const listeners = new Set();

const shape = (raw) => {
  const body = raw && typeof raw === "object" ? raw : {};
  const preview = body.preview && typeof body.preview === "object" ? body.preview : {};
  return {
    moduleEnabled: body.module_enabled === true,
    mode: body.mode || "legacy",
    legacyModeLabel: body.legacy_mode_label || "checkout",
    optinDismissed: body.optin_dismissed === true,
    tier: body.tier || "free",
    gates: body.gates && typeof body.gates === "object" ? body.gates : {},
    usage: body.usage && typeof body.usage === "object" ? body.usage : null,
    currency: body.currency || "",
    moneyFormat: body.money_format || "",
    shopCountry: body.shop_country || "",
    otpEnabled: body.otp_enabled === true,
    planFormOrders: body.plan_form_orders && typeof body.plan_form_orders === "object" ? body.plan_form_orders : {},
    locales: Array.isArray(body.locales) && body.locales.length ? body.locales : ["en"],
    preview: { assetBase: preview.asset_base || "", frameUrl: preview.frame_url || "" },
    failed: false,
  };
};

const FAILED = shape({});
FAILED.failed = true;

/*
 * Last module flag seen in this browser ("1" on, "0" off, null unknown). The
 * Settings hub uses it to decide whether its landing page has to wait for the
 * bootstrap call: a shop known to have the module off is never delayed.
 * Storage can be unavailable inside the embedded iframe; then it is "unknown".
 */
const HINT_KEY = "codk_cod_form_module";

export const lastKnownModuleFlag = () => {
  try {
    return window.localStorage.getItem(HINT_KEY);
  } catch (error) {
    return null;
  }
};

const rememberModuleFlag = (value) => {
  if (!value || value.failed) return;
  try {
    window.localStorage.setItem(HINT_KEY, value.moduleEnabled ? "1" : "0");
  } catch (error) {
    /* ignore */
  }
};

const publish = (value) => {
  cache = value;
  rememberModuleFlag(value);
  listeners.forEach((listener) => listener(value));
};

const fetchBootstrap = () => {
  if (!inflight) {
    inflight = codFormApi
      .bootstrap()
      .then((raw) => publish(shape(raw)))
      .catch(() => publish(FAILED))
      .then(() => {
        inflight = null;
      });
  }
  return inflight;
};

/** Re-fetch, e.g. after a mode switch. Resolves when the new value is published. */
export const refreshBootstrap = () => {
  inflight = null;
  return fetchBootstrap();
};

/** Patch the shared value locally (e.g. right after a write whose effect is known). */
export const patchBootstrap = (patch) => {
  if (cache) publish({ ...cache, ...patch });
};

/** Current value without subscribing (null until the first fetch resolves). */
export const peekBootstrap = () => cache;

const useCodFormBootstrap = () => {
  const [value, setValue] = useState(cache);

  useEffect(() => {
    listeners.add(setValue);
    if (cache) setValue(cache);
    else fetchBootstrap();
    return () => {
      listeners.delete(setValue);
    };
  }, []);

  return value;
};

export default useCodFormBootstrap;

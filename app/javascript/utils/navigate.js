/**
 * App Bridge v4 Navigation Utility
 * This replaces the legacy Redirect actions with standard Web APIs.
 */

export const navigateTo = (path) => {
  // 1. Update the browser address bar.
  // App Bridge v4 automatically catches this and syncs the Shopify Admin URL.
  window.history.pushState({}, "", path);

  // 2. Dispatch a 'popstate' event.
  // This is CRITICAL for React apps to detect the change and re-render
  // the correct component based on the new URL.
  const navEvent = new PopStateEvent("popstate");
  window.dispatchEvent(navEvent);
};

/** Safe in-app path for returnTo deep links (open redirect guard). */
export const safeInternalPath = (raw) => {
  if (raw == null || typeof raw !== "string") return null;
  const decoded = String(raw).trim();
  if (!decoded.startsWith("/") || decoded.startsWith("//")) return null;
  if (decoded.includes("://")) return null;
  const pathOnly =
    decoded.split("?")[0].split("#")[0].replace(/\/+$/, "") || "/";
  if (!/^\/[a-zA-Z0-9_\-\/]*$/.test(pathOnly)) return null;
  return pathOnly;
};

/**
 * Navigates to a pathname while preserving existing query params (e.g. shop, host)
 * and merging in extra key/values (e.g. smsTemplate for deep links).
 * @param {string[]} keysToRemove - query keys to drop before merging (e.g. when going “back”)
 */
export const navigateToPreservingParams = (
  pathname,
  extraParams = {},
  keysToRemove = [],
) => {
  const params = new URLSearchParams(window.location.search || "");
  keysToRemove.forEach((k) => params.delete(k));
  Object.entries(extraParams).forEach(([k, v]) => {
    if (v != null && v !== "") params.set(k, String(v));
    else params.delete(k);
  });
  const qs = params.toString();
  const href = qs ? `${pathname}?${qs}` : pathname;
  window.history.pushState({}, "", href);
  window.dispatchEvent(new PopStateEvent("popstate"));
};

/**
 * For top-level redirects (like billing confirmation URLs)
 */
export const navigateExternal = (url) => {
  if (url) {
    window.open(url, "_top");
  }
};

/**
 * Full page navigation (reload). Preserves query string (e.g. shop, host) for embedded admin.
 */
export const assignWithFullReload = (path) => {
  const base = path.startsWith("/") ? path : `/${path}`;
  const qs = window.location.search || "";
  const hash = window.location.hash || "";
  window.location.assign(base + qs + hash);
};

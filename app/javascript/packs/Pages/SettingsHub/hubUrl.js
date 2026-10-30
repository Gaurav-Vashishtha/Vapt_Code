import { isHubWrappedPath } from "./registry";

/* The admin highlights an app nav item by matching the app URL against the
   item's href (child paths included); App Bridge no longer forwards the
   `active` attribute. Settings screens keep their existing routes inside the
   app, but the address bar shows them under /settings-hub so "Settings" lights
   up: /features/otp/pre-order is displayed as /settings-hub/features/otp/pre-order.

   Writes go through the history patch below, so every pushState/replaceState
   in the app gets the prefix without touching its call site. Reads that
   compare routes use currentAppPath(), which strips it again. */

export const HUB_BASE = "/settings-hub";

const trimSlash = (path) =>
  path && path.length > 1 ? path.replace(/\/+$/, "") : path;

const isUnderHub = (path) => path === HUB_BASE || path.startsWith(`${HUB_BASE}/`);

/** "/features/otp" -> "/settings-hub/features/otp"; other paths unchanged. */
export const toHubPath = (path) => {
  const trimmed = trimSlash(path);
  if (!trimmed || isUnderHub(trimmed) || !isHubWrappedPath(trimmed)) return path;
  return `${HUB_BASE}${trimmed}`;
};

/** "/settings-hub/features/otp" -> "/features/otp". Hub-own pages such as
    /settings-hub/language stay as they are. */
export const fromHubPath = (path) => {
  const trimmed = trimSlash(path);
  if (!trimmed || !trimmed.startsWith(`${HUB_BASE}/`)) return trimmed;
  const inner = trimmed.slice(HUB_BASE.length);
  return !isUnderHub(inner) && isHubWrappedPath(inner) ? inner : trimmed;
};

/** The app route for the current URL, without the /settings-hub prefix. */
export const currentAppPath = () => fromHubPath(window.location.pathname);

const rewriteUrl = (url) => {
  if (url === undefined || url === null || url === "") return url;
  try {
    const target = new URL(String(url), window.location.href);
    if (target.origin !== window.location.origin) return url;
    const pathname = toHubPath(target.pathname);
    if (pathname === target.pathname) return url;
    return `${pathname}${target.search}${target.hash}`;
  } catch (_) {
    return url;
  }
};

/** Patch history once, before anything navigates, and move a direct load of a
    bare settings path (bookmark, server redirect) onto its hub URL. */
export const installHubUrlRewrite = () => {
  if (typeof window === "undefined" || window.__codkHubUrlRewrite) return;
  window.__codkHubUrlRewrite = true;

  const { history } = window;
  const pushState = history.pushState;
  const replaceState = history.replaceState;

  history.pushState = function (state, title, url) {
    return pushState.call(this, state, title, rewriteUrl(url));
  };
  history.replaceState = function (state, title, url) {
    return replaceState.call(this, state, title, rewriteUrl(url));
  };

  const { pathname, search, hash } = window.location;
  if (toHubPath(pathname) !== pathname) {
    history.replaceState(history.state, "", `${pathname}${search}${hash}`);
  }
};

/**
 * postMessage helpers for the storefront modal.
 *
 * The widget runs in an iframe embedded by the merchant's theme, so the
 * embedding origin differs per shop and is not known at build time. Sending to
 * "*" lets any window that can get a handle on us read the message, so the
 * origin is resolved at runtime instead:
 *
 *   1. `location.ancestorOrigins` — the browser's own answer (Chromium, WebKit).
 *   2. the referrer's origin — for an iframe this is the embedding document
 *      (Firefox, which has no ancestorOrigins).
 *   3. "*" — only when both are unavailable (e.g. a referrer policy strips it).
 *      This is the previous behaviour, so a resolution failure degrades to
 *      today's situation rather than breaking the modal. Every payload sent
 *      through here is a control signal ("close", "reattach", "destroy
 *      iframe") and carries no customer or order data, which is what keeps
 *      that fallback acceptable.
 *
 * Do not pass customer, address, OTP or order data through these helpers while
 * the "*" fallback exists.
 */

const ANY_ORIGIN = "*";

let resolved;

function resolveParentOrigin() {
  try {
    if (typeof window === "undefined") return ANY_ORIGIN;

    const ancestors = window.location.ancestorOrigins;
    if (ancestors && ancestors.length > 0) {
      const first = ancestors[0];
      if (first && first !== "null") return first;
    }

    if (typeof document !== "undefined" && document.referrer) {
      const origin = new URL(document.referrer).origin;
      if (origin && origin !== "null") return origin;
    }
  } catch (_e) {}

  return ANY_ORIGIN;
}

/** The embedding storefront's origin, or "*" when it cannot be determined. */
export function getParentOrigin() {
  if (resolved === undefined) resolved = resolveParentOrigin();
  return resolved;
}

/**
 * Post a control message to the embedding storefront window.
 * @returns {boolean} false when there is no parent window to post to.
 */
export function postToParent(message) {
  try {
    if (typeof window === "undefined" || !window.parent || window.parent === window) {
      return false;
    }
    window.parent.postMessage(message, getParentOrigin());
    return true;
  } catch (_e) {
    return false;
  }
}

/**
 * Post to an explicit window: the parent's resolved origin when it is the
 * parent, our own origin when we are posting to ourselves.
 */
export function postToWindow(targetWindow, message) {
  try {
    if (!targetWindow) return false;
    const isParent = typeof window !== "undefined" && targetWindow === window.parent && window.parent !== window;
    const target = isParent ? getParentOrigin() : window.location.origin;
    targetWindow.postMessage(message, target);
    return true;
  } catch (_e) {
    return false;
  }
}

/**
 * True when a received `message` event really came from the embedding
 * storefront. Checks the window identity first (which an unrelated frame
 * cannot forge) and then the origin, when one could be resolved.
 */
export function isFromParent(event) {
  try {
    if (!event) return false;
    if (typeof window === "undefined" || !window.parent || window.parent === window) return false;
    if (event.source !== window.parent) return false;

    const expected = getParentOrigin();
    if (expected !== ANY_ORIGIN && event.origin !== expected) return false;

    return true;
  } catch (_e) {
    return false;
  }
}

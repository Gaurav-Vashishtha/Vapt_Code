/**
 * canvas-confetti is pulled from a CDN at runtime instead of being bundled, so
 * the widget ships no third-party JS of its own. Resolves to `window.confetti`
 * (or null when the CDN is unreachable — celebrations then simply skip).
 */

const CONFETTI_SRC =
  "https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.3/dist/confetti.browser.min.js";

let pending = null;

export function loadConfetti() {
  if (typeof window === "undefined") return Promise.resolve(null);
  if (window.confetti) return Promise.resolve(window.confetti);
  if (pending) return pending;

  pending = new Promise((resolve) => {
    const existing = document.querySelector(`script[src="${CONFETTI_SRC}"]`);
    const script = existing || document.createElement("script");

    const done = () => resolve(window.confetti || null);
    const fail = () => {
      pending = null;
      resolve(null);
    };

    script.addEventListener("load", done, { once: true });
    script.addEventListener("error", fail, { once: true });

    if (!existing) {
      script.src = CONFETTI_SRC;
      script.async = true;
      document.head.appendChild(script);
    }
  });

  return pending;
}

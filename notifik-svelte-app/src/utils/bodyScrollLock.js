/**
 * Shared body scroll lock for overlay surfaces (bottom sliders, sheets).
 *
 * The counter is module-level so nested overlays (e.g. a confirmation sheet on
 * top of the saved-addresses slider) don't unlock the page when the inner one
 * closes. `data-bottom-slider-open` stays the public hook other stylesheets key
 * off to freeze the background screen.
 */

let activeLocks = 0;
let lockedScrollY = 0;

export function lockBodyScroll() {
  if (typeof document === "undefined") return;

  if (activeLocks === 0) {
    lockedScrollY = window.scrollY;
    document.body.style.position = "fixed";
    document.body.style.top = `-${lockedScrollY}px`;
    document.body.style.width = "100%";
    document.body.style.overflow = "hidden";
    document.documentElement.style.overflow = "hidden";
    document.documentElement.dataset.bottomSliderOpen = "true";
  }
  activeLocks += 1;
}

export function unlockBodyScroll() {
  if (typeof document === "undefined") return;

  activeLocks = Math.max(0, activeLocks - 1);
  if (activeLocks !== 0) return;

  const scrollY = document.body.style.top;
  const scrollToRestore = scrollY
    ? parseInt(scrollY || "0", 10) * -1
    : lockedScrollY;

  document.body.style.position = "";
  document.body.style.top = "";
  document.body.style.width = "";
  document.body.style.overflow = "";
  document.documentElement.style.overflow = "";
  delete document.documentElement.dataset.bottomSliderOpen;
  lockedScrollY = 0;

  const needRestore =
    typeof window !== "undefined" &&
    Number.isFinite(scrollToRestore) &&
    scrollToRestore >= 0;
  if (needRestore) {
    requestAnimationFrame(() => {
      window.scrollTo(0, scrollToRestore);
    });
  }
}

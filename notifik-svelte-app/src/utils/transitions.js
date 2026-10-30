/**
 * Shared Svelte transitions for fast, snappy motion.
 * Use with transition:slideFromBottom and transition:fade (from svelte/transition).
 */
import { linear } from "svelte/easing";

/** Duration for bottom sheet open/close (ms) - fast and snappy */
export const MOTION_SHEET_MS = 150;
/** Duration for backdrop fade (ms) */
export const MOTION_BACKDROP_MS = 100;

function prefersReducedMotion() {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Svelte transition: slide panel up from bottom (enter) and down (exit).
 * Uses transform translateY(100%) for smooth, GPU-friendly animation.
 * @param {Element} node
 * @param {{ duration?: number; delay?: number }} params
 */
export function slideFromBottom(node, params = {}) {
  const requested = params.duration ?? MOTION_SHEET_MS;
  const duration = prefersReducedMotion() ? 0 : requested;
  const delay = params.delay ?? 0;

  return {
    delay,
    duration,
    easing: linear,
    css: (t, u) => `transform: translateY(${u * 100}%);`,
  };
}

/** Backdrop fade duration; 0 when user prefers reduced motion */
export function getBackdropDuration() {
  return prefersReducedMotion() ? 0 : MOTION_BACKDROP_MS;
}

/** Sheet slide duration; 0 when user prefers reduced motion (use for unlock delay) */
export function getSheetDuration() {
  return prefersReducedMotion() ? 0 : MOTION_SHEET_MS;
}

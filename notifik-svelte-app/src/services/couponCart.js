/**
 * Merge-safe coupon apply/remove for the cart's single `discount` field.
 *
 * Shopify's /cart/update.js `discount` param holds the ENTIRE comma-separated
 * code set; each write replaces it. The partial-payment flow also writes this
 * field, so a naive apply/remove would clobber a rule's code (and vice-versa).
 * These helpers read the cart's currently-applicable codes and write the merged
 * set so coupons stack instead of overwrite.
 */
import { get } from "svelte/store";
import otpStore from "../stores/otpStore.js";
import { executePost, getCart } from "./otpService.js";
import { isCouponExcluded } from "../utils/couponEligibility.js";

const EVENT_CART_DISCOUNT_UPDATED = "codk-cart-discount-updated";

function dispatchDiscountUpdated() {
  try {
    if (typeof window !== "undefined" && window.dispatchEvent) {
      window.dispatchEvent(new CustomEvent(EVENT_CART_DISCOUNT_UPDATED));
    }
  } catch (_) {}
}

/** Applicable codes on a given cart (Shopify keeps rejected ones as applicable:false). */
function codesOf(cart) {
  const codes = Array.isArray(cart?.discount_codes) ? cart.discount_codes : [];
  return codes
    .filter((c) => c && c.code && c.applicable !== false)
    .map((c) => c.code);
}

/** Currently-applicable codes on the live cart. */
function currentCodes() {
  return codesOf(get(otpStore)?.currentCartData);
}

function eq(a, b) {
  return String(a).toLowerCase() === String(b).toLowerCase();
}

/**
 * Apply a coupon code, merged with any codes already on the cart.
 * @returns {Promise<{ success: boolean, message?: string }>}
 */
export async function applyCouponCode(code) {
  const trimmed = typeof code === "string" ? code.trim() : "";
  if (!trimmed) return { success: false, message: "Please enter a coupon code." };

  const existing = currentCodes();
  if (existing.some((c) => eq(c, trimmed))) {
    return { success: true }; // already applied
  }

  const merged = [...existing, trimmed];
  const response = await executePost({ discount: merged.join(",") });
  if (!response?.ok) {
    return { success: false, message: response?.statusText || "Could not apply coupon." };
  }

  await getCart(true);

  // Confirm Shopify actually accepted it; if not, roll the inapplicable code back out.
  const cart = get(otpStore)?.currentCartData;
  const entry = (cart?.discount_codes || []).find((c) => eq(c.code, trimmed));
  if (entry && entry.applicable === false) {
    await executePost({ discount: currentCodes().join(",") });
    await getCart(true);
    dispatchDiscountUpdated();
    return {
      success: false,
      message: response?.message || "This coupon isn’t valid for your cart.",
    };
  }

  dispatchDiscountUpdated();
  return { success: true };
}

/**
 * Remove a single coupon code, preserving any other applied codes (e.g. a rule code).
 * @returns {Promise<{ success: boolean, message?: string }>}
 */
export async function removeCouponCode(code) {
  const trimmed = typeof code === "string" ? code.trim() : "";
  const remaining = currentCodes().filter((c) => !eq(c, trimmed));

  const response = await executePost({ discount: remaining.join(",") });
  if (!response?.ok) {
    return { success: false, message: response?.statusText || "Could not remove coupon." };
  }

  await getCart(true);
  dispatchDiscountUpdated();
  return { success: true };
}

/** Is a given code currently applied (and applicable) on the cart? */
export function isCodeApplied(code) {
  return currentCodes().some((c) => eq(c, code));
}

let reconciling = false;

/** Applied codes on `cart` whose exception product is present (must be stripped). */
function excludedAppliedCodes(cart) {
  const discounts = get(otpStore)?.settings?.activeDiscounts;
  if (!cart || !Array.isArray(discounts)) return [];
  const applied = codesOf(cart);
  if (applied.length === 0) return [];
  return discounts
    .filter(
      (c) =>
        c &&
        c.code &&
        isCouponExcluded(c, cart) &&
        applied.some((a) => eq(a, c.code)),
    )
    .map((c) => c.code);
}

/**
 * Strip excluded coupons from a freshly-fetched cart and return the cleaned cart
 * (the /cart/update.js response) — or null if nothing changed. Does NOT touch the
 * store; the caller (getCart) exposes only the cleaned cart, so the UI's load gate
 * naturally waits for update.js and the coupon never renders as applied.
 */
export async function stripExcludedFromCart(cart) {
  if (reconciling) return null;
  const drop = new Set(excludedAppliedCodes(cart).map((c) => c.toLowerCase()));
  if (drop.size === 0) return null;

  const remaining = codesOf(cart).filter(
    (c) => !drop.has(String(c).toLowerCase()),
  );

  reconciling = true;
  try {
    const response = await executePost({ discount: remaining.join(",") });
    if (!response?.ok) return null;
    dispatchDiscountUpdated();
    return await response.json(); // /cart/update.js returns the updated cart
  } finally {
    reconciling = false;
  }
}

/**
 * Reactive safety net for cart changes after load: if an excluded coupon is
 * applied, force a fresh getCart (which strips it before updating the store).
 */
export async function reconcileExcludedCoupons() {
  const cart = get(otpStore)?.currentCartData;
  if (excludedAppliedCodes(cart).length > 0) {
    await getCart(true);
  }
}

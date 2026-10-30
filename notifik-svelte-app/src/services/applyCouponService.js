/**
 * Apply/remove Shopify discount codes in the popup via cart/update.js.
 * Refetches cart and dispatches codk-cart-discount-updated for partial payment rules refresh (flow v2).
 */
import { executePost, getCart } from "./otpService.js";

const EVENT_CART_DISCOUNT_UPDATED = "codk-cart-discount-updated";

function dispatchDiscountUpdated() {
  try {
    if (typeof window !== "undefined" && window.dispatchEvent) {
      window.dispatchEvent(new CustomEvent(EVENT_CART_DISCOUNT_UPDATED));
    }
  } catch (_) {}
}

/**
 * Apply a discount code to the cart.
 * @param {string} code - Raw coupon code (will be trimmed).
 * @returns {Promise<{ success: true } | { success: false; message: string }>}
 */
export async function applyCoupon(code) {
  const trimmed = typeof code === "string" ? code.trim() : "";
  if (!trimmed) {
    return { success: false, message: "Please enter a coupon code." };
  }

  const response = await executePost({ discount: trimmed });

  if (!response?.ok) {
    return {
      success: false,
      message: response?.statusText || "Could not apply coupon. Please try again.",
    };
  }

  // executePost resolves with parsed body spread onto response (e.g. message, discount_codes)
  const body = response;
  const discountCodes = body?.discount_codes || [];
  const firstCode = Array.isArray(discountCodes) ? discountCodes[0] : null;
  const applicable = firstCode?.applicable ?? firstCode?.applicable_to_price;

  if (applicable === false) {
    const msg =
      body?.message ||
      firstCode?.message ||
      "This coupon is not valid or has expired.";
    return { success: false, message: msg };
  }

  if (body?.message && typeof body.message === "string") {
    const lower = body.message.toLowerCase();
    if (
      lower.includes("not found") ||
      lower.includes("invalid") ||
      lower.includes("expired") ||
      lower.includes("doesn't exist")
    ) {
      return { success: false, message: body.message };
    }
  }

  const cart = await getCart(true);
  if (!cart) {
    return { success: false, message: "Coupon may have been applied but cart could not be refreshed." };
  }

  dispatchDiscountUpdated();
  return { success: true };
}

/**
 * Remove all discount codes from the cart.
 * @returns {Promise<{ success: true } | { success: false; message: string }>}
 */
export async function removeCoupon() {
  const response = await executePost({ discount: "" });

  if (!response?.ok) {
    return {
      success: false,
      message: response?.statusText || "Could not remove coupon. Please try again.",
    };
  }

  const cart = await getCart(true);
  if (!cart) {
    return { success: false, message: "Coupon was removed but cart could not be refreshed." };
  }

  dispatchDiscountUpdated();
  return { success: true };
}

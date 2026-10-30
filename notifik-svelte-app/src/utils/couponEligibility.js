/**
 * Client-side coupon eligibility for the storefront widget.
 *
 * Advisory only — Shopify is the source of truth and re-validates at apply/checkout.
 * We compute the cheap, client-knowable gates (schedule, min subtotal, min quantity,
 * product membership) to drive the "applicable vs unlock" UI. Collection-scoped and
 * BXGY rules are treated optimistically (Shopify judges them when the code is applied).
 */

function numericId(gid) {
  return String(gid || "").split("/").pop();
}

/** Subtotal in major currency units (before cart-level discounts). */
function cartSubtotal(cart) {
  const cents =
    cart?.items_subtotal_price ??
    cart?.original_total_price ??
    cart?.total_price ??
    0;
  return Number(cents) / 100;
}

export function formatMoney(value, cart) {
  const n = Number(value) || 0;
  const currency = cart?.currency || "INR";
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency,
      maximumFractionDigits: n % 1 === 0 ? 0 : 2,
    }).format(n);
  } catch (_) {
    return `₹${n % 1 === 0 ? n : n.toFixed(2)}`;
  }
}

/** Short savings label for a coupon, e.g. "10% OFF" / "₹50 OFF" / "Buy X Get Y". */
export function couponSavingsLabel(coupon, cart) {
  if (coupon.headline) return coupon.headline;
  if (coupon.discount_type === "buy_x_get_y") return "Buy X Get Y";
  if (coupon.discount_type === "percentage") return `${Number(coupon.value)}% OFF`;
  return `${formatMoney(coupon.value, cart)} OFF`;
}

/** Estimated money saved if this coupon is applied (null for BXGY — unknown client-side). */
export function couponSavings(coupon, cart) {
  const subtotal = cartSubtotal(cart);
  if (coupon.discount_type === "percentage") {
    return subtotal * (Number(coupon.value) / 100);
  }
  if (coupon.discount_type === "amount_off") {
    return Math.min(Number(coupon.value), subtotal);
  }
  return null;
}

/** "Save ₹926.37" style pill text. Falls back to the generic label for BXGY. */
export function formatSavings(coupon, cart) {
  const saving = couponSavings(coupon, cart);
  if (saving == null || saving <= 0) return couponSavingsLabel(coupon, cart);
  return `Save ${formatMoney(saving, cart)}`;
}

/** Formatted amount alone, so the pill can weight the label and value apart. */
export function savingsAmount(coupon, cart) {
  const saving = couponSavings(coupon, cart);
  if (saving == null || saving <= 0) return "";
  return formatMoney(saving, cart);
}

/**
 * Actual money saved by an already-applied coupon, read from the cart's real
 * discount allocations (cart-level + line-level) matched by code/title.
 * Use this for the "applied" state so it reflects what Shopify actually applied
 * (e.g. ₹75), instead of re-estimating a percentage off the already-discounted total.
 */
export function appliedSavings(coupon, cart) {
  const names = [coupon?.code, coupon?.title, coupon?.headline]
    .map((v) => String(v || "").trim().toLowerCase())
    .filter(Boolean);
  if (names.length === 0) return 0;
  const matches = (title) => names.includes(String(title || "").trim().toLowerCase());

  let cents = 0;
  for (const app of cart?.cart_level_discount_applications || []) {
    if (matches(app.title)) cents += Number(app.total_allocated_amount) || 0;
  }
  for (const item of cart?.items || []) {
    for (const alloc of item?.line_level_discount_allocations || []) {
      if (matches(alloc?.discount_application?.title)) cents += Number(alloc.amount) || 0;
    }
  }
  return cents / 100;
}

/** One-line "Apply this code and get 10% off" style description. */
export function couponDescription(coupon, cart) {
  if (coupon.discount_type === "percentage") {
    return `Apply this code and get ${Number(coupon.value)}% off`;
  }
  if (coupon.discount_type === "amount_off") {
    return `Apply this code and get ${formatMoney(coupon.value, cart)} off`;
  }
  return "Buy X get Y offer";
}

/** Human-readable terms & conditions derived from the coupon config. */
export function couponTerms(coupon, cart) {
  const terms = [];

  if (coupon.minimum_requirement_type === "subtotal") {
    terms.push(`Minimum order value ${formatMoney(coupon.minimum_requirement_value, cart)}`);
  } else if (coupon.minimum_requirement_type === "quantity") {
    terms.push(`Minimum ${coupon.minimum_requirement_value} item(s) in cart`);
  }

  if (coupon.applies_to === "products") {
    terms.push("Valid on selected products only");
  } else if (coupon.applies_to === "collections") {
    terms.push("Valid on selected collections only");
  } else {
    terms.push("Valid on all products");
  }

  if (coupon.discount_type === "buy_x_get_y") {
    terms.push("Buy X get Y offer — eligible items added to cart");
  }

  if (coupon.ends_at) {
    try {
      terms.push(`Valid till ${new Date(coupon.ends_at).toLocaleDateString()}`);
    } catch (_) {}
  }

  const cw = coupon.combines_with || {};
  terms.push(
    cw.order || cw.product || cw.shipping
      ? "Can be combined with other eligible offers"
      : "Cannot be combined with other offers",
  );

  if (coupon.method === "automatic") {
    terms.push("Applies automatically — no code needed");
  }

  return terms;
}

/**
 * Whether a collection-scoped coupon must be hidden because the cart contains a
 * product the merchant excluded from that collection. Product membership is
 * client-knowable (cart items carry product_id), so this gate is enforced here.
 * @returns {boolean}
 */
export function isCouponExcluded(coupon, cart) {
  if (coupon.applies_to !== "collections") return false;
  const excluded = (coupon.excluded_product_gids || []).map(numericId);
  if (excluded.length === 0) return false;
  return (cart?.items || []).some((it) =>
    excluded.includes(String(it.product_id)),
  );
}

/**
 * @returns {{
 *   applicable: boolean,
 *   reason: string,        // why it's locked (empty when applicable)
 *   unlockText: string,    // engaging "add X to avail" copy
 *   progress: number       // 0..1 progress toward unlocking (for a progress bar)
 * }}
 */
export function evaluateCoupon(coupon, cart) {
  const ok = { applicable: true, reason: "", unlockText: "", progress: 1 };
  const now = Date.now();

  if (coupon.starts_at && new Date(coupon.starts_at).getTime() > now) {
    return { applicable: false, reason: "Not started yet", unlockText: "", progress: 0 };
  }
  if (coupon.ends_at && new Date(coupon.ends_at).getTime() < now) {
    return { applicable: false, reason: "Expired", unlockText: "", progress: 0 };
  }

  if (isCouponExcluded(coupon, cart)) {
    return {
      applicable: false,
      reason: "Not valid with an item in your cart",
      unlockText: "Remove the ineligible item to use this offer",
      progress: 0,
    };
  }

  const subtotal = cartSubtotal(cart);
  const itemCount = Number(cart?.item_count || 0);
  const custom = coupon.unlock_text;

  if (coupon.minimum_requirement_type === "subtotal") {
    const min = Number(coupon.minimum_requirement_value || 0);
    if (subtotal < min) {
      const remaining = Math.max(min - subtotal, 0);
      // Estimated saving once the threshold is reached, so the copy can nudge
      // with a concrete amount: "Add ₹325.04 more to save ₹75.00".
      const estSaving =
        coupon.discount_type === "percentage"
          ? min * (Number(coupon.value) / 100)
          : coupon.discount_type === "amount_off"
            ? Math.min(Number(coupon.value), min)
            : null;
      const text =
        (custom && custom.replace("{remaining}", formatMoney(remaining, cart))) ||
        (estSaving && estSaving > 0
          ? `Add ${formatMoney(remaining, cart)} more to save ${formatMoney(estSaving, cart)}`
          : `Add ${formatMoney(remaining, cart)} more to avail this offer`);
      return {
        applicable: false,
        reason: `Minimum ${formatMoney(min, cart)} required`,
        unlockText: text,
        progress: min > 0 ? Math.min(subtotal / min, 0.99) : 0,
      };
    }
  } else if (coupon.minimum_requirement_type === "quantity") {
    const min = Number(coupon.minimum_requirement_value || 0);
    if (itemCount < min) {
      const remaining = Math.max(min - itemCount, 0);
      // Estimated saving so the copy can nudge: "Add 3 more items to save ₹75".
      // Quantity-gated coupons aren't tied to a subtotal threshold, so estimate
      // against the current subtotal (a percentage) or the fixed value.
      const estSaving =
        coupon.discount_type === "percentage"
          ? subtotal * (Number(coupon.value) / 100)
          : coupon.discount_type === "amount_off"
            ? Number(coupon.value)
            : null;
      const text =
        (custom && custom.replace("{remaining}", String(remaining))) ||
        (estSaving && estSaving > 0
          ? `Add ${remaining} more item${remaining > 1 ? "s" : ""} to save ${formatMoney(estSaving, cart)}`
          : `Add ${remaining} more item${remaining > 1 ? "s" : ""} to avail this offer`);
      return {
        applicable: false,
        reason: `Minimum ${min} items required`,
        unlockText: text,
        progress: min > 0 ? Math.min(itemCount / min, 0.99) : 0,
      };
    }
  }

  // Product membership is client-knowable; collection membership is not.
  if (coupon.applies_to === "products") {
    const ids = (coupon.product_gids || []).map(numericId);
    const hasEligible = (cart?.items || []).some((it) =>
      ids.includes(String(it.product_id)),
    );
    if (!hasEligible) {
      return {
        applicable: false,
        reason: "No eligible product in cart",
        unlockText: custom || "Add an eligible product to avail this offer",
        progress: 0,
      };
    }
  }

  return ok;
}

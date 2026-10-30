/**
 * Partial payment bundle functions for Shopify carts.
 */

import { createDiscountCode, getCart } from "../../../services/otpService";
import {
  getSessionValue,
  getCurrentStep,
  setSessionValue,
  addCartAttributesWithOtpStore,
  applyDiscountCodeToOtpStore,
  removeDiscountCodeFromOtpStore,
  debugLog,
  formatCurrency,
  getStorefrontCartId,
  calculateRuleLevelDiscount,
  PartialPaymentFilteredRules,
  // createCartsForEligibleRules,
  hasBOGOItems,
  getFreeVariantIds,
  hasFreeProducts,
} from "../../../utilities/otpUtils";
import useOtpStore from "../../../stores/otpStore";
import { handleSimpleFlow } from "./paymentOptionsUtils";

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Get cart totals and discount information
 * @returns {Object} - Cart totals, discounts, and pricing info
 */
const getCartPricingInfo = () => {
  // Use currentCartData from OTP store (current cart) instead of cartStore
  const currentCartData = useOtpStore.getState()?.currentCartData;
  const cartTotalDecimal = (currentCartData?.total_price || 0) / 100 || 0;
  // Prefer original_total_price when available (pre-discount subtotal)
  const originalCartTotalDecimal =
    typeof currentCartData?.original_total_price === "number"
      ? currentCartData.original_total_price / 100
      : cartTotalDecimal + ((currentCartData?.total_discount || 0) / 100 || 0);
  const currencyCode = currentCartData?.currency || "INR";
  const cartItems = currentCartData?.items || [];

  // True line-level discounts only (exclude order-level allocations)
  const lineLevelDiscountDecimal = (cartItems || []).reduce((sum, item) => {
    const hasLineLevelDiscounts =
      item?.line_level_discount_allocations &&
      item.line_level_discount_allocations.length > 0;
    if (!hasLineLevelDiscounts) return sum;

    const cents =
      item?.line_level_total_discount ||
      (item?.line_level_discount_allocations || []).reduce((s, alloc) => {
        return s + (alloc?.amount || 0);
      }, 0);
    return sum + cents / 100;
  }, 0);

  // Existing order-level discount from cart-level applications
  const existingOrderLevelDiscountDecimal =
    (currentCartData?.cart_level_discount_applications || []).reduce(
      (sum, d) => {
        return sum + (d?.total_allocated_amount || 0);
      },
      0,
    ) / 100 || 0;

  return {
    cartState: currentCartData,
    cartTotalDecimal,
    originalCartTotalDecimal,
    currencyCode,
    cartItems,
    lineLevelDiscountDecimal,
    existingOrderLevelDiscountDecimal,
    hasFreeProducts: hasFreeProducts(cartItems),
  };
};

// Build _codkDiscounts + _codkImageURLs exactly like Svelte
export const getCodkImageURLs = (cartItems = []) => {
  try {
    const variantImageMap = new Map();
    (cartItems || []).forEach((item) => {
      const variantId = item?.variant_id || item?.id;
      if (variantId == null) return;

      let imageURL = item?.image || item?.image_url || item?.imageUrl || null;
      if (!imageURL && item?.featured_image) {
        if (typeof item.featured_image === "string") {
          imageURL = item.featured_image;
        } else if (item.featured_image?.url) {
          imageURL = item.featured_image.url;
        }
      }
      if (
        imageURL &&
        typeof imageURL === "string" &&
        !variantImageMap.has(variantId)
      ) {
        variantImageMap.set(variantId, imageURL);
      }
    });

    const entries = [];
    variantImageMap.forEach((url, variantId) => {
      const encoded = encodeURIComponent(url);
      entries.push(`${variantId}:${encoded}`);
    });
    return entries.join(",");
  } catch (e) {
    return "";
  }
};

export const calculateRuleOrderLevelDiscountDecimal = (
  rule,
  originalCartTotalDecimal,
  lineLevelDiscountDecimal,
) => {
  const ruleDiscountValueNum = parseFloat(rule?.discount_value || 0);
  const ruleDiscountType = rule?.discount_type || "";
  const ruleDiscountCode = (rule?.discount_code || "").trim();
  if (!ruleDiscountCode || !(ruleDiscountValueNum > 0)) return 0;

  if (ruleDiscountType === "percentage") {
    const base = Math.max(
      0,
      originalCartTotalDecimal - (lineLevelDiscountDecimal || 0),
    );
    return (base * ruleDiscountValueNum) / 100;
  }
  return ruleDiscountValueNum;
};

export const getCodkDiscounts = (
  cartItems = [],
  cartLevelDiscountApplications = [],
  options = { ruleOrderLevelDiscount: null },
) => {
  const discountEntries = [];

  // Line-level discounts per variant (true line-level only)
  const variantDiscountMap = new Map(); // variantId -> { discountCents, code }
  (cartItems || []).forEach((item) => {
    const variantId = item?.variant_id || item?.id;
    if (variantId == null) return;

    const hasLineLevelDiscounts =
      item?.line_level_discount_allocations &&
      item.line_level_discount_allocations.length > 0;
    if (!hasLineLevelDiscounts) return;

    const lineDiscountCents =
      item?.line_level_total_discount ||
      (item?.line_level_discount_allocations || []).reduce(
        (sum, alloc) => sum + (alloc?.amount || 0),
        0,
      );

    const discountCode =
      item?.line_level_discount_allocations?.[0]?.discount_application?.title ||
      item?.line_level_discount_allocations?.[0]?.discount_application?.code ||
      "";

    if (lineDiscountCents > 0) {
      const current = variantDiscountMap.get(variantId) || {
        discountCents: 0,
        code: "",
      };
      variantDiscountMap.set(variantId, {
        discountCents: current.discountCents + lineDiscountCents,
        code: current.code || discountCode,
      });
    }
  });

  variantDiscountMap.forEach((data, variantId) => {
    const discountDecimal = data.discountCents / 100;
    const entry = data.code
      ? `${variantId}:${discountDecimal}|${data.code}`
      : `${variantId}:${discountDecimal}`;
    discountEntries.push(entry);
  });

  // Existing order-level discount (cart-level applications)
  let existingOrderLevelDiscountCents = 0;
  let existingOrderLevelCode = "";
  if (
    cartLevelDiscountApplications &&
    cartLevelDiscountApplications.length > 0
  ) {
    existingOrderLevelDiscountCents = cartLevelDiscountApplications.reduce(
      (sum, d) => sum + (d?.total_allocated_amount || 0),
      0,
    );
    existingOrderLevelCode =
      cartLevelDiscountApplications[0]?.title ||
      cartLevelDiscountApplications[0]?.code ||
      "";
  }
  const existingOrderLevelDiscountDecimal =
    existingOrderLevelDiscountCents / 100;

  // Rule override (decimal)
  const ruleOrder = options?.ruleOrderLevelDiscount || null;
  const ruleAmount = Number(ruleOrder?.amount || 0);
  const ruleCode = (ruleOrder?.code || "").trim();

  let finalOrderLevelAmount = existingOrderLevelDiscountDecimal;
  let finalOrderLevelCode = existingOrderLevelCode;
  if (
    ruleAmount > finalOrderLevelAmount ||
    (ruleAmount === finalOrderLevelAmount && ruleCode)
  ) {
    finalOrderLevelAmount = ruleAmount;
    finalOrderLevelCode = ruleCode || finalOrderLevelCode;
  }

  if (finalOrderLevelAmount > 0) {
    const entry = finalOrderLevelCode
      ? `orderLevel:${finalOrderLevelAmount}|${finalOrderLevelCode}`
      : `orderLevel:${finalOrderLevelAmount}`;
    discountEntries.push(entry);
  }

  return discountEntries.join(",");
};

/**
 * Calculate rule-level discount value
 * @param {Object} rule - Rule object
 * @param {number} originalCartTotalDecimal - Original cart total
 * @returns {number} - Rule-level discount value
 */
// const calculateRuleLevelDiscount = (rule, originalCartTotalDecimal) => {
//   const ruleDiscountValue = parseFloat(rule?.discount_value || 0);
//   const ruleDiscountType = rule?.discount_type || "";
//   const ruleDiscountCode = rule?.discount_code || "";

//   if (ruleDiscountValue <= 0 || !ruleDiscountCode) return 0;

//   if (ruleDiscountType === "percentage") {
//     return (originalCartTotalDecimal * ruleDiscountValue) / 100;
//   } else {
//     return ruleDiscountValue;
//   }
// };

const getDiscountName = (cartState, rule, isRuleDiscountBigger) => {
  const ruleDiscountCode = rule?.discount_code || "";

  if (isRuleDiscountBigger && ruleDiscountCode) {
    return ruleDiscountCode;
  }

  const firstCartDiscount = cartState?.cart_level_discount_applications?.[0];
  return (
    firstCartDiscount?.title ||
    cartState?.discount_codes?.[0]?.code ||
    (cartState?.discount_codes?.[0]
      ? typeof cartState.discount_codes[0] === "string"
        ? cartState.discount_codes[0]
        : cartState.discount_codes[0]?.code
      : "") ||
    ""
  );
};

/**
 * Get effective amount (amount_to_show has priority)
 * @param {Object} rule - Rule object
 * @returns {Object} - Effective amount info
 */
const getEffectiveAmount = (rule) => {
  const amountToShow = rule?.amount_to_show?.trim();
  const shouldUseAmountToShow = amountToShow && amountToShow !== "";
  const effectiveAmount = shouldUseAmountToShow
    ? amountToShow
    : rule?.amount || "0";

  return {
    amountToShow,
    shouldUseAmountToShow,
    effectiveAmount,
    isCodFeeException:
      parseFloat(rule?.amount || 0) === 0 &&
      shouldUseAmountToShow &&
      rule?.amount_type === "fixed",
  };
};

/**
 * Build discount info string for description
 * @param {Object} params - Parameters object
 * @returns {string} - Discount info string
 */
const buildDiscountInfoString = ({
  originalCartTotalDecimal,
  finalPriceWithDiscount,
  totalDiscount,
  discountName,
  currencyCode,
  cartTotalDecimal,
}) => {
  if (totalDiscount > 0) {
    const discountAmountFormatted = formatCurrency(totalDiscount, currencyCode);
    const discountText = discountName
      ? `${discountAmountFormatted} discount (${discountName})`
      : `${discountAmountFormatted} discount`;
    return `Original price: ${formatCurrency(
      originalCartTotalDecimal,
      currencyCode,
    )}. ${formatCurrency(
      finalPriceWithDiscount,
      currencyCode,
    )} after ${discountText}`;
  }
  return `Total: ${formatCurrency(cartTotalDecimal, currencyCode)}`;
};

/**
 * Calculate payment and remaining amounts for a rule
 * @param {Object} rule - Rule object
 * @param {Object} pricingInfo - Pricing information from getCartPricingInfo
 * @returns {Object} - Payment and remaining amounts
 */
const calculatePaymentAmounts = (rule, pricingInfo) => {
  const {
    originalCartTotalDecimal,
    cartTotalDecimal,
    lineLevelDiscountDecimal,
    existingOrderLevelDiscountDecimal,
    hasFreeProducts: hasFreeProductsFlag,
  } = pricingInfo;

  // Order-level discount from rule (fixed amount)
  const ruleLevelDiscount = calculateRuleOrderLevelDiscountDecimal(
    rule,
    originalCartTotalDecimal,
    lineLevelDiscountDecimal,
  );
  const finalOrderLevelDiscount = Math.max(
    existingOrderLevelDiscountDecimal || 0,
    ruleLevelDiscount || 0,
  );
  const isRuleDiscountBigger =
    (ruleLevelDiscount || 0) > (existingOrderLevelDiscountDecimal || 0);
  const totalDiscount =
    (lineLevelDiscountDecimal || 0) + finalOrderLevelDiscount;

  // Always compute from original total so rule discount is reflected even if not yet applied to cart.
  const finalPriceWithDiscount = Math.max(
    0,
    originalCartTotalDecimal - totalDiscount,
  );

  // Get effective amount
  const { shouldUseAmountToShow, effectiveAmount, isCodFeeException } =
    getEffectiveAmount(rule);
  const ruleAmount = parseFloat(effectiveAmount || 0);

  let paymentAmount = 0;

  // Calculate payment amount based on rule type
  if (shouldUseAmountToShow && !isCodFeeException) {
    paymentAmount = parseFloat(rule?.amount_to_show || 0);
  } else if (isCodFeeException) {
    paymentAmount = parseFloat(rule?.amount_to_show || 0);
  } else if (rule?.amount_type === "fixed") {
    paymentAmount = ruleAmount;
  } else if (rule?.amount_type === "percentage") {
    if (ruleAmount === 100) {
      paymentAmount = finalPriceWithDiscount;
    } else {
      // Check if there's an order-level discount (not line-level)
      const hasOrderLevelDiscount = finalOrderLevelDiscount > 0;
      const hasLineLevelDiscount = (lineLevelDiscountDecimal || 0) > 0;

      if (hasOrderLevelDiscount && !hasLineLevelDiscount) {
        // For order-level discounts: calculate percentage on original total
        paymentAmount = (originalCartTotalDecimal * ruleAmount) / 100;
      } else {
        // For line-level discounts or no discounts: calculate from discounted price
        if (hasFreeProductsFlag) {
          paymentAmount = (finalPriceWithDiscount * ruleAmount) / 100;
        } else {
          paymentAmount = (finalPriceWithDiscount * ruleAmount) / 100;
        }
      }
    }
  }

  // Calculate remaining amount
  let remainingAmount = 0;
  if (isCodFeeException) {
    remainingAmount = finalPriceWithDiscount;
  } else if (shouldUseAmountToShow && !isCodFeeException) {
    remainingAmount = Math.max(0, finalPriceWithDiscount - paymentAmount);
  } else if (rule?.amount_type === "percentage") {
    // For percentage with order-level discount only: remaining = original - orderDiscount - paymentAmount
    const hasOrderLevelDiscount = finalOrderLevelDiscount > 0;
    const hasLineLevelDiscount = (lineLevelDiscountDecimal || 0) > 0;

    if (hasOrderLevelDiscount && !hasLineLevelDiscount && ruleAmount !== 100) {
      remainingAmount = Math.max(
        0,
        originalCartTotalDecimal - finalOrderLevelDiscount - paymentAmount,
      );
    } else {
      remainingAmount = Math.max(0, finalPriceWithDiscount - paymentAmount);
    }
  } else {
    paymentAmount = Math.min(paymentAmount, finalPriceWithDiscount);
    remainingAmount = Math.max(0, finalPriceWithDiscount - paymentAmount);
  }

  return {
    paymentAmount,
    remainingAmount,
    finalPriceWithDiscount,
    totalDiscount,
    isRuleDiscountBigger,
    originalCartTotalDecimal,
    cartTotalDecimal,
    ruleAmount,
  };
};

/**
 * Build cart attributes for partial payment
 * @param {Object} params - Parameters object
 * @returns {Object} - Cart attributes object
 */
const buildCartAttributes = ({
  amountType,
  amountValue,
  actualDiscountValue,
  freeVariantsValue,
  isCOD,
  isFullPercentage,
  ruleDescription,
  cart,
  rule,
}) => {
  const cartItems =
    cart?.items || useOtpStore.getState()?.currentCartData?.items || [];
  const cartLevelApps =
    cart?.cart_level_discount_applications ||
    useOtpStore.getState()?.currentCartData?.cart_level_discount_applications ||
    [];

  // Pricing inputs for rule discount
  const originalCartTotalDecimal =
    typeof cart?.original_total_price === "number"
      ? cart.original_total_price / 100
      : (() => {
          const c = cart || useOtpStore.getState()?.currentCartData || {};
          return ((c?.total_price || 0) + (c?.total_discount || 0)) / 100;
        })();

  const lineLevelDiscountDecimal = (cartItems || []).reduce((sum, item) => {
    const hasLineLevelDiscounts =
      item?.line_level_discount_allocations &&
      item.line_level_discount_allocations.length > 0;
    if (!hasLineLevelDiscounts) return sum;
    const cents =
      item?.line_level_total_discount ||
      (item?.line_level_discount_allocations || []).reduce(
        (s, alloc) => s + (alloc?.amount || 0),
        0,
      );
    return sum + cents / 100;
  }, 0);

  const ruleOrderLevelDiscountAmount = calculateRuleOrderLevelDiscountDecimal(
    rule,
    originalCartTotalDecimal,
    lineLevelDiscountDecimal,
  );
  const ruleOrderLevelDiscountCode = (rule?.discount_code || "").trim();
  const ruleOrderLevelDiscount =
    ruleOrderLevelDiscountAmount > 0 && ruleOrderLevelDiscountCode
      ? {
          amount: ruleOrderLevelDiscountAmount,
          code: ruleOrderLevelDiscountCode,
        }
      : null;

  const codkDiscounts = getCodkDiscounts(cartItems, cartLevelApps, {
    ruleOrderLevelDiscount,
  });
  const codkImageURLs = getCodkImageURLs(cartItems);
  const partialDummyVariantId =
    typeof sessionStorage !== "undefined"
      ? sessionStorage.getItem("partialDummyVariantId")
      : null;

  // Restrict checkout to COD-only when the merchant enabled it on this COD rule.
  // Read by the payment & delivery Shopify Functions via the _codkCheckoutMode
  // cart attribute. Always written (empty when not restricted) so switching away
  // from a restricted COD rule never leaves a stale restriction on the cart.
  const restrictCodOnly =
    isCOD &&
    (rule?.checkout_cod_only === true || rule?.checkout_cod_only === "true");

  const attributes = {
    _codkAmountType: amountType,
    _codkAmountValue: amountValue,
    _codkCheckoutMode: restrictCodOnly ? "cod_only" : "",
    _codkFinalDiscountValue: actualDiscountValue || "",
    _codkFreeVariants: freeVariantsValue || "",
    _codkPaymentDescription: ruleDescription,
    _codkDiscounts: codkDiscounts || "",
    _codkImageURLs: codkImageURLs || "",
    // Original cart total (full order value) — read by web pixel for Google Ads
    // conversion firing on partial-payment orders, since checkout.totalPrice only
    // reflects the partial paid amount.
    _codkOriginalTotal: String(originalCartTotalDecimal || ""),
  };

  // When the per-shop expand flag is on, signal the Cart Transform function to
  // use the `lineExpand` operation (real product at deposit price) instead of
  // the default `linesMerge` (dummy parent bundle). Absent => merge (unchanged).
   const EXPAND_TEST_DOMAINS = ["test-sso-store-11.myshopify.com", "democodking.myshopify.com", "dripdropattire.com", "aavikazevar.com", "unboxkar.com", "hairnhook.com", "beejkart.com", "maplestore.in", "modelgiftz.com"];
  const currentHost =
    typeof window !== "undefined" ? window.location?.host || "" : "";
  const expandFlowEnabled =
    getSessionValue("settingSession")?.partialExpandFlowEnabled === true ||
    EXPAND_TEST_DOMAINS.includes(currentHost);
  if (expandFlowEnabled && !isCOD && !isFullPercentage) {
    attributes._codkBundleMode = "expand";
  }

  if (partialDummyVariantId) {
    attributes._partial_product_variant = partialDummyVariantId;
  }

  // Add partial payment variants for partial payments (not COD or full payment)
  if (!isCOD && !isFullPercentage) {
    // Use currentCartData from OTP store (current cart) instead of cartStore
    const currentCartData = useOtpStore.getState()?.currentCartData;
    const variants = (currentCartData?.items || [])
      .map((item) => item?.variant_id || item?.id)
      .filter((id) => id != null);

    if (variants.length > 0) {
      attributes.partial_payment_variants = JSON.stringify(
        variants.map((v) => Number(v)).filter((n) => !isNaN(n)),
      );
      attributes._partialPaymentProduct = true;
    }
  }

  return attributes;
};

/**
 * Update ALL line items with description property for partial payment
 * OPTIMIZED: Makes minimal API calls - updates in parallel and skips unnecessary refresh
 * @param {string} ruleDescription - Description to add to all line items
 * @returns {Promise<void>}
 */
export const updateAllLineItemsDescription = async (ruleDescription) => {
  try {
    // Use currentCartData from OTP store (current cart) instead of cartStore
    const currentCartData = useOtpStore.getState()?.currentCartData;

    if (!currentCartData?.items || currentCartData.items.length === 0) {
      console.warn("[PartialPayment] No cart items to update with description");
      return;
    }

    // Skip if description is empty or already set on all items
    if (!ruleDescription || ruleDescription.trim() === "") {
      return;
    }

    const otpStore = useOtpStore.getState();

    // Update store first (for instant UI update)
    const storeUpdates = currentCartData.items.map((item, index) => {
      const lineNumber = index + 1;
      let existingProperties = {};

      if (item?.properties) {
        if (
          typeof item.properties === "object" &&
          !Array.isArray(item.properties)
        ) {
          existingProperties = { ...item.properties };
        } else if (Array.isArray(item.properties)) {
          item.properties.forEach((prop) => {
            if (prop && prop.name && prop.value !== undefined) {
              existingProperties[prop.name] = prop.value;
            }
          });
        }
      }

      const updatedProperties = {
        ...existingProperties,
        description: ruleDescription,
      };

      return { lineNumber, item, updatedProperties };
    });

    // ✅ Sync with otpStore currentCartData for UI consistency
    if (otpStore.patchCurrentCartData) {
      const patchedItems = currentCartData.items.map((item, index) => {
        const matchingUpdate = storeUpdates.find(
          (u) => u.lineNumber === index + 1,
        );
        if (matchingUpdate) {
          return {
            ...item,
            properties: matchingUpdate.updatedProperties,
          };
        }
        return item;
      });
      otpStore.patchCurrentCartData({ items: patchedItems });
    }
  } catch (descError) {
    // Don't throw - non-critical for checkout flow
  }
};

/**
 * Remove description property from ALL line items (for full payment)
 * Syncs with Shopify API to ensure descriptions are actually removed
 * @returns {Promise<void>}
 */
export const removeAllLineItemsDescription = async () => {
  try {
    // Use currentCartData from OTP store (current cart) instead of cartStore
    const currentCartData = useOtpStore.getState()?.currentCartData;

    if (!currentCartData?.items || currentCartData.items.length === 0) {
      return;
    }

    // Update store and Shopify API - remove description property from all items
    const propertyUpdates = currentCartData.items.map((item, index) => {
      const lineNumber = index + 1;
      let existingProperties = {};

      if (item?.properties) {
        if (
          typeof item.properties === "object" &&
          !Array.isArray(item.properties)
        ) {
          existingProperties = { ...item.properties };
        } else if (Array.isArray(item.properties)) {
          item.properties.forEach((prop) => {
            if (prop && prop.name && prop.value !== undefined) {
              existingProperties[prop.name] = prop.value;
            }
          });
        }
      }

      // Remove description property
      const updatedProperties = { ...existingProperties };
      delete updatedProperties.description;

      // Also update Shopify API directly to ensure it's synced
      return {
        lineNumber,
        quantity: item.quantity || 1,
        properties: updatedProperties,
      };
    });

    // ✅ Sync with otpStore currentCartData for UI consistency
    const otpStore = useOtpStore.getState();
    if (otpStore.patchCurrentCartData) {
      const patchedItems = currentCartData.items.map((item, index) => {
        const matchingUpdate = propertyUpdates.find(
          (u) => u.lineNumber === index + 1,
        );
        if (matchingUpdate) {
          return {
            ...item,
            properties: matchingUpdate.properties,
          };
        }
        return item;
      });
      otpStore.patchCurrentCartData({ items: patchedItems });
    }
  } catch (descError) {
    // Don't throw - non-critical for checkout flow
  }
};

/**
 * Determine if rule's discount should be applied
 * Rule: Apply if rule has discount_code AND (rule discount > cart discount OR cart discount === 0)
 * @param {Object} selectedRuleObj - Rule object
 * @param {number} ruleDiscountValue - Calculated rule discount value
 * @param {number} existingCartDiscountValue - Existing cart discount value
 * @returns {boolean} - True if rule discount should be applied
 */
const shouldApplyRuleDiscount = (
  selectedRuleObj,
  ruleDiscountValue,
  existingCartDiscountValue,
) => {
  const ruleDiscountCode = selectedRuleObj?.discount_code?.trim();
  return (
    ruleDiscountCode &&
    ruleDiscountCode !== "" &&
    (ruleDiscountValue > existingCartDiscountValue ||
      existingCartDiscountValue === 0)
  );
};

/**
 * Remove all discount codes from both cart store and storefront cart
 * Used when switching to a rule that doesn't need discount codes
 * @returns {Promise<void>}
 */
const removeAllDiscountCodesHelper = async () => {
  const otpStore = useOtpStore.getState();
  const currentCartData = otpStore?.currentCartData;
  const currentDiscountCodes = currentCartData?.discount_codes || [];

  if (currentDiscountCodes.length === 0) {
    return;
  }

  try {
    removeDiscountCodeFromOtpStore();
  } catch (removeError) {
    // Non-critical - continue anyway
  }
};

/**
 * Apply discount code to both cart store and storefront cart
 * OPTIMIZED: Skips unnecessary removal calls if no existing discount codes
 * @param {string} discountCode - Discount code to apply
 */
const applyDiscountCodeToCartHelper = async (discountCode) => {
  if (!discountCode) return;

  const otpStore = useOtpStore.getState();
  const currentCartData = otpStore?.currentCartData;
  const currentDiscountCodes = currentCartData?.discount_codes || [];

  // OPTIMIZED: Only remove existing discount codes if they exist
  const hasExistingCodes = currentDiscountCodes.length > 0;

  if (hasExistingCodes) {
    try {
      removeDiscountCodeFromOtpStore();
    } catch (removeError) {
      console.warn(
        "[PartialPayment] Error removing existing discount codes:",
        removeError,
      );
    }
  }

  applyDiscountCodeToOtpStore(discountCode);
};

/**
 * Generate a random discount name for API-created discount codes
 * Includes "codk" prefix for easy tracking of system-created discounts
 * @returns {string} - Random discount name (e.g., "CODK Flash Sale", "CODK Super Deal")
 */
const generateRandomDiscountName = () => {
  const prefixes = ["ASEC", "QWER", "AUNF"];
  const suffixes = ["ASEC", "AJDH", "QWER"];
  const randomPrefix = prefixes[Math.floor(Math.random() * prefixes.length)];
  const randomSuffix = suffixes[Math.floor(Math.random() * suffixes.length)];
  return `CODK ${randomPrefix} ${randomSuffix}`;
};

/**
 * Create discount code via API if discount doesn't match
 * Rule: If discountValueMatch === false, create new discount code
 * Tracks created codes in session for later removal
 * IMPORTANT: Only creates discount code if discount value > 0
 * @param {string} shop - Shopify domain
 * @param {string|number} actualDiscountValue - Actual discount value
 * @returns {string|null} - Created discount code or null
 */
// const createDiscountCodeIfNeeded = async (shop, actualDiscountValue) => {
//   // Skip creating discount code if discount value is 0, null, or invalid
//   const discountValueNum = parseFloat(actualDiscountValue);
//   if (
//     !actualDiscountValue ||
//     isNaN(discountValueNum) ||
//     discountValueNum <= 0
//   ) {
//     debugLog(
//       "[PartialPayment] Skipping discount code creation - discount value is zero or invalid:",
//       actualDiscountValue,
//     );
//     return null;
//   }

//   const discountName = generateRandomDiscountName();

//   try {
//     const discountResponse = await createDiscountCode({
//       shopifyDomain: shop,
//       title: discountName,
//       discountValue: discountValueNum,
//       type: "amount",
//     });

//     // Check if discount was created but code not returned
//     if (
//       discountResponse?.data?.discountCreated ||
//       discountResponse?.data?.error?.includes("created but code not returned")
//     ) {
//       return null;
//     }

//     // Extract discount code from response
//     const createdDiscountCode =
//       discountResponse?.data?.code ||
//       discountResponse?.data?.discount_code ||
//       null;

//     // Store created discount code in session for later removal if needed
//     if (createdDiscountCode) {
//       setSessionValue("codk_created_discount_code", createdDiscountCode);
//       debugLog(
//         "[PartialPayment] Stored created discount code for tracking:",
//         createdDiscountCode,
//       );
//     }

//     return createdDiscountCode;
//   } catch (error) {
//     return null;
//   }
// };

export const handlePartialPaymentBundleFlow = async (
  cart,
  selectedRuleObj,
  shop,
  selectedRule,
  currencyCode,
  setIsPartialPaymentCartReadyAndUpdated,
  cartTotal,
  orderSummary,
  cartResult = null,
) => {
  // Extract amount type and value
  const amountToShow = selectedRuleObj?.amount_to_show?.trim();
  const shouldUseAmountToShow = amountToShow && amountToShow !== "";
  const amountType =
    selectedRuleObj?.amount_type != null ? selectedRuleObj.amount_type : "0";

  // Check if this is COD or Full Payment FIRST - these should use handleSimpleFlow, not this function
  const isCOD = selectedRuleObj?.amount_type === "cod";
  const isFullPercentage =
    selectedRuleObj?.amount_type === "percentage" &&
    selectedRuleObj?.amount === "100.0";

  if (isCOD || isFullPercentage) {
    return; // Early return - these should not create products
  }

  // IMPORTANT: For product creation, always use the actual `amount` value
  const actualAmount =
    selectedRuleObj?.amount != null ? selectedRuleObj.amount : "0";
  const amountValue = actualAmount;

  // Get discount codes and discount value from currentCartData in OTP store
  const otpStoreState = useOtpStore.getState();
  const currentCartData = otpStoreState.currentCartData;
  const actualDiscountValue = currentCartData?.total_discount
    ? String(currentCartData.total_discount / 100)
    : "0";

  // CRITICAL: If discount value is 0, there should be no discount codes
  // Filter out discount codes that exist but aren't providing any discount
  // This prevents stale discount codes from being included when switching rules
  const rawDiscountCodes = (currentCartData?.discount_codes || [])
    .map((dc) => (typeof dc === "string" ? dc : dc?.code))
    .filter((code) => code && typeof code === "string");

  // Only include discount codes if there's an actual discount value
  const actualDiscountCodes =
    Number(actualDiscountValue) > 0 ? rawDiscountCodes : [];

  // Find free line items (items with zero final price)
  const freeVariantsValue = getFreeVariantIds(cart?.items || []);

  // ✅ BOGO EXCEPTION: Check if cart has BOGO items - skip all discount code application
  const hasBOGO = hasBOGOItems(cart?.items || []);

  // Use cartResult if provided (from createCartsForEligibleRules), otherwise calculate discount match
  let discountValueMatch = false;
  let ruleDiscountValue = 0;
  let existingCartDiscountValue = 0;

  if (cartResult) {
    discountValueMatch = cartResult.discountValueMatch ?? false;
  }

  const currentCartTotalDecimal = (currentCartData?.total_price || 0) / 100;
  const existingCartDiscountValueDecimal = parseFloat(actualDiscountValue || 0);
  const originalCartTotalDecimal =
    currentCartTotalDecimal + existingCartDiscountValueDecimal;

  ruleDiscountValue = calculateRuleLevelDiscount(
    selectedRuleObj,
    originalCartTotalDecimal,
  );
  existingCartDiscountValue = existingCartDiscountValueDecimal;

  // Determine if rule's discount should be applied
  const shouldApplyRuleDiscountValue = shouldApplyRuleDiscount(
    selectedRuleObj,
    ruleDiscountValue,
    existingCartDiscountValue,
  );

  const ruleDiscountCode = selectedRuleObj?.discount_code?.trim();

  const discountValueNum = parseFloat(actualDiscountValue || 0);

  // CRITICAL: Only create discount code if discount VALUE doesn't match
  // If discountValueMatch is true, it means the discount value already matches (via line item, automatic, or discount code)
  // If discountValueMatch is false, we need to create a discount code for the actualDiscountValue
  // BUT: Only create if actualDiscountValue > 0 (don't create zero-value discounts)
  const shouldCreateDiscountCodeForValue =
    !discountValueMatch && discountValueNum > 0 && !isNaN(discountValueNum);

  // Check if we need to switch discount codes even if discount value matches
  // This handles the case where we switch from Rule A (with discount_code_A)
  // to Rule B (with discount_code_B) where both have the same discount value
  const currentDiscountCodes = actualDiscountCodes;
  const needsDiscountCodeSwitch =
    ruleDiscountCode &&
    ruleDiscountCode !== "" &&
    !currentDiscountCodes.some(
      (code) =>
        code.trim().toLowerCase() === ruleDiscountCode.trim().toLowerCase(),
    ) &&
    (ruleDiscountValue >= existingCartDiscountValue ||
      existingCartDiscountValue === 0);

  const shouldApplyDiscount =
    shouldApplyRuleDiscountValue ||
    shouldCreateDiscountCodeForValue ||
    needsDiscountCodeSwitch;

  // ✅ BOGO EXCEPTION: Skip all discount code application if BOGO items are present
  const shouldSkipDiscountApplication = hasBOGO;

  if (!shouldApplyDiscount || shouldSkipDiscountApplication) {
    if (currentDiscountCodes.length > 0) {
      try {
        await removeAllDiscountCodesHelper();
      } catch (removeError) {
        console.warn(
          "[PartialPayment] Failed to remove discount codes when switching rules:",
          removeError,
        );
      }
    }
  } else if (!shouldSkipDiscountApplication) {
    try {
      let discountCode = null;

      if (shouldApplyRuleDiscountValue || needsDiscountCodeSwitch) {
        const ruleCodeAlreadyApplied = currentDiscountCodes.some(
          (code) =>
            code.trim().toLowerCase() === ruleDiscountCode.trim().toLowerCase(),
        );

        if (!ruleCodeAlreadyApplied) {
          discountCode = ruleDiscountCode;
        }
      } else if (shouldCreateDiscountCodeForValue) {
        if (cartResult?.createdDiscountCode) {
          discountCode = cartResult.createdDiscountCode;
        }
        // else {
        //   discountCode = await createDiscountCodeIfNeeded(
        //     shop,
        //     actualDiscountValue,
        //   );
        // }
      }

      if (discountCode) {
        await applyDiscountCodeToCartHelper(discountCode);
      }
    } catch (discountError) {
      // Continue with attribute update even if discount application fails
    }
  } else if (shouldSkipDiscountApplication) {
    // Remove any existing discount codes for BOGO carts
    if (currentDiscountCodes.length > 0) {
      try {
        await removeAllDiscountCodesHelper();
      } catch (removeError) {
        console.warn(
          "[PartialPayment] Failed to remove discount codes for BOGO cart:",
          removeError,
        );
      }
    }
  }

  // Get rule description using getDescBundle
  const ruleDescription =
    getDescBundle(selectedRuleObj) || "Partial payment option selected";

  // Build attributes object for executePost
  const currentCartDataForAttrs = useOtpStore.getState()?.currentCartData;
  const attributes = buildCartAttributes({
    amountType,
    amountValue,
    actualDiscountValue,
    freeVariantsValue,
    isCOD,
    isFullPercentage,
    ruleDescription,
    cart: currentCartDataForAttrs,
    rule: selectedRuleObj,
  });

  // Update cart attributes in both Shopify and OTP Store
  // await executePost({ attributes });

  // ✅ Sync with otpStore currentCartData for UI consistency
  addCartAttributesWithOtpStore(attributes);

  // Add description to ALL line items for partial payment
  await updateAllLineItemsDescription(ruleDescription);
  setIsPartialPaymentCartReadyAndUpdated(true);
  return;
};

/**
 * Generate payment description for a rule
 *
 * Rules:
 * 1. amount_to_show has HIGHEST PRIORITY (except COD fee exception)
 * 2. Always include discount info: "Original price: ₹XXX. ₹YYY after ₹ZZZ discount (CODE)"
 * 3. Compare rule-level vs cart-level discount, use whichever is bigger
 * 4. FREE PRODUCTS EXCEPTION: Calculate percentage from discounted price, not original
 * 5. COD fee exception: When amount === "0.0" && amount_to_show provided, treat as COD fee
 * 6. Percentage with amount_to_show: Don't show percentage notation
 *
 * @param {Object} rule - Rule object
 * @returns {string} - Formatted payment description
 */
export const getDescBundle = (rule) => {
  try {
    if (!rule) return "";

    // Check if sub_heading is provided - if yes, return only sub_heading (no description)
    const subHeading = rule?.sub_heading?.trim();
    if (subHeading) {
      return subHeading;
    }

    // Get cart pricing information
    const pricingInfo = getCartPricingInfo();
    const {
      cartState,
      currencyCode,
      hasFreeProducts: hasFreeProductsFlag,
    } = pricingInfo;

    // Calculate payment amounts
    const {
      paymentAmount,
      remainingAmount,
      finalPriceWithDiscount,
      totalDiscount,
      isRuleDiscountBigger,
      originalCartTotalDecimal,
      cartTotalDecimal,
      ruleAmount,
    } = calculatePaymentAmounts(rule, pricingInfo);

    // Get discount name
    const discountName = getDiscountName(cartState, rule, isRuleDiscountBigger);

    // Build discount info string
    const discountInfo = buildDiscountInfoString({
      originalCartTotalDecimal,
      finalPriceWithDiscount,
      totalDiscount,
      discountName,
      currencyCode,
      cartTotalDecimal,
    });

    // Get effective amount info
    const { shouldUseAmountToShow, isCodFeeException } =
      getEffectiveAmount(rule);

    // Handle COD type
    if (rule?.amount_type === "cod") {
      const codFeeAmount = shouldUseAmountToShow
        ? parseFloat(rule?.amount_to_show || 0)
        : parseFloat(rule?.amount || 0);
      const codFee = codFeeAmount;
      const totalOnDelivery = finalPriceWithDiscount + codFee;
      const totalFormatted = formatCurrency(totalOnDelivery, currencyCode);
      const codFeeFormatted = formatCurrency(codFee, currencyCode);

      if (codFee > 0) {
        return `${discountInfo}. Additional ${codFeeFormatted} COD fee applies. Total amount to pay: ${totalFormatted}`;
      } else {
        return `${discountInfo}. Total amount to pay: ${totalFormatted}`;
      }
    }

    // Handle 100% payment
    if (rule?.amount_type === "percentage" && ruleAmount === 100) {
      const fullAmountFormatted = formatCurrency(paymentAmount, currencyCode);
      return `${discountInfo}. Pay full amount ${fullAmountFormatted} now`;
    }

    // Format amounts
    const paymentAmountFormatted = formatCurrency(paymentAmount, currencyCode);
    const remainingAmountFormatted = formatCurrency(
      remainingAmount,
      currencyCode,
    );

    // Generate description based on rule type
    if (isCodFeeException) {
      return `${discountInfo}. Pay ${paymentAmountFormatted} cod fee now, remaining ${remainingAmountFormatted} on delivery as cod`;
    } else if (shouldUseAmountToShow && rule?.amount_type === "percentage") {
      return `${discountInfo}. Pay ${paymentAmountFormatted} and rest on delivery`;
    } else if (shouldUseAmountToShow) {
      return `${discountInfo}. Pay ${paymentAmountFormatted} now, remaining ${remainingAmountFormatted} on delivery`;
    } else if (rule?.amount_type === "percentage" && ruleAmount !== 100) {
      return `${discountInfo}. Pay ${ruleAmount}% (${paymentAmountFormatted}) now, remaining ${remainingAmountFormatted} on delivery`;
    } else if (remainingAmount === 0) {
      return `${discountInfo}. Pay ${paymentAmountFormatted} now`;
    } else {
      return `${discountInfo}. Pay ${paymentAmountFormatted} now, remaining ${remainingAmountFormatted} on delivery`;
    }
  } catch (error) {
    return "";
  }
};

/**
 * Calculate payment price for a rule
 *
 * Rules:
 * 1. amount_to_show has HIGHEST PRIORITY
 * 2. FREE PRODUCTS EXCEPTION: Calculate percentage from discounted price
 * 3. 100% payment: Use finalPriceWithDiscount (discounted price)
 * 4. Partial percentage: Calculate from ORIGINAL cart total (unless free products)
 *
 * @param {Object} rule - Rule object
 * @returns {string} - Formatted payment price (e.g., "₹566.96")
 */
export const getPriceBundle = (rule) => {
  try {
    if (!rule) return formatCurrency(0);

    // Get cart pricing information
    const pricingInfo = getCartPricingInfo();
    const { currencyCode } = pricingInfo;

    // Calculate payment amounts
    const { paymentAmount, finalPriceWithDiscount } = calculatePaymentAmounts(
      rule,
      pricingInfo,
    );

    // Get effective amount info
    const { shouldUseAmountToShow } = getEffectiveAmount(rule);
    const ruleAmount = parseFloat(
      shouldUseAmountToShow ? rule?.amount_to_show || "0" : rule?.amount || "0",
    );

    let price = paymentAmount;

    // Handle COD type - return total amount including COD fee
    if (rule?.amount_type === "cod") {
      const codFee = shouldUseAmountToShow
        ? parseFloat(rule?.amount_to_show || 0)
        : parseFloat(rule?.amount || 0);
      price = finalPriceWithDiscount + codFee;
    }

    return formatCurrency(Math.max(0, price), currencyCode);
  } catch (error) {
    const pricingInfo = getCartPricingInfo();
    return formatCurrency(0, pricingInfo.currencyCode);
  }
};

/**
 * Remove discount codes that were created via createDiscountCode API
 * This works even in new tabs by checking cart discount codes directly
 * All created discount codes are prefixed with "CODK-" for easy identification
 *
 * Strategy:
 * 1. Check session storage first (works in same tab)
 * 2. Also check cart discount codes for "CODK-" prefix (works in new tabs)
 * 3. Remove all CODK- codes from cart
 *
 * @returns {Promise<void>}
 */

/**
 * Clear partial payment cart attributes
 * This should be called when modal opens to prevent miscalculations from stale attributes
 * Also clears cached cart results from session storage to ensure fresh data on every popup open
 *
 * @returns {Promise<void>}
 */
// export const clearPartialPaymentCartAttributes = async () => {
//   try {
//     // ✅ Sync with otpStore currentCartData
//     addCartAttributesWithOtpStore({
//       _codkFinalDiscountValue: "",
//       _codkFreeVariants: "",
//       _codkAmountType: "",
//       _codkAmountValue: "",
//       _partialPaymentProduct: "",
//       partial_payment_variants: "",
//       _codkPaymentDescription: "",
//     });

//     debugLog("✅ Cleared partial payment cart attributes");
//   } catch (attrError) {
//     // Don't throw - this is non-critical
//   }
// };

/**
 * Check if user navigated from checkout page to cart page (back button navigation)
 * Reload page once if partialPaymentEnabled && partialPaymentFlowVersion === 2
 *
 * This function:
 * 1. Checks if current page is cart page
 * 2. Checks if referrer is checkout page (multiple methods)
 * 3. Verifies partialPaymentEnabled && partialPaymentFlowVersion === 2
 * 4. Reloads page once using sessionStorage to prevent infinite reloads
 *
 * @param {Object} settings - Settings object containing partialPaymentEnabled and partialPaymentFlowVersion
 * @returns {boolean} - True if reload is happening, false otherwise
 */
export const checkAndReloadFromCheckout = (settings) => {
  try {
    const currentPath = window.location.pathname;
    const currentUrl = window.location.href;
    const referrer = document.referrer;
    const partialPaymentEnabled = settings?.partialPaymentEnabled === true;
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

    // Check if we're on cart page
    const isCartPage =
      currentPath.includes("/cart") || currentUrl.includes("/cart");

    // Check if referrer is checkout page (multiple methods)
    const referrerIsCheckout =
      referrer &&
      (referrer.includes("/checkout") ||
        referrer.includes("/checkouts/") ||
        referrer.includes("/checkout?"));

    // Method 2: Check performance navigation API (if available)
    const performanceNavigation =
      window.performance &&
      window.performance.getEntriesByType &&
      window.performance.getEntriesByType("navigation")[0];
    const navigationType = performanceNavigation?.type;
    const isBackNavigation =
      navigationType === "back_forward" || navigationType === 2;

    // Method 3: Check sessionStorage for checkout navigation flag
    const wasOnCheckout = sessionStorage.getItem("codk_was_on_checkout");

    // Combine methods - consider it from checkout if any indicator suggests so
    const isFromCheckout =
      referrerIsCheckout ||
      (isBackNavigation && wasOnCheckout === "true") ||
      (isBackNavigation && !referrer && isCartPage) ||
      (isBackNavigation && isCartPage);

    // Check conditions
    const shouldReload =
      partialPaymentEnabled &&
      partialPaymentFlowVersion === 2 &&
      isCartPage &&
      isFromCheckout;

    if (shouldReload) {
      // Use session storage to ensure we only reload once
      const reloadKey = "codk_reload_from_checkout";
      const hasReloaded = sessionStorage.getItem(reloadKey);

      if (!hasReloaded) {
        sessionStorage.setItem(reloadKey, "true");
        // Clear checkout flag after reload
        sessionStorage.removeItem("codk_was_on_checkout");
        window.location.reload();
        return true;
      } else {
        // Clear the flag after reload is done
        sessionStorage.removeItem(reloadKey);
      }
    }

    return false;
  } catch (reloadError) {
    console.warn("⚠️ Error checking checkout navigation:", reloadError);
    return false;
  }
};

/**
 * Handle partial payment submission bundle
 *
 * Flow:
 * 1. Validate selected rule and cart
 * 2. Check if COD or Full Payment -> Use handleSimpleFlow
 * 3. Get pre-created cart results from session (optimization)
 * 4. Call handlePartialPaymentBundleFlow with cartResult
 * 5. Update OTP store and navigate to next step
 *
 * Optimization:
 * - Reuses cart results from createCartsForEligibleRules (stored in session)
 * - Avoids redundant API calls during checkout
 *
 * @param {number} selectedRule - Selected rule ID
 * @param {Array} ruleSets - Array of rule objects
 * @param {Function} setIsPartialLoading - Loading state setter
 * @param {Function} setError - Error state setter
 * @param {Function} setIsPartialPaymentCartReadyAndUpdated - State setter
 * @param {Function} setStep - Step setter
 * @param {number} cartTotal - Cart total
 * @param {Object} orderSummary - Order summary object
 */
export const handlePartialPaymentSubmitBundle = async (
  selectedRule,
  ruleSets,
  setIsPartialLoading,
  setError,
  setIsPartialPaymentCartReadyAndUpdated,
  setStep,
  cartTotal,
  orderSummary,
) => {
  const otpStore = useOtpStore.getState();

  debugLog("🔵 [handlePartialPaymentSubmitBundle] START", {
    selectedRule,
    timestamp: new Date().toISOString(),
  });

  // Clear any previous errors
  setError("");
  setIsPartialLoading(true);

  try {
    // Validation phase
    if (!selectedRule) {
      throw new Error("Please select a payment option");
    }

    if (!Array.isArray(ruleSets) || ruleSets.length === 0) {
      throw new Error("No payment options available");
    }

    const selectedRuleObj = ruleSets.find((rule) => rule.id === selectedRule);
    if (!selectedRuleObj) {
      throw new Error("Selected payment option is no longer available");
    }

    // Get required data
    const shop = window?.Shopify?.shop;
    if (!shop) {
      throw new Error("Shop information not available");
    }

    // Use currentCartData from OTP store (current cart) instead of cartStore
    const cart = useOtpStore.getState()?.currentCartData;

    if (!cart || !cart.items || cart.items.length === 0) {
      throw new Error("Your cart is empty");
    }

    const currencyCode = window?.Shopify?.currency?.active || "INR";

    // Check if this is COD or Full Payment - use handleSimpleFlow for these cases
    const isCOD = selectedRuleObj?.amount_type === "cod";
    const isFullPercentage =
      selectedRuleObj?.amount_type === "percentage" &&
      selectedRuleObj?.amount === "100.0";

    if (isCOD || isFullPercentage) {
      // Use handleSimpleFlow for COD and full payment
      await handleSimpleFlow(
        cart,
        selectedRuleObj,
        isFullPercentage,
        isCOD,
        setIsPartialPaymentCartReadyAndUpdated,
      );
      otpStore.setIsCartManipulationProcessCompleted(true);
      const nextStep = await getCurrentStep();
      setStep(nextStep);
      return;
    }

    // Get pre-created cart results from session storage
    const cartResults = getSessionValue("partial_payment_cart_results") || [];
    const cartResult = cartResults.find(
      (result) => result.ruleId === selectedRule,
    );

    // if (!cartResult) {
    //   // Fallback: Create carts on-demand if not found in cache
    //   try {
    //     const fallbackCartResults = await createCartsForEligibleRules(true);
    //     const fallbackCartResult = fallbackCartResults.find(
    //       (result) => result.ruleId === selectedRule
    //     );

    //     if (!fallbackCartResult) {
    //       throw new Error(
    //         "Cart results not found. Please refresh the page and try again."
    //       );
    //     }

    //     // Use the fallback result
    //     const cartResultToUse = fallbackCartResult;

    //     // Execute bundle payment flow with the newly created cart result
    //     await handlePartialPaymentBundleFlow(
    //       cart,
    //       selectedRuleObj,
    //       shop,
    //       selectedRule,
    //       currencyCode,
    //       setIsPartialPaymentCartReadyAndUpdated,
    //       cartTotal,
    //       orderSummary,
    //       cartResultToUse
    //     );

    //     otpStore.setIsCartManipulationProcessCompleted(true);
    //     return;
    //   } catch (fallbackError) {
    //     throw new Error(
    //       "Cart results not found. Please refresh the page and try again."
    //     );
    //   }
    // }

    // Execute bundle payment flow for partial payments
    await handlePartialPaymentBundleFlow(
      cart,
      selectedRuleObj,
      shop,
      selectedRule,
      currencyCode,
      setIsPartialPaymentCartReadyAndUpdated,
      cartTotal,
      orderSummary,
      cartResult,
    );

    otpStore.setIsCartManipulationProcessCompleted(true);
    const nextStep = await getCurrentStep();
    setStep(nextStep);
  } catch (error) {
    // Set user-friendly error message
    const errorMessage =
      error.message || "An unexpected error occurred. Please try again.";
    setError(errorMessage);
  } finally {
    // Always clear loading state after a delay to prevent UI flickering
    setTimeout(() => {
      setIsPartialLoading(false);
    }, 100);
  }
};

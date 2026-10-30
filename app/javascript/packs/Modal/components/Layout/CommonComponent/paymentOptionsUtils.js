// paymentOptionsUtils.js - Optimized with comprehensive error prevention
import "../../../utilities/polyfills";
import { createPartialCart, getCart } from "../../../services/otpService";
import {
  getCurrentStep,
  getMachineId,
  getSessionValue,
  setLocalValue,
  addCartAttributesWithOtpStore,
  applyDiscountCodeToOtpStore,
  removeDiscountCodeFromOtpStore,
  formatCurrency,
  getStorefrontCartId,
  debugLog,
} from "../../../utilities/otpUtils";
import {
  applyDiscountCodeToCart,
  removeSelectiveDiscountCodes,
} from "../../../services/cartService";
import useOtpStore from "../../../stores/otpStore";
import {
  handlePartialPaymentBundleFlow,
  getDescBundle,
  updateAllLineItemsDescription,
  removeAllLineItemsDescription,
  getCodkDiscounts,
  getCodkImageURLs,
  calculateRuleOrderLevelDiscountDecimal,
} from "./partialPaymentBundleFuntions";

// ========================================
// CONSTANTS & ENUMS
// ========================================

export const PAYMENT_TYPES = {
  PERCENTAGE: "percentage",
  FIXED: "fixed",
  COD: "cod",
};

export const DISCOUNT_TYPES = {
  PERCENTAGE: "percentage",
  FIXED: "fixed",
  FIXED_AMOUNT: "fixed_amount",
};

export const AMOUNT_CONSTANTS = {
  FULL_PAYMENT_PERCENTAGE: "100.0",
  ZERO: "0",
};

export const MAX_UNIQUE_LINES_FOR_PARTIAL = 45;

// Default values to prevent undefined errors
export const DEFAULT_VALUES = {
  CURRENCY_CODE: "INR",
  LOCALE: "en-IN",
  CART_TOTAL: 0,
  RULE_AMOUNT: 0,
  DISCOUNT_VALUE: 0,
};

// ========================================
// TYPE CHECKING & VALIDATION HELPERS
// ========================================

const safeParseFloat = (value, fallback = 0) => {
  const parsed = parseFloat(value);
  return isNaN(parsed) ? fallback : parsed;
};

/**
 * Safe string trimming
 * @param {any} value - Value to trim
 * @returns {string} Trimmed string or empty string
 */
const safeTrim = (value) => {
  return typeof value === "string" ? value.trim() : "";
};

/**
 * Validate rule object structure
 * @param {Object} rule - Rule object to validate
 * @throws {Error} If rule is invalid
 * @returns {boolean} True if valid
 */
const validateRule = (rule) => {
  if (!rule || typeof rule !== "object") {
    throw new Error("Invalid rule object provided");
  }

  const requiredFields = ["id", "amount_type", "rule_name"];
  for (const field of requiredFields) {
    if (!rule[field]) {
      throw new Error(`Missing required field: ${field} in rule`);
    }
  }

  return true;
};

const validateCart = (cart) => {
  if (!cart) {
    throw new Error("Cart object is null or undefined");
  }

  if (!Array.isArray(cart.items)) {
    throw new Error("Cart items must be an array");
  }

  return true;
};

// ========================================
// UTILITY FUNCTIONS
// ========================================

/**
 * Convert float to integer safely
 * @param {number|string} value - Value to convert
 * @returns {number} Rounded integer
 */
export const convertFloatToInt = (value) => {
  const numericValue = safeParseFloat(value);
  return Math.round(numericValue);
};

/**
 * Check if value is full percentage payment
 * @param {Object} rule - Rule object
 * @returns {boolean} True if full percentage payment
 */
const isFullPercentagePayment = (rule) => {
  return (
    rule.amount === AMOUNT_CONSTANTS.FULL_PAYMENT_PERCENTAGE &&
    rule.amount_type === PAYMENT_TYPES.PERCENTAGE
  );
};

/**
 * Check if value is COD payment
 * @param {Object} rule - Rule object
 * @returns {boolean} True if COD payment
 */
const isCodPayment = (rule) => {
  return rule.amount_type === PAYMENT_TYPES.COD;
};

/**
 * Get cart total with error handling
 * @param {Array} cartItems - Array of cart items
 * @returns {number} Total cart value
 */
const calculateCartTotal = (cartItems, orderSummary) => {
  const cart = useOtpStore.getState().currentCartData;
  // Post-discount total (cents) — min/max cart rules must track this, not original_total_price.
  if (cart && typeof cart.total_price === "number" && cart.total_price >= 0) {
    return cart.total_price / 100;
  }

  if (orderSummary && orderSummary.totalPrice > 0) {
    return orderSummary.totalPrice;
  }

  if (!Array.isArray(cartItems)) {
    console.warn("Cart items is not an array, returning 0");
    return 0;
  }

  return cartItems.reduce((sum, item) => {
    const price = safeParseFloat(item?.presentment_price || item?.price);
    const quantity = safeParseFloat(item?.quantity);
    return sum + price * quantity;
  }, 0);
};

/**
 * Filter rules based on cart total with validation
 * @param {Array} rules - Array of rules
 * @param {number} cartTotal - Cart total amount
 * @returns {Array} Filtered rules
 */
const filterRulesByCartTotal = (rules, cartTotal) => {
  if (!Array.isArray(rules)) {
    console.warn("Rules is not an array, returning empty array");
    return [];
  }

  return rules.filter((rule) => {
    try {
      validateRule(rule);

      const min = safeParseFloat(rule.min_cart_range);
      const max = safeParseFloat(rule.max_cart_range);

      // No range restrictions
      if (min === 0 && max === 0) return true;

      // Only minimum restriction
      if (max === 0 && cartTotal >= min) return true;

      // Only maximum restriction
      if (min === 0 && cartTotal <= max) return true;

      // Both min and max restrictions
      return cartTotal >= min && cartTotal <= max;
    } catch (error) {
      console.error("Error validating rule:", error, rule);
      return false;
    }
  });
};

// ========================================
// MAIN BUSINESS LOGIC FUNCTIONS
// ========================================

/**
 * Initialize cart and filter rules based on cart total
 * @param {Function} setCartTotal - Set cart total state
 * @param {Function} setRuleSets - Set rule sets state
 * @param {Function} setSelectedRule - Set selected rule state
 * @param {Function} setIsFullPercentage - Set full percentage state
 * @param {Function} setIsCOD - Set COD state
 * @param {Function} setIsLoaderLoading - Set loader loading state
 */
export const initializeCartAndRules = async (
  setCartTotal,
  setRuleSets,
  setSelectedRule,
  setIsFullPercentage,
  setIsCOD,
  setIsLoaderLoading,
  orderSummary = null // Added orderSummary
) => {
  try {
    const storedRules = getSessionValue("ruleSets");

    if (!Array.isArray(storedRules) || storedRules.length === 0) {
      setRuleSets([]);
      setIsLoaderLoading(false);
      return;
    }

    const currentCartData = useOtpStore.getState()?.currentCartData;
    let cart = currentCartData;

    if (!cart || !cart.items || cart.items.length === 0) {
      cart = await getCart(true);
    }

    validateCart(cart);

    const cartTotal = calculateCartTotal(cart.items, orderSummary); // Pass orderSummary

    setCartTotal(cartTotal);

    let filteredRules = filterRulesByCartTotal(storedRules, cartTotal);

    // Hide partial-payment options when the cart has too many unique lines;
    // keep COD and full-payment options available.
    const uniqueLineCount = Array.isArray(cart.items) ? cart.items.length : 0;
    if (uniqueLineCount >= MAX_UNIQUE_LINES_FOR_PARTIAL) {
      filteredRules = filteredRules.filter(
        (rule) => isCodPayment(rule) || isFullPercentagePayment(rule)
      );
    }

    if (filteredRules.length > 0) {
      setRuleSets(filteredRules);
      const firstRule = filteredRules[0];
      setSelectedRule(firstRule.id);

      const isFullPercentage = isFullPercentagePayment(firstRule);
      const isCOD = isCodPayment(firstRule);

      setIsFullPercentage(isFullPercentage);
      setIsCOD(isCOD);
    } else {
      setRuleSets([]);
    }
  } catch (error) {
    console.error("Error in initializeCartAndRules:", error);
    setRuleSets([]);
  } finally {
    setIsLoaderLoading(false);
  }
};

export const handleRuleSelection = (
  id,
  ruleSets,
  setSelectedRule,
  setError,
  setIsCOD,
  setIsFullPercentage
) => {
  try {
    if (!id) {
      throw new Error("Rule ID is required");
    }

    if (!Array.isArray(ruleSets)) {
      throw new Error("Rule sets must be an array");
    }

    const selectedRule = ruleSets.find((rule) => rule.id === id);

    if (!selectedRule) {
      throw new Error(`Rule with ID ${id} not found`);
    }

    validateRule(selectedRule);

    setSelectedRule(id);
    setError("");

    const isCOD = isCodPayment(selectedRule);
    const isFullPercentage = isFullPercentagePayment(selectedRule);

    setIsCOD(isCOD);
    setIsFullPercentage(isFullPercentage);
  } catch (error) {
    console.error("Error in handleRuleSelection:", error);
    setError(error.message || "Error selecting payment option");
  }
};

export const calculateRulePrice = (
  rule,
  cartTotal,
  orderSummary,
  currencyCode = DEFAULT_VALUES.CURRENCY_CODE
) => {
  try {
    validateRule(rule);

    const safeCartTotal = safeParseFloat(cartTotal);
    const ruleAmount = safeParseFloat(rule.amount);
    const discountValue = safeParseFloat(rule.discount_value);
    const amountToShow = safeTrim(rule.amount_to_show);

    const hasRuleDiscount = Boolean(rule.discount_code && discountValue > 0);
    const isPercentageDiscount =
      rule.discount_type === DISCOUNT_TYPES.PERCENTAGE;

    if (amountToShow && !isNaN(parseFloat(amountToShow))) {
      return formatCurrency(parseFloat(amountToShow), currencyCode);
    }

    let discountAmount = 0;

    if (hasRuleDiscount) {
      discountAmount = isPercentageDiscount
        ? (safeCartTotal * discountValue) / 100
        : discountValue;
    } else if (
      orderSummary?.discountDetails?.code &&
      safeParseFloat(orderSummary.discountDetails.value) > 0
    ) {
      const summaryDiscountValue = safeParseFloat(
        orderSummary.discountDetails.value
      );
      const summaryDiscountType = orderSummary.discountDetails.type;

      discountAmount =
        summaryDiscountType === DISCOUNT_TYPES.PERCENTAGE
          ? (safeCartTotal * summaryDiscountValue) / 100
          : summaryDiscountValue;
    }

    const cart = useOtpStore.getState().currentCartData;
    const totalAfterDiscount =
      cart && cart.total_price
        ? (cart.total_price || 0) / 100
        : Math.max(0, safeCartTotal - discountAmount);

    let finalPrice = 0;

    switch (rule.amount_type) {
      case PAYMENT_TYPES.COD:
        finalPrice = totalAfterDiscount + ruleAmount;
        break;

      case PAYMENT_TYPES.FIXED:
        finalPrice = ruleAmount;
        break;

      case PAYMENT_TYPES.PERCENTAGE:
        if (rule.amount === AMOUNT_CONSTANTS.FULL_PAYMENT_PERCENTAGE) {
          if (hasRuleDiscount) {
            const ruleDiscountAmount = isPercentageDiscount
              ? (safeCartTotal * discountValue) / 100
              : discountValue;
            finalPrice = Math.max(0, safeCartTotal - ruleDiscountAmount);
          } else {
            finalPrice = totalAfterDiscount;
          }
        } else {
          finalPrice = (totalAfterDiscount * ruleAmount) / 100;
        }
        break;

      default:
        console.warn(`Unknown amount type: ${rule.amount_type}`);
        finalPrice = 0;
    }

    const result = Math.max(0, finalPrice);

    return formatCurrency(result, currencyCode);
  } catch (error) {
    console.error("Error calculating rule price:", error);
    return formatCurrency(0, currencyCode);
  }
};

/**
 * Generate detailed description for a rule with comprehensive breakdown
 * @param {Object} rule - Rule object
 * @param {number} cartTotal - Cart total amount
 * @param {Object} orderSummary - Order summary object
 * @param {string} currencyCode - Currency code
 * @param {Function} getPrice - Function to get price
 * @returns {string} Detailed rule description
 */

export const generateRuleDescription = (
  rule,
  cartTotal,
  orderSummary,
  currencyCode,
  getPrice
) => {
  try {
    validateRule(rule);

    const safeCartTotal = safeParseFloat(cartTotal);
    const ruleAmount = safeParseFloat(rule.amount);
    const discountValue = safeParseFloat(rule.discount_value);
    const amountToShow = safeTrim(rule.amount_to_show);
    const subHeading = safeTrim(rule.sub_heading);

    const isCodRule = rule.amount_type === PAYMENT_TYPES.COD;
    const hasRuleDiscount = Boolean(rule.discount_code && discountValue > 0);
    const isPercentageDiscount =
      rule.discount_type === DISCOUNT_TYPES.PERCENTAGE;

    const hasOrderSummaryDiscount = Boolean(
      orderSummary?.discountDetails?.code &&
        safeParseFloat(orderSummary.discountDetails.value) > 0
    );

    // Priority 1: Use subheading if provided
    if (subHeading) {
      return subHeading;
    }

    // Calculate discount amounts and totals
    let totalOrderValue = safeCartTotal;

    // Get the exact discounted price from cart (same as Order summary)
    const cart = useOtpStore.getState().currentCartData;
    let totalOrderValueAfterDiscount =
      cart && cart.total_price ? (cart.total_price || 0) / 100 : safeCartTotal;

    let discountAmount = 0;
    let discountCode = "";
    let discountType = "";

    // Calculate discount amount
    if (hasRuleDiscount) {
      discountAmount = isPercentageDiscount
        ? (safeCartTotal * discountValue) / 100
        : discountValue;
      discountCode = rule.discount_code;
      discountType = rule.discount_type;
    } else if (hasOrderSummaryDiscount) {
      const summaryDiscountValue = safeParseFloat(
        orderSummary.discountDetails.value
      );
      const summaryDiscountType = orderSummary.discountDetails.type;

      discountAmount =
        summaryDiscountType === DISCOUNT_TYPES.PERCENTAGE
          ? (safeCartTotal * summaryDiscountValue) / 100
          : summaryDiscountValue;
      discountCode = orderSummary.discountDetails.code;
      discountType = summaryDiscountType;
    }

    // totalOrderValueAfterDiscount is now set directly from cart.total_price above
    // totalOrderValueAfterDiscount = Math.max(0, safeCartTotal - discountAmount);

    // Calculate payment amounts based on rule type
    let toBePaidNow = 0;
    let toBePaidOnDelivery = 0;
    let codFee = 0;

    // Priority 2: Handle amount_to_show
    if (amountToShow && !isNaN(parseFloat(amountToShow))) {
      toBePaidNow = parseFloat(amountToShow);
      toBePaidOnDelivery = Math.max(
        0,
        totalOrderValueAfterDiscount - toBePaidNow
      );
    }
    // Handle different payment types
    if (isFullPercentagePayment(rule)) {
      if (hasRuleDiscount) {
        const ruleDiscountAmount = isPercentageDiscount
          ? (safeCartTotal * discountValue) / 100
          : discountValue;
        toBePaidNow = Math.max(0, safeCartTotal - ruleDiscountAmount);
      } else {
        toBePaidNow = totalOrderValueAfterDiscount;
      }
      toBePaidOnDelivery = 0;
    } else if (isCodRule) {
      codFee = ruleAmount;
      toBePaidNow = 0;
      toBePaidOnDelivery = totalOrderValueAfterDiscount + codFee;
    } else if (rule.amount_type === PAYMENT_TYPES.FIXED) {
      toBePaidNow = ruleAmount;

      toBePaidNow = Math.min(toBePaidNow, totalOrderValueAfterDiscount);
      toBePaidOnDelivery = Math.max(
        0,
        totalOrderValueAfterDiscount - toBePaidNow
      );
    } else if (rule.amount_type === PAYMENT_TYPES.PERCENTAGE) {
      toBePaidNow = (totalOrderValueAfterDiscount * ruleAmount) / 100;
      toBePaidOnDelivery = Math.max(
        0,
        totalOrderValueAfterDiscount - toBePaidNow
      );
    }

    let description = "";

    if (isFullPercentagePayment(rule)) {
      if (hasRuleDiscount) {
        const ruleDiscountAmount = isPercentageDiscount
          ? (safeCartTotal * discountValue) / 100
          : discountValue;
        const finalAmount = Math.max(0, safeCartTotal - ruleDiscountAmount);
        description = `Order total is ${formatCurrency(
          totalOrderValue,
          currencyCode
        )} (${formatCurrency(
          finalAmount,
          currencyCode
        )} after ${discountCode} discount).`;
      } else if (discountAmount > 0) {
        description = `Order total is ${formatCurrency(
          totalOrderValue,
          currencyCode
        )} (${formatCurrency(
          totalOrderValueAfterDiscount,
          currencyCode
        )} after ${discountCode} discount).`;
      } else {
        description = `Order total is ${formatCurrency(
          totalOrderValue,
          currencyCode
        )}.`;
      }
    } else if (isCodRule) {
      if (codFee > 0) {
        if (discountAmount > 0) {
          description = `Order total is ${formatCurrency(
            totalOrderValue,
            currencyCode
          )} (${formatCurrency(
            totalOrderValueAfterDiscount,
            currencyCode
          )} after ${discountCode} discount): pay ${formatCurrency(
            toBePaidOnDelivery,
            currencyCode
          )} on delivery (includes ${formatCurrency(
            codFee,
            currencyCode
          )} COD fee).`;
        } else {
          description = `Order total is ${formatCurrency(
            totalOrderValue,
            currencyCode
          )}: pay ${formatCurrency(
            toBePaidOnDelivery,
            currencyCode
          )} on delivery (includes ${formatCurrency(
            codFee,
            currencyCode
          )} COD fee).`;
        }
      } else {
        if (discountAmount > 0) {
          description = `Order total is ${formatCurrency(
            totalOrderValue,
            currencyCode
          )} (${formatCurrency(
            totalOrderValueAfterDiscount,
            currencyCode
          )} after ${discountCode} discount): pay on delivery with no extra charges.`;
        } else {
          description = `Order total is ${formatCurrency(
            totalOrderValue,
            currencyCode
          )}: pay on delivery with no extra charges.`;
        }
      }
    } else {
      if (discountAmount > 0) {
        description = `Order total is ${formatCurrency(
          totalOrderValue,
          currencyCode
        )} (${formatCurrency(
          totalOrderValueAfterDiscount,
          currencyCode
        )} after ${discountCode} discount): pay ${formatCurrency(
          toBePaidNow,
          currencyCode
        )} now and ${formatCurrency(
          toBePaidOnDelivery,
          currencyCode
        )} on delivery.`;
      } else {
        description = `Order total is ${formatCurrency(
          totalOrderValue,
          currencyCode
        )}: pay ${formatCurrency(
          toBePaidNow,
          currencyCode
        )} now and ${formatCurrency(
          toBePaidOnDelivery,
          currencyCode
        )} on delivery.`;
      }
    }

    return description;
  } catch (error) {
    console.error("Error generating rule description:", error);
    return "Payment option available.";
  }
};

export const addCartAttributes = async (isFullPercentage, isCOD) => {
  try {
    const cart = await getCart(true);
    validateCart(cart);

    const sessionId = getMachineId();
    if (!sessionId) {
      throw new Error("Unable to get machine ID");
    }

    let attributes = {
      _codkSessionId: sessionId,
    };

    if (isFullPercentage) {
      attributes = {
        ...attributes,
        partial_payment_variants: null,
        _partialPaymentProduct: true,
      };
    } else if (isCOD) {
      attributes = {
        ...attributes,
        partial_payment_variants: null,
        _partialPaymentProduct: null,
      };
    } else {
      const variants = cart.items
        .map((item) => item?.variant_id)
        .filter(Boolean); // Remove null/undefined values

      if (variants.length === 0) {
        throw new Error("No valid variant IDs found in cart");
      }

      attributes = {
        ...attributes,
        partial_payment_variants: JSON.stringify(
          variants.map((v) => Number(v)).filter((n) => !isNaN(n))
        ),
        _partialPaymentProduct: true,
      };
    }

    await executePost({ attributes });

    if (!isFullPercentage && !isCOD) {
      await getCart(true); // Refresh cart for partial payment
    }
  } catch (error) {
    console.error("Error in addCartAttributes:", error);
    throw new Error(`Failed to update cart attributes: ${error.message}`);
  }
};

// ========================================
// COMPLEX WORKFLOW FUNCTIONS
// ========================================

export const handleSimpleFlow = async (
  cart,
  selectedRuleObj,
  isFullPercentage,
  isCOD,
  setIsPartialPaymentCartReadyAndUpdated
) => {
  try {
    const settings = getSessionValue("settingSession");
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

    if (partialPaymentFlowVersion === 2) {
      // Handle null/undefined cases
      const amountType =
        selectedRuleObj?.amount_type != null
          ? selectedRuleObj.amount_type
          : "0";
      const amountValue =
        selectedRuleObj?.amount != null ? selectedRuleObj.amount : "0";

      // ✅ Use patch instead of API call for version 2
      addCartAttributesWithOtpStore({
        _codkAmountType: amountType,
        _codkAmountValue: amountValue,
      });
    }

    // Check if rule's discount is bigger than existing discount before applying
    const ruleDiscountCode = selectedRuleObj?.discount_code?.trim();
    const ruleDiscountValueStr = selectedRuleObj?.discount_value || "0";
    const ruleDiscountType = selectedRuleObj?.discount_type || "fixed";
    const ruleDiscountValueNum = parseFloat(ruleDiscountValueStr || 0);

    // Use currentCartData from OTP store (current cart) instead of cartStore
    const currentCartState = useOtpStore.getState()?.currentCartData;
    const currentCartTotalDecimal = (currentCartState?.total_price || 0) / 100;
    const originalCartTotalDecimal =
      typeof currentCartState?.original_total_price === "number"
        ? currentCartState.original_total_price / 100
        : ((currentCartState?.total_price || 0) + (currentCartState?.total_discount || 0)) / 100;

    const lineLevelDiscountDecimal = (currentCartState?.items || []).reduce((sum, item) => {
      const hasLineLevelDiscounts =
        item?.line_level_discount_allocations &&
        item.line_level_discount_allocations.length > 0;
      if (!hasLineLevelDiscounts) return sum;
      const cents =
        item?.line_level_total_discount ||
        (item?.line_level_discount_allocations || []).reduce((s, alloc) => s + (alloc?.amount || 0), 0);
      return sum + cents / 100;
    }, 0);

    const existingOrderLevelDiscountValueDecimal =
      ((currentCartState?.cart_level_discount_applications || []).reduce((sum, d) => {
        return sum + (d?.total_allocated_amount || 0);
      }, 0) / 100) || 0;

    // Calculate rule's discount value
    let ruleDiscountValue = 0;
    if (ruleDiscountValueNum > 0) {
      if (ruleDiscountType === "percentage") {
        ruleDiscountValue =
          ((Math.max(0, originalCartTotalDecimal - lineLevelDiscountDecimal)) * ruleDiscountValueNum) / 100;
      } else {
        ruleDiscountValue = ruleDiscountValueNum;
      }
    }

    // Only apply rule's discount code if:
    // 1. Rule has a discount code AND
    // 2. (Rule discount value > existing cart discount) OR (no existing discount)
    const shouldApplyRuleDiscount =
      ruleDiscountCode &&
      ruleDiscountCode !== "" &&
      (ruleDiscountValue > existingOrderLevelDiscountValueDecimal ||
        existingOrderLevelDiscountValueDecimal === 0);

    if (shouldApplyRuleDiscount) {
      // Remove existing discount codes first before applying the rule's discount
      try {
        await removeDiscountCodeFromOtpStore();
      } catch (removeError) {
        console.warn("Error removing existing discount codes:", removeError);
      }

      // Apply rule's discount code
      await applyDiscountCodeToOtpStore(ruleDiscountCode);
    } else if (ruleDiscountCode && ruleDiscountCode !== "") {
      // Don't apply - keep existing discount if it's bigger
    } else {
      await removeDiscountCodeFromOtpStore();
    }

    // Update cart attributes
    const sessionId = getMachineId();
    if (!sessionId) {
      throw new Error("Unable to get machine ID");
    }

    // Restrict checkout to COD-only when the merchant enabled it on this COD rule.
    // Read by the payment & delivery Shopify Functions via the _codkCheckoutMode
    // cart attribute. Always written (empty when not restricted) so a previous
    // selection never leaves a stale restriction on the cart.
    const restrictCodOnly =
      isCOD &&
      (selectedRuleObj?.checkout_cod_only === true ||
        selectedRuleObj?.checkout_cod_only === "true");

    let attributes = {
      _codkSessionId: sessionId,
      _codkCheckoutMode: restrictCodOnly ? "cod_only" : "",
    };

    // Always compute _codkDiscounts (and friends) for COD / Full Payment too (parity with Svelte)
    try {
      const effectiveCart = currentCartState || cart || {};

      const ruleOrderLevelDiscountAmount = calculateRuleOrderLevelDiscountDecimal(
        selectedRuleObj,
        originalCartTotalDecimal,
        lineLevelDiscountDecimal
      );
      const ruleOrderLevelDiscountCode = (selectedRuleObj?.discount_code || "").trim();
      const ruleOrderLevelDiscount =
        ruleOrderLevelDiscountAmount > 0 && ruleOrderLevelDiscountCode
          ? { amount: ruleOrderLevelDiscountAmount, code: ruleOrderLevelDiscountCode }
          : null;

      const codkDiscounts = getCodkDiscounts(
        effectiveCart?.items || [],
        effectiveCart?.cart_level_discount_applications || [],
        { ruleOrderLevelDiscount }
      );
      if (codkDiscounts) {
        attributes._codkDiscounts = codkDiscounts;
      }

      const codkImageURLs = getCodkImageURLs(effectiveCart?.items || []);
      if (codkImageURLs) {
        attributes._codkImageURLs = codkImageURLs;
      }

      const partialDummyVariantId =
        typeof sessionStorage !== "undefined"
          ? sessionStorage.getItem("partialDummyVariantId")
          : null;
      if (partialDummyVariantId) {
        attributes._partial_product_variant = partialDummyVariantId;
      }
    } catch (e) {
      console.warn("[PartialPayment] Failed to compute _codkDiscounts in React simple flow:", e);
    }

    if (isFullPercentage) {
      attributes = {
        ...attributes,
        partial_payment_variants: null,
        _partialPaymentProduct: true,
      };
    } else if (isCOD) {
      attributes = {
        ...attributes,
        partial_payment_variants: null,
        _partialPaymentProduct: null,
      };
    }

    // ✅ Sync with otpStore currentCartData for UI consistency using patch instead of API
    addCartAttributesWithOtpStore(attributes);

    // Handle descriptions based on payment type
    if (isFullPercentage) {
      // For full payment: Always remove any existing descriptions (regardless of flow version)
      await removeAllLineItemsDescription();
    } else if (isCOD && partialPaymentFlowVersion === 2) {
      // For COD: Add description (only for flow version 2)
      const ruleDescription =
        getDescBundle(selectedRuleObj) || "Payment option selected";
      await updateAllLineItemsDescription(ruleDescription);
    }

    setIsPartialPaymentCartReadyAndUpdated(true);
  } catch (error) {
    console.error("Error in handleSimpleFlow:", error);
    throw new Error(`Simple flow failed: ${error.message}`);
  }
};

export const handlePartialPaymentFlow = async (
  cart,
  selectedRuleObj,
  shop,
  selectedRule,
  currencyCode,
  setIsPartialPaymentCartReadyAndUpdated,
  cartTotal,
  orderSummary
) => {
  try {
    if (!shop) {
      throw new Error("Shop parameter is required");
    }

    if (!selectedRule) {
      throw new Error("Selected rule is required");
    }

    // Use currentCartData from OTP store (current cart) instead of cartStore
    const currentCart = useOtpStore.getState()?.currentCartData;

    if (!currentCart || !currentCart.items) {
      throw new Error("Cart data is missing");
    }

    // 🔍 STEP 1: Store original cart items with their properties for later reference
    const originalCartItemsMap = new Map();
    currentCart.items.forEach((item) => {
      // Check both variant_id and id fields, and include items even with empty properties
      const variantId = item.variant_id || item.id;
      if (variantId) {
        // Store properties even if empty object, so we can preserve the structure
        originalCartItemsMap.set(variantId.toString(), item.properties || {});
      }
    });

    debugLog(
      "Original cart items properties map:",
      Object.fromEntries(originalCartItemsMap)
    );

    // Format and validate cart items
    const items = formatCartItemsForPartial(currentCart.items);
    if (items.length === 0) {
      throw new Error("No valid items found for partial payment");
    }

    // For bundle flow, skip creating partial cart and just add amount attributes

    // Create partial cart
    const response = await createPartialCart(shop, selectedRule, items);
    const data = response?.data?.cartItems || response?.data;

    if (!data || !Array.isArray(data)) {
      throw new Error("Invalid response from partial cart creation");
    }

    setLocalValue("partialCartData", data);

    // Generate rule description for cart items
    const ruleDescription = generateRuleDescription(
      selectedRuleObj,
      cartTotal,
      orderSummary,
      currencyCode
    );

    // Transform cart items with only the rule description
    const cartItems = transformToCartLineItems(
      data,
      currencyCode,
      ruleDescription
    );

    if (cartItems.length === 0) {
      throw new Error("Failed to transform cart items");
    }

    // 🔄 STEP 2: Enhance cartItems with properties from original items
    const cartItemsWithTransferredProperties = cartItems.map((cartItem) => {
      // Find the corresponding partial cart data item
      const partialDataItem = data.find((d) => d.variantId === cartItem.id);

      if (partialDataItem && partialDataItem.originalVariantId) {
        // Get properties from original cart item
        const originalProperties = originalCartItemsMap.get(
          partialDataItem.originalVariantId.toString()
        );

        if (originalProperties && Object.keys(originalProperties).length > 0) {
          // Merge original properties with existing cart item properties
          return {
            ...cartItem,
            properties: {
              ...(cartItem.properties || {}), // Keep existing properties (like description)
              ...originalProperties, // Add original properties (like "Add Your Name")
            },
          };
        }
      }

      // Return cart item as-is if no properties to transfer
      return cartItem;
    });

    // ✅ Sync with otpStore currentCartData for UI consistency
    const otpStore = useOtpStore.getState();
    if (otpStore.patchCurrentCartData) {
      // We need to transform the items to match Shopify cart item format roughly
      // so the Order Summary can still render them.
      const patchedItems = cartItemsWithTransferredProperties.map((item) => {
        const partialInfo = data.find((d) => d.variantId === item.id);
        return {
          variant_id: item.id,
          id: item.id,
          quantity: item.quantity,
          title: partialInfo?.title || "Partial Payment Item",
          presentment_price: partialInfo?.cost || 0,
          price: (partialInfo?.cost || 0) * 100, // Shopify uses cents usually, but otpStore might use decimals
          properties: item.properties,
          image: partialInfo?.imageUrl || "",
        };
      });

      otpStore.patchCurrentCartData({
        items: patchedItems,
        total_price: patchedItems.reduce(
          (sum, item) => sum + item.presentment_price * item.quantity,
          0
        ),
      });
    }

    // Apply discount if applicable using otpStore
    if (selectedRuleObj?.discount_code) {
      await applyDiscountCodeToOtpStore(selectedRuleObj.discount_code);
    } else {
      await removeDiscountCodeFromOtpStore();
    }

    // Extract partial payment variant IDs from createPartialCart response
    // These are the actual partial payment variants, not the original product variants
    const partialPaymentVariantIds = data
      .map((item) => item?.variantId)
      .filter((id) => id != null)
      .map((id) => Number(id))
      .filter((n) => !isNaN(n));

    // Add cart attributes directly (not using cart store)
    const sessionId = getMachineId();
    if (!sessionId) {
      throw new Error("Unable to get machine ID");
    }

    const attributes = {
      _codkSessionId: sessionId,
      partial_payment_variants: JSON.stringify(partialPaymentVariantIds),
      _partialPaymentProduct: true,
      // Partial payment is a prepaid flow — never restrict checkout to COD-only.
      // Clear any stale restriction left by a previously selected COD rule.
      _codkCheckoutMode: "",
    };

    // await executePost({ attributes });

    // ✅ Sync with otpStore currentCartData for UI consistency
    addCartAttributesWithOtpStore(attributes);

    setIsPartialPaymentCartReadyAndUpdated(true);
  } catch (error) {
    console.error("Error in handlePartialPaymentFlow:", error);
    throw new Error(`Partial payment flow failed: ${error.message}`);
  }
};

export const formatCartItemsForPartial = (items) => {
  if (!Array.isArray(items)) {
    console.error("Items must be an array");
    return [];
  }

  return items
    .filter((item) => item && item.variant_id) // Filter out invalid items
    .map((item) => ({
      cost: safeParseFloat(item.presentment_price),
      totalQuantity: Math.max(1, safeParseFloat(item.quantity)), // Ensure minimum quantity of 1
      title: item.title || "Unknown Product",
      imageUrl: item.image || "",
      variantId: item.variant_id.toString(),
    }));
};

export const transformToCartLineItems = (
  items,
  currencyCode,
  ruleDescription = ""
) => {
  if (!Array.isArray(items)) {
    console.error("Items must be an array for transformation");
    return [];
  }

  return items
    .filter((item) => item && item.variantId) // Filter out invalid items
    .map((item) => {
      const quantity = Math.max(1, safeParseFloat(item.totalQuantity));

      return {
        id: item.variantId,
        quantity: quantity,
        properties: {
          description: ruleDescription || "Partial payment option selected",
        },
      };
    });
};

export const removeDiscountCodeFromCart = async (cart) => {
  try {
    const cartId = getStorefrontCartId(cart?.token);
    if (!cartId) {
      debugLog("No valid cart ID for discount removal");
      return;
    }

    await applyDiscountCodeToCart(cartId, "");
  } catch (error) {
    console.error("Error removing discount code:", error);
    // Don't throw here as this is often a non-critical operation
  }
};

export const removePartialPaymentRuleSetDiscountCodeFromCart = async (cart) => {
  try {
    const cartId = getStorefrontCartId(cart?.token);
    if (!cartId) {
      return;
    }

    const ruleSets = getSessionValue("ruleSets");
    if (!ruleSets || !Array.isArray(ruleSets)) {
      return;
    }

    const cartDiscountCodes = cart?.discount_codes || [];
    if (cartDiscountCodes.length === 0) {
      return;
    }

    const ruleSetDiscountCodes = ruleSets
      .filter((rule) => rule.is_enabled && rule.discount_code)
      .map((rule) => rule.discount_code.toLowerCase().trim());

    if (ruleSetDiscountCodes.length === 0) {
      return;
    }

    // Get codes to KEEP (non-ruleset codes)
    const codesToKeep = cartDiscountCodes
      .filter(
        (cartCode) =>
          !ruleSetDiscountCodes.includes(cartCode.code?.toLowerCase().trim())
      )
      .map((cartCode) => cartCode.code);

    const matchingCodes = cartDiscountCodes.filter((cartCode) =>
      ruleSetDiscountCodes.includes(cartCode.code?.toLowerCase().trim())
    );

    if (matchingCodes.length === 0) {
      return;
    }

    // Update cart with only the codes we want to keep
    await removeSelectiveDiscountCodes(cartId, codesToKeep);
  } catch (error) {
    console.error("Error removing discount code:", error);
  }
};

export const hasRuleDiscount = (rule) => {
  if (!rule) return false;
  return Boolean(rule.discount_code && safeParseFloat(rule.discount_value) > 0);
};

export const hasOrderSummaryDiscount = (orderSummary) => {
  if (!orderSummary?.discountDetails) return false;
  return Boolean(
    orderSummary.discountDetails.code &&
      safeParseFloat(orderSummary.discountDetails.value) > 0
  );
};

export const handlePaymentSubmit = async (
  isFullPercentage,
  isCOD,
  selectedRule,
  ruleSets,
  setIsPartialLoading,
  setError,
  setIsPartialPaymentCartReadyAndUpdated,
  handleSkip,
  setStep,
  cartTotal,
  orderSummary
) => {
  const otpStore = useOtpStore.getState();
  setError("");
  setIsPartialLoading(true);

  try {
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

    const shop = window?.Shopify?.shop;
    if (!shop) {
      throw new Error("Shop information not available");
    }

    const cart = useOtpStore.getState()?.currentCartData;

    if (!cart || !cart.items || cart.items.length === 0) {
      throw new Error("Your cart is empty");
    }

    const currencyCode =
      window?.Shopify?.currency?.active || DEFAULT_VALUES.CURRENCY_CODE;
    const isSimpleFlow = isFullPercentage || isCOD;

    if (isSimpleFlow) {
      await handleSimpleFlow(
        cart,
        selectedRuleObj,
        isFullPercentage,
        isCOD,
        setIsPartialPaymentCartReadyAndUpdated
      );
      otpStore.setIsCartManipulationProcessCompleted(true);
      const nextStep = await getCurrentStep();
      setStep(nextStep);
    } else {
      await handlePartialPaymentFlow(
        cart,
        selectedRuleObj,
        shop,
        selectedRule,
        currencyCode,
        setIsPartialPaymentCartReadyAndUpdated,
        cartTotal,
        orderSummary
      );

      const nextStep = await getCurrentStep();
      setStep(nextStep);
    }
  } catch (error) {
    const errorMessage =
      error.message || "An unexpected error occurred. Please try again.";
    setError(errorMessage);
  } finally {
    setTimeout(() => {
      setIsPartialLoading(false);
    }, 100);
  }
};

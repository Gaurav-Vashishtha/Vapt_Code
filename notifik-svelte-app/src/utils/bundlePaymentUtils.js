import { cartFetch } from "./shopifyCartApi.js";
import { getCart } from "../services/otpService.js";
import { otpStore } from "../stores/otpStore.js";
import { formatCurrency, getShopDomain } from "./helpers.js";
import { getSessionValue } from "../services/sessionService.js";
import { getStorefrontCartId } from "../utilities/otpUtils.js";
import { createLightweightGraphQLClient } from "../services/lightweightGraphQLClient.js";
import { uiText, UI_TEXT_DEFAULTS } from "./uiCustomization.js";
import { isGiftLine } from "../services/freeGiftService.js";

export const getFreeVariantIds = (cartItems) => {
  const freeItems = (cartItems || []).filter((item) => {
    const finalLinePrice = item?.final_line_price || 0;
    const finalPrice = item?.final_price || 0;
    return finalLinePrice === 0 || finalPrice === 0;
  });

  if (freeItems.length === 0) return "";
  const variantCountMap = new Map();
  freeItems.forEach((item) => {
    const id = item?.variant_id ?? item?.id;
    if (id != null)
      variantCountMap.set(
        id,
        (variantCountMap.get(id) || 0) + (item?.quantity || 1),
      );
  });

  return Array.from(variantCountMap.entries())
    .map(([id, c]) => `${id}:${c}`)
    .join(",");
};

const normalizeVariantId = (variantId) => {
  if (!variantId) return "";
  const raw = String(variantId);
  if (raw.includes("/")) return raw.split("/").pop() || "";
  if (raw.includes(":")) return raw.split(":")[0] || "";
  return raw;
};

const parseVariantCounts = (freeVariantsValue) => {
  const map = new Map();
  if (!freeVariantsValue || typeof freeVariantsValue !== "string") return map;

  freeVariantsValue
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .forEach((pair) => {
      const [rawId, rawCount] = pair.split(":");
      const id = normalizeVariantId(rawId);
      const count = rawCount != null ? parseInt(rawCount, 10) : 0;
      if (!id) return;
      map.set(id, (map.get(id) || 0) + (Number.isFinite(count) ? count : 0));
    });

  return map;
};

export const getCodkDiscounts = (
  cartItems = [],
  cartLevelDiscountApplications = [],
  options = { ruleOrderLevelDiscount: null, skipFreeItems: false },
) => {
  const discountEntries = [];

  // Calculate line-level discounts per variant
  // Only count discounts that are truly line-level (have line_level_discount_allocations)
  // If line_level_discount_allocations is empty but total_discount > 0, it's from order-level allocation
  const variantDiscountMap = new Map(); // variantId -> { discount, code }
  (cartItems || []).forEach((item) => {
    const variantId = item?.variant_id || item?.id;
    if (variantId == null || isGiftLine(item)) return;

    const hasLineLevelDiscounts =
      item?.line_level_discount_allocations &&
      item.line_level_discount_allocations.length > 0;

    if (hasLineLevelDiscounts) {
      const lineDiscount =
        item?.line_level_total_discount ||
        (item?.line_level_discount_allocations || []).reduce((sum, alloc) => {
          return sum + (alloc?.amount || 0);
        }, 0);
      const discountCode =
        item?.line_level_discount_allocations?.[0]?.discount_application
          ?.title ||
        item?.line_level_discount_allocations?.[0]?.discount_application
          ?.code ||
        "";

      if (lineDiscount > 0) {
        const currentData = variantDiscountMap.get(variantId) || {
          discount: 0,
          code: "",
        };
        variantDiscountMap.set(variantId, {
          discount: currentData.discount + lineDiscount,
          code: currentData.code || discountCode,
        });
      }
    }
  });
  variantDiscountMap.forEach((data, variantId) => {
    if (data.discount > 0) {
      const discountDecimal = data.discount / 100;
      const entry = data.code
        ? `${variantId}:${discountDecimal}|${data.code}`
        : `${variantId}:${discountDecimal}`;
      discountEntries.push(entry);
    }
  });
  let orderLevelDiscountCents = 0;
  let orderLevelDiscountCode = "";
  if (
    cartLevelDiscountApplications &&
    cartLevelDiscountApplications.length > 0
  ) {
    orderLevelDiscountCents = cartLevelDiscountApplications.reduce(
      (sum, discount) => {
        return sum + (discount?.total_allocated_amount || 0);
      },
      0,
    );
    orderLevelDiscountCode =
      cartLevelDiscountApplications[0]?.title ||
      cartLevelDiscountApplications[0]?.code ||
      "";
  }

  const existingOrderLevelDiscountDecimal = orderLevelDiscountCents / 100;
  const ruleOrder = options?.ruleOrderLevelDiscount || null;
  const ruleAmount = Number(ruleOrder?.amount || 0);
  const ruleCode = (ruleOrder?.code || "").trim();
  let finalOrderLevelAmount = existingOrderLevelDiscountDecimal;
  let finalOrderLevelCode = orderLevelDiscountCode;

  if (ruleAmount > 0 && ruleCode) {
    finalOrderLevelAmount = ruleAmount;
    finalOrderLevelCode = ruleCode;
  }
  if (finalOrderLevelAmount > 0) {
    const entry = finalOrderLevelCode
      ? `orderLevel:${finalOrderLevelAmount}|${finalOrderLevelCode}`
      : `orderLevel:${finalOrderLevelAmount}`;
    discountEntries.push(entry);
  }

  return discountEntries.join(",");
};

export const getCodkImageURLs = (cartItems = []) => {
  const imageEntries = [];
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
    )
      variantImageMap.set(variantId, imageURL);
  });
  variantImageMap.forEach((imageURL, variantId) => {
    if (imageURL && typeof imageURL === "string") {
      const encodedURL = encodeURIComponent(imageURL);
      imageEntries.push(`${variantId}:${encodedURL}`);
    }
  });

  return imageEntries.join(",");
};

const hasFreeProducts = (cartItems) => {
  return (cartItems || []).some((item) => {
    const finalLinePrice = item?.final_line_price || 0;
    const finalPrice = item?.final_price || 0;
    return finalLinePrice === 0 || finalPrice === 0;
  });
};

const safeNum = (v, fallback = 0) => {
  const n = typeof v === "number" ? v : parseFloat(v);
  return Number.isFinite(n) && !Number.isNaN(n) ? n : fallback;
};

const getCartPricingInfo = (cart) => {
  const totalPriceCents = safeNum(cart?.total_price, 0);
  const cartTotalDecimal = totalPriceCents / 100;
  // Prefer original_total_price when available (pre-discount subtotal)
  const originalCartTotalDecimal =
    typeof cart?.original_total_price === "number"
      ? safeNum(cart.original_total_price, 0) / 100
      : Math.max(0, cartTotalDecimal + safeNum(cart?.total_discount, 0) / 100);
  const currencyCode = cart?.currency || "INR";
  const cartItems = cart?.items || [];

  // True line-level discounts (exclude order-level allocations that Shopify spreads across lines)
  const lineLevelDiscountDecimal = (cartItems || []).reduce((sum, item) => {
    const hasLineLevelDiscounts =
      item?.line_level_discount_allocations &&
      item.line_level_discount_allocations.length > 0;
    if (!hasLineLevelDiscounts) return sum;

    const lineDiscountCents =
      item?.line_level_total_discount ||
      (item?.line_level_discount_allocations || []).reduce((s, alloc) => {
        return s + safeNum(alloc?.amount, 0);
      }, 0);

    return sum + safeNum(lineDiscountCents, 0) / 100;
  }, 0);

  // Existing order-level discount from cart-level applications
  const existingOrderLevelDiscountDecimal =
    (cart?.cart_level_discount_applications || []).reduce((sum, d) => {
      return sum + safeNum(d?.total_allocated_amount, 0);
    }, 0) / 100;

  return {
    cartTotalDecimal,
    originalCartTotalDecimal,
    currencyCode,
    cartItems,
    lineLevelDiscountDecimal,
    existingOrderLevelDiscountDecimal,
    hasFreeProducts: hasFreeProducts(cartItems),
  };
};

/**
 * Calculate rule-level discount value
 */
const calculateRuleLevelDiscount = (
  rule,
  originalCartTotalDecimal,
  lineLevelDiscountDecimal = 0,
) => {
  const ruleDiscountValue = parseFloat(rule?.discount_value || 0);
  const ruleDiscountType = rule?.discount_type || "";
  const ruleDiscountCode = rule?.discount_code || "";

  if (ruleDiscountValue <= 0 || !ruleDiscountCode) return 0;

  if (ruleDiscountType === "percentage") {
    // Percentage discount should apply on cart value AFTER line-level discounts
    const base = Math.max(
      0,
      originalCartTotalDecimal - (lineLevelDiscountDecimal || 0),
    );
    return (base * ruleDiscountValue) / 100;
  } else {
    return ruleDiscountValue;
  }
};

/**
 * Get discount name from cart or rule
 */
const getDiscountName = (cart, rule, isRuleDiscountBigger) => {
  const ruleDiscountCode = rule?.discount_code || "";

  if (isRuleDiscountBigger && ruleDiscountCode) {
    return ruleDiscountCode;
  }

  const firstCartDiscount = cart?.cart_level_discount_applications?.[0];
  return (
    firstCartDiscount?.title ||
    cart?.discount_codes?.[0]?.code ||
    (cart?.discount_codes?.[0]
      ? typeof cart.discount_codes[0] === "string"
        ? cart.discount_codes[0]
        : cart.discount_codes[0]?.code
      : "") ||
    ""
  );
};

/**
 * Get effective amount (amount_to_show has priority)
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
    const originalFormatted = formatCurrency(
      originalCartTotalDecimal,
      currencyCode,
    );
    const finalFormatted = formatCurrency(finalPriceWithDiscount, currencyCode);
    const discountAmountFormatted = formatCurrency(totalDiscount, currencyCode);

    const discountLabel = discountName
      ? `${discountAmountFormatted} (${discountName})`
      : discountAmountFormatted;

    // Example:
    // "You save ₹5 (Monsoon Sale). Total after discount: ₹95 (original ₹100)."
    return `You save ${discountLabel}. Total after discount: ${finalFormatted} (original ${originalFormatted}).`;
  }

  return `Total: ${formatCurrency(cartTotalDecimal, currencyCode)}`;
};

/**
 * Calculate payment and remaining amounts for a rule
 */
const calculatePaymentAmounts = (rule, pricingInfo, cart) => {
  const {
    originalCartTotalDecimal,
    cartTotalDecimal,
    lineLevelDiscountDecimal,
    existingOrderLevelDiscountDecimal,
  } = pricingInfo;

  // Calculate rule-level *order-level* discount (fixed amount)
  const ruleLevelDiscount = calculateRuleLevelDiscount(
    rule,
    originalCartTotalDecimal,
    lineLevelDiscountDecimal,
  );
  const finalOrderLevelDiscount =
    (existingOrderLevelDiscountDecimal || 0) + (ruleLevelDiscount || 0);
  const isRuleDiscountBigger =
    (ruleLevelDiscount || 0) > (existingOrderLevelDiscountDecimal || 0);
  const totalDiscount =
    (lineLevelDiscountDecimal || 0) + finalOrderLevelDiscount;

  // Always compute final price from original total so rule discount shows even if not yet applied to cart.
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
      // Same base the Cart Transform charges on: line-level discounts (free
      // BOGO units) leave the base, order-level discounts do not.
      const depositBase = Math.max(
        0,
        originalCartTotalDecimal - (lineLevelDiscountDecimal || 0),
      );
      paymentAmount = (depositBase * ruleAmount) / 100;
    }
  }

  // Calculate remaining amount
  let remainingAmount = 0;
  if (isCodFeeException) {
    remainingAmount = finalPriceWithDiscount;
  } else if (shouldUseAmountToShow && !isCodFeeException) {
    // amount_to_show is display-only; remaining uses the real advance (rule.amount).
    const realRuleAmount = parseFloat(rule?.amount || 0);
    if (rule?.amount_type === "percentage") {
      if (realRuleAmount === 100) {
        remainingAmount = 0;
      } else {
        const depositBase = Math.max(
          0,
          originalCartTotalDecimal - (lineLevelDiscountDecimal || 0),
        );
        const realAdvance = (depositBase * realRuleAmount) / 100;
        remainingAmount = Math.max(0, finalPriceWithDiscount - realAdvance);
      }
    } else {
      const realAdvance = Math.min(realRuleAmount, finalPriceWithDiscount);
      remainingAmount = Math.max(0, finalPriceWithDiscount - realAdvance);
    }
  } else if (rule?.amount_type === "percentage") {
    remainingAmount = Math.max(0, finalPriceWithDiscount - paymentAmount);
  } else {
    paymentAmount = Math.min(paymentAmount, finalPriceWithDiscount);
    remainingAmount = Math.max(0, finalPriceWithDiscount - paymentAmount);
  }

  return {
    paymentAmount: safeNum(paymentAmount, 0),
    remainingAmount: safeNum(remainingAmount, 0),
    finalPriceWithDiscount: safeNum(finalPriceWithDiscount, 0),
    totalDiscount: safeNum(totalDiscount, 0),
    isRuleDiscountBigger,
    originalCartTotalDecimal: safeNum(originalCartTotalDecimal, 0),
    cartTotalDecimal: safeNum(cartTotalDecimal, 0),
    ruleAmount: safeNum(ruleAmount, 0),
  };
};

export const prepaidDiscountAttribute = (isFullPercentage, ruleOrderLevelDiscount) =>
  isFullPercentage && ruleOrderLevelDiscount?.amount > 0 && ruleOrderLevelDiscount?.code
    ? `${ruleOrderLevelDiscount.amount.toFixed(2)}|${ruleOrderLevelDiscount.code}`
    : "";

/**
 * Build cart attributes for partial payment
 */
export const buildCartAttributes = async ({
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
  const pricingInfo = getCartPricingInfo(cart);
  const ruleOrderLevelDiscountAmount = calculateRuleLevelDiscount(
    rule,
    pricingInfo.originalCartTotalDecimal,
    pricingInfo.lineLevelDiscountDecimal,
  );
  const ruleOrderLevelDiscountCode = (rule?.discount_code || "").trim();
  const ruleOrderLevelDiscount =
    ruleOrderLevelDiscountAmount > 0 && ruleOrderLevelDiscountCode
      ? {
          amount: ruleOrderLevelDiscountAmount,
          code: ruleOrderLevelDiscountCode,
        }
      : null;

  // Calculate discounts from cart items (and apply rule override if bigger)
  const codkDiscounts = getCodkDiscounts(
    cart?.items || [],
    cart?.cart_level_discount_applications || [],
    { ruleOrderLevelDiscount, skipFreeItems: isFullPercentage || isCOD },
  );

  // Get image URLs from cart items
  const codkImageURLs = getCodkImageURLs(cart?.items || []);

  // Get partial dummy variant ID from sessionStorage
  const partialDummyVariantId =
    typeof sessionStorage !== "undefined"
      ? sessionStorage.getItem("partialDummyVariantId")
      : null;

  const attributes = {
    _codkAmountType: amountType,
    _codkAmountValue: amountValue,
    // Restrict checkout to COD-only when the merchant enabled it on this COD rule.
    // Read by the payment & delivery Shopify Functions via _codkCheckoutMode.
    // Always written (empty when not restricted) so a prior selection never leaves
    // a stale restriction on the cart.
    _codkCheckoutMode:
      isCOD &&
      (rule?.checkout_cod_only === true || rule?.checkout_cod_only === "true")
        ? "cod_only"
        : "",
    _codkFinalDiscountValue: actualDiscountValue || "",
    _codkPrepaidDiscount: prepaidDiscountAttribute(isFullPercentage, ruleOrderLevelDiscount),
    // _codkFreeVariants: freeVariantsValue || "",
    _codkPaymentDescription: ruleDescription,
    _codkDiscounts: codkDiscounts || "",
    _codkImageURLs: codkImageURLs || "",
    // Original cart total (full order value) — read by web pixel for Google Ads
    _codkOriginalTotal: String(pricingInfo?.originalCartTotalDecimal || ""),
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

  // Add partial dummy variant ID if available
  if (partialDummyVariantId) {
    attributes._partial_product_variant = partialDummyVariantId;
  }

  // Add partial payment variants for partial payments (not COD or full payment)
  if (!isCOD && !isFullPercentage) {
    const variants = (cart?.items || [])
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
 * Calculate rule discount value
 */
export const calculateRuleDiscountValue = (
  selectedRuleObj,
  originalCartTotalDecimal,
) => {
  return calculateRuleLevelDiscount(selectedRuleObj, originalCartTotalDecimal);
};

/**
 * Determine if rule's discount should be applied
 */
export const shouldApplyRuleDiscount = (
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
 * Default description templates for each rule type
 * 
 * Available Placeholders:
 * - {{pay_now}}        : Amount to pay now (with tax if applicable)
 * - {{pay_now_base}}   : Amount to pay now (without tax)
 * - {{pay_now_tax}}    : Tax on pay now amount
 * - {{pay_later}}      : Amount to pay on delivery (with tax if applicable)
 * - {{pay_later_base}} : Amount on delivery (without tax)
 * - {{pay_later_tax}}  : Tax on delivery amount
 * - {{total}}          : Total order amount (with tax and COD fee)
 * - {{total_base}}     : Total order amount (without tax)
 * - {{total_tax}}      : Total tax amount
 * - {{discount}}       : Discount amount
 * - {{cod_fee}}        : COD fee amount
 */
const DEFAULT_TEMPLATES = {
  cod: UI_TEXT_DEFAULTS.desc_cod,
  cod_with_fee: UI_TEXT_DEFAULTS.desc_cod_with_fee,
  percentage_100: UI_TEXT_DEFAULTS.desc_prepaid,
  percentage_100_with_discount: UI_TEXT_DEFAULTS.desc_prepaid_with_discount,
  percentage: UI_TEXT_DEFAULTS.desc_partial,
  fixed: UI_TEXT_DEFAULTS.desc_partial,
  cod_fee_exception: UI_TEXT_DEFAULTS.desc_cod_fee_exception,
};

/**
 * Replace template placeholders with actual values
 * @param {string} template - Template string with {{placeholders}}
 * @param {Object} values - Object with placeholder values
 * @returns {string} - Formatted string
 */
const applyTemplate = (template, values) => {
  if (!template) return "";
  return template.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    return values[key] !== undefined ? values[key] : match;
  });
};

/**
 * Get the appropriate default template for a rule
 * @param {Object} rule - The payment rule
 * @param {number} totalDiscount - Total discount amount
 * @param {boolean} isCodFeeException - Whether this is a COD fee exception case
 * @returns {string} - Default template string
 */
const getDefaultTemplate = (rule, totalDiscount, isCodFeeException) => {
  const amountType = rule?.amount_type;
  const ruleAmount = parseFloat(rule?.amount || 0);
  const codFeeAmount = parseFloat(rule?.amount_to_show || rule?.amount || 0);

  if (amountType === "cod") {
    return codFeeAmount > 0 ? uiText("desc_cod_with_fee") : uiText("desc_cod");
  }
  if (amountType === "percentage" && ruleAmount === 100) {
    return totalDiscount > 0
      ? uiText("desc_prepaid_with_discount")
      : uiText("desc_prepaid");
  }
  if (isCodFeeException) {
    return uiText("desc_cod_fee_exception");
  }
  return uiText("desc_partial");
};

/**
 * Get description for bundle flow
 * @param {Object} rule - The payment rule
 * @param {Object} cart - The cart data
 * @param {Object} taxInfo - Optional tax information { ruleTax, remainingTax }
 * @param {number} shipping - Shipping charge for the selected rate (rupees)
 */
export const getDescBundle = (rule, cart, taxInfo = null, shipping = 0) => {
  try {
    if (!rule) return "";

    // Check if sub_heading is provided (snake_case from API or subHeading camelCase) - if yes, return only sub_heading
    const subHeading = (rule?.sub_heading ?? rule?.subHeading)?.trim?.();
    if (subHeading) {
      return subHeading;
    }

    // Get cart pricing information
    const pricingInfo = getCartPricingInfo(cart);
    const { currencyCode, hasFreeProducts: hasFreeProductsFlag } = pricingInfo;

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
    } = calculatePaymentAmounts(rule, pricingInfo, cart);

    // Get effective amount info
    const { shouldUseAmountToShow, isCodFeeException } =
      getEffectiveAmount(rule);

    // Extract tax values (default to 0 if not provided)
    const ruleTax = taxInfo?.ruleTax || 0;
    const remainingTax = taxInfo?.remainingTax || 0;
    const totalTax = ruleTax + remainingTax;
    const shippingAmount = Math.max(0, safeNum(shipping, 0));

    // Calculate COD fee for COD type
    const codFeeAmount =
      rule?.amount_type === "cod"
        ? shouldUseAmountToShow
          ? parseFloat(rule?.amount_to_show || 0)
          : parseFloat(rule?.amount || 0)
        : 0;

    // Calculate amounts with tax included. Shipping rides along with whichever
    // leg actually collects it: the delivery total for COD, the pay-now leg for
    // full prepaid, the pay-later leg for partial payments.
    const totalOnDelivery =
      finalPriceWithDiscount + codFeeAmount + totalTax + shippingAmount;
    const paymentAmountWithTax = paymentAmount + ruleTax;
    const remainingAmountWithTax =
      remainingAmount + remainingTax + shippingAmount;
    const fullAmountWithTax = paymentAmount + totalTax + shippingAmount;

    // Base amounts (without tax) for granular placeholders
    const payNowBase = rule?.amount_type === "percentage" && ruleAmount === 100
      ? paymentAmount
      : paymentAmount;
    const payNowWithTax = rule?.amount_type === "percentage" && ruleAmount === 100
      ? fullAmountWithTax
      : paymentAmountWithTax;
    const payNowTax = rule?.amount_type === "percentage" && ruleAmount === 100
      ? totalTax
      : ruleTax;
    
    const payLaterBase = remainingAmount;
    const payLaterWithTax = remainingAmountWithTax;
    const payLaterTax = remainingTax;

    const totalBase = finalPriceWithDiscount + codFeeAmount;

    // Prepare template values with all placeholders
    const templateValues = {
      // Pay now values
      pay_now: formatCurrency(payNowWithTax, currencyCode),
      pay_now_base: formatCurrency(payNowBase, currencyCode),
      pay_now_tax: formatCurrency(payNowTax, currencyCode),
      
      // Pay later values
      pay_later: formatCurrency(payLaterWithTax, currencyCode),
      pay_later_base: formatCurrency(payLaterBase, currencyCode),
      pay_later_tax: formatCurrency(payLaterTax, currencyCode),
      
      // Total values
      total: formatCurrency(totalOnDelivery, currencyCode),
      total_base: formatCurrency(totalBase, currencyCode),
      total_tax: formatCurrency(totalTax, currencyCode),
      
      // Other values
      discount: formatCurrency(totalDiscount, currencyCode),
      cod_fee: formatCurrency(codFeeAmount, currencyCode),
      shipping: formatCurrency(shippingAmount, currencyCode),
    };

    // Check if rule has a custom description_template
    const customTemplate = (
      rule?.description_template ?? rule?.descriptionTemplate
    )?.trim?.();

    if (customTemplate) {
      return applyTemplate(customTemplate, templateValues);
    }

    // Use default template based on rule type
    const defaultTemplate = getDefaultTemplate(rule, totalDiscount, isCodFeeException);
    return applyTemplate(defaultTemplate, templateValues);
  } catch (error) {
    return "";
  }
};

/**
 * Export default templates for use in admin UI
 */
export { DEFAULT_TEMPLATES };

/**
 * Calculate payment price for bundle flow
 */
export const getPriceBundle = (rule, cart, shipping = 0) => {
  try {
    if (!rule) return formatCurrency(0);

    // Get cart pricing information (handles null/undefined cart)
    const pricingInfo = getCartPricingInfo(cart || {});
    const { currencyCode } = pricingInfo;

    // Calculate payment amounts
    const { paymentAmount, finalPriceWithDiscount, ruleAmount } =
      calculatePaymentAmounts(rule, pricingInfo, cart || {});

    // Get effective amount info
    const { shouldUseAmountToShow } = getEffectiveAmount(rule);

    const shippingAmount = Math.max(0, safeNum(shipping, 0));
    let price = paymentAmount;

    // Handle COD type - return total amount including COD fee
    if (rule?.amount_type === "cod") {
      const codFee = shouldUseAmountToShow
        ? safeNum(rule?.amount_to_show, 0)
        : safeNum(rule?.amount, 0);
      price = finalPriceWithDiscount + codFee + shippingAmount;
    } else if (rule?.amount_type === "percentage" && ruleAmount === 100) {
      // Full prepaid collects shipping up front; partial rules collect it on
      // delivery, so their pay-now headline stays as-is.
      price = paymentAmount + shippingAmount;
    }

    return formatCurrency(Math.max(0, safeNum(price, 0)), currencyCode);
  } catch (error) {
    const pricingInfo = getCartPricingInfo(cart || {});
    return formatCurrency(0, pricingInfo?.currencyCode || "INR");
  }
};

/**
 * Update all line items with description property
 */
export const updateAllLineItemsDescription = async (ruleDescription, cart) => {
  try {
    // Use currentCartData from OTP store (current cart) instead of cartStore
    const { get } = await import("svelte/store");
    const otpState = get(otpStore);
    const currentCartData = otpState?.currentCartData;

    if (!currentCartData?.items || currentCartData.items.length === 0) {
      return;
    }

    // Skip if description is empty or already set on all items
    if (!ruleDescription || ruleDescription.trim() === "") {
      return;
    }

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
 * Remove description property from ALL line items (parity with React v2 flow)
 */
export const removeAllLineItemsDescription = async (cart) => {
  try {
    const items = cart?.items || [];

    if (!items.length) {
      return;
    }

    const variantsWithFreeItem = new Set();
    items.forEach((it) => {
      const vid = it?.variant_id || it?.id;
      if (!vid) return;
      if (!it?.final_price) variantsWithFreeItem.add(vid);
    });

    const variantTotalQty = new Map();
    const variantAnchorIndex = new Map();
    items.forEach((it, idx) => {
      const vid = it?.variant_id || it?.id;
      if (!vid || !variantsWithFreeItem.has(vid)) return;
      variantTotalQty.set(
        vid,
        (variantTotalQty.get(vid) || 0) + (parseInt(it.quantity) || 1),
      );
      if (it?.final_price && !variantAnchorIndex.has(vid)) {
        variantAnchorIndex.set(vid, idx);
      }
    });

    let hasUpdates = false;

    const updatedItems = new Array(items.length);

    for (let index = items.length - 1; index >= 0; index--) {
      const item = items[index];
      const line = index + 1;
      const variantId = item?.variant_id || item?.id;
      let existingProperties = {};

      if (item?.properties) {
        if (
          typeof item.properties === "object" &&
          !Array.isArray(item.properties)
        ) {
          existingProperties = { ...item.properties };
        } else if (Array.isArray(item.properties)) {
          item.properties.forEach((prop) => {
            if (prop?.name && prop?.value !== undefined) {
              existingProperties[prop.name] = prop.value;
            }
          });
        }
      }

      if (existingProperties.description !== undefined) {
        const isBogo = variantsWithFreeItem.has(variantId);

        if (isBogo && (!item?.final_price || variantAnchorIndex.get(variantId) !== index)) {
          updatedItems[index] = item;
          continue;
        }

        const { description, ...rest } = existingProperties;
        const body = { line, properties: rest };
        if (isBogo) {
          body.quantity = variantTotalQty.get(variantId) || (parseInt(item.quantity) || 1);
        }

        await cartFetch("/cart/change.js", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        hasUpdates = true;
        updatedItems[index] = { ...item, properties: rest };
      } else {
        updatedItems[index] = item;
      }
    }

    if (hasUpdates) {
      otpStore.patchCurrentCartData?.({ items: updatedItems });
    }
  } catch (error) {}
};

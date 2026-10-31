import { executePost, getCart, fetchPartialRuleSets } from "../services/otpService.js";
import { getSessionValue, setSessionValue } from "../services/sessionService.js";
import { getMachineId, getShopDomain, isTaxIncludedWithProductAny } from "./helpers.js";
import {
  addCartAttributesWithOtpStore,
  applyDiscountCodeToOtpStore,
  removeDiscountCodeFromOtpStore,
  saveDiscountSummaryToSession,
} from "../utilities/otpUtils.js";
export { saveDiscountSummaryToSession };
import { actions } from "../stores/buttonManager.js";
import otpStore, { otpStoreActions } from "../stores/otpStore.js";
import { get } from "svelte/store";
import { createLightweightGraphQLClient } from "../services/lightweightGraphQLClient.js";
import {
  getDescBundle,
  buildCartAttributes,
  getCodkDiscounts,
  getCodkImageURLs,
  prepaidDiscountAttribute,
} from "./bundlePaymentUtils.js";
import { cartFetch } from "./shopifyCartApi.js";
import { giftDiscountCents, giftFinalCents, giftOriginalCents, isGiftLine } from "../services/freeGiftService.js";

/**
 * Calculate tax amounts for a rule based on stored tax data
 * @param {Object} rule - The payment rule
 * @param {Object} cart - The cart data
 * @returns {{ ruleTax: number, remainingTax: number } | null}
 */
const calculateTaxForRule = (rule, cart) => {
  try {
    const otpState = get(otpStore);
    const calculatedTax = otpState?.calculatedTaxData;
    const settings = otpState?.settings || getSessionValue("settingSession");

    if (
      isTaxIncludedWithProductAny(settings, getSessionValue("settingSession"))
    ) {
      return null;
    }

    // Check if tax info should be shown
    const codFormEnabled =
      settings?.cod_form_enabled === true ||
      settings?.cod_form_enabled === "true";
    const showTaxInfo =
      codFormEnabled ||
      (settings?.pre_v2_show_tax_info === true ||
        settings?.preV2ShowTaxInfo === true);

    if (!showTaxInfo || !calculatedTax || !calculatedTax.total_tax) {
      return null;
    }

    // Calculate tax rate
    const taxLines = calculatedTax?.tax_lines;
    let taxRate = 0;
    if (taxLines?.length > 0) {
      taxRate = taxLines.reduce((s, l) => s + (parseFloat(l.rate) || 0), 0);
    }
    if (taxRate <= 0) {
      const totalTax = calculatedTax.total_tax > 10000
        ? calculatedTax.total_tax / 100
        : calculatedTax.total_tax;
      const totalPrice = (cart?.total_price || 0) / 100;
      if (totalTax > 0 && totalPrice > 0) {
        taxRate = totalTax / totalPrice;
      }
    }

    if (taxRate <= 0) return null;

    // Calculate payNow amount (same logic as PaymentOptionsSection)
    const totalPriceCents = cart?.total_price || 0;
    const totalAfterDiscount = totalPriceCents / 100;
    const ruleAmount = parseFloat(rule?.amount) || 0;

    let payNow = 0;
    if (rule?.amount_type === "cod") {
      payNow = totalAfterDiscount;
    } else if (rule?.amount_type === "percentage" && rule?.amount === "100.0") {
      payNow = totalAfterDiscount;
    } else if (rule?.amount_type === "fixed") {
      payNow = Math.min(ruleAmount, totalAfterDiscount);
    } else if (rule?.amount_type === "percentage") {
      payNow = (totalAfterDiscount * ruleAmount) / 100;
    }

    const remaining = Math.max(0, totalAfterDiscount - payNow);

    const ruleTax = Math.floor(payNow * taxRate * 100) / 100;
    const remainingTax = Math.floor(remaining * taxRate * 100) / 100;

    return { ruleTax, remainingTax };
  } catch (_) {
    return null;
  }
};

const CART_DISCOUNT_CODES_UPDATE = `
  mutation cartDiscountCodesUpdate($cartId: ID!, $discountCodes: [String!]) {
    cartDiscountCodesUpdate(cartId: $cartId, discountCodes: $discountCodes) {
      cart { id discountCodes { code applicable } checkoutUrl cost { totalAmount { amount currencyCode } } }
      userErrors { field message }
    }
  }
`;
const mutateCartDiscountCodes = async (cartId, discountCodes) => {
  const settings = getSessionValue("settingSession");
  const shop = getShopDomain();
  const token = settings?.storeFrontToken;
  if (!shop || !token) throw new Error("Shopify configuration not found");
  const client = createLightweightGraphQLClient(shop, token);
  const { data } = await client.mutateWithCacheClear(CART_DISCOUNT_CODES_UPDATE, {
    cartId,
    discountCodes: Array.isArray(discountCodes) ? discountCodes : [discountCodes],
  });
  const res = data?.cartDiscountCodesUpdate;
  if (res?.userErrors?.length) throw new Error(res.userErrors[0].message);
  return res.cart;
};

const syncCartAttributesToShopify = async (attributes) => {
  if (!attributes || Object.keys(attributes).length === 0) return;
  try {
    await executePost({ attributes });
    addCartAttributesWithOtpStore(attributes);
  } catch (_e) {}
};

const rebuildCartWithPartialVariants = async (cartData, partialCartItems) => {
  try {
    const newItems = cartData.items.map((item) => {
      const match = partialCartItems.find((p) => p.variantId == item.variant_id);
      const id = match ? parseInt(match.originalVariantId) : item.variant_id;
      return { id, quantity: item.quantity };
    });
    await cartFetch("/cart/clear.js", { method: "POST" });
    await cartFetch("/cart/add.js", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ items: newItems }),
    });
    setSessionValue("partial_payment_cart_results", null);
    otpStoreActions.setIsPartialCartRevertToOriginalCartCompleted(true);
  } catch (error) {
    throw error;
  }
};

export const removeSelectiveDiscountCodes = async (cartId, discountCodesToKeep) =>
  mutateCartDiscountCodes(cartId, discountCodesToKeep);

export const applyDiscountCodeToCart = async (cartId, discountCode) =>
  mutateCartDiscountCodes(cartId, discountCode ? [discountCode] : []);

const applyDiscountCodeToCartHelper = async (discountCode) => {
  if (!discountCode) return;
  const codes = get(otpStore)?.currentCartData?.discount_codes || [];
  if (codes.length > 0) {
    try {
      removeDiscountCodeFromOtpStore();
    } catch (_) {}
  }
  applyDiscountCodeToOtpStore(discountCode);
};

const removeAllDiscountCodesHelper = async () => {
  const codes = get(otpStore)?.currentCartData?.discount_codes || [];
  if (codes.length === 0) return;
  try {
    await removeAllDiscountCodes();
  } catch (_) {}
};

export const removeAllDiscountCodes = async () => {
  const response = await executePost({ discount: "" });
  const result = await response.json();
  removeDiscountCodeFromOtpStore();
  return result;
};

const CLEAR_ATTRS = {
  _codkFinalDiscountValue: "",
  _codkPrepaidDiscount: "",
  _codkFreeVariants: "",
  _codkDiscounts: "",
  _codkImageURLs: "",
  _codkAmountType: "",
  _codkAmountValue: "",
  _partialPaymentProduct: "",
  partial_payment_variants: "",
  _codkPaymentDescription: "",
};

export const clearPartialPaymentCartAttributes = async () => {
  try {
    await executePost({ attributes: { ...CLEAR_ATTRS }, discount: "" });
    addCartAttributesWithOtpStore(CLEAR_ATTRS);
    removeDiscountCodeFromOtpStore();
  } catch (_) {}
};

export const preCreateCartsForEligibleRules = async () => Promise.resolve();

export const hasBOGOItems = (cartItems) => {
  if (!cartItems?.length) return false;
  return cartItems.some((item) => {
    if (item?.isBOGODiscount === true) return true;
    const line = item?.final_line_price || 0;
    const price = item?.final_price || 0;
    if (line !== 0 && price !== 0) return false;
    const allocs =
      item?.line_level_discount_allocations?.length > 0 ||
      item?.discount_allocations?.length > 0;
    return !!allocs;
  });
};

const getFreeVariantIds = (cartItems = []) => {
  const free = (cartItems || []).filter(
    (item) =>
      (item?.final_line_price || 0) === 0 || (item?.final_price || 0) === 0,
  );
  if (free.length === 0) return "";
  const map = new Map();
  free.forEach((item) => {
    const id = item?.variant_id ?? item?.id;
    if (id != null)
      map.set(id, (map.get(id) || 0) + (item?.quantity || 1));
  });
  return Array.from(map.keys()).join(",");
};

const calcRuleDiscount = (rule, originalTotal) => {
  const val = parseFloat(String(rule?.discount_value ?? "0"));
  const type = rule?.discount_type || "";
  const code = rule?.discount_code || "";
  if (val <= 0 || !code) return 0;
  return type === "percentage" ? (originalTotal * val) / 100 : val;
};

const PartialPaymentFilteredRules = async () => {
  try {
    let rules = getSessionValue("ruleSets");
    if (!Array.isArray(rules) || rules.length === 0) {
      try {
        const result = await fetchPartialRuleSets(getShopDomain());
        if (result?.success && Array.isArray(result.data)) {
          rules = result.data;
          setSessionValue("ruleSets", rules);
        }
      } catch (_) {}
    }
    if (!Array.isArray(rules)) return [];
    return rules.filter((rule) => {
      const amountType = rule?.amount_type;
      const amountNum = rule?.amount != null ? Number(rule.amount) : null;
      const min = rule?.min_cart_range != null ? Number(rule.min_cart_range) : null;
      const max = rule?.max_cart_range != null ? Number(rule.max_cart_range) : null;
      let totalNum = NaN;
      try {
        const cart = get(otpStore)?.currentCartData;
        if (cart && typeof cart.total_price === "number") totalNum = cart.total_price / 100;
      } catch (_) {}
      if (amountType === "cod") return false;
      if (amountType === "percentage" && amountNum === 100) return false;
      if (!Number.isNaN(totalNum)) {
        if (min != null && !Number.isNaN(min) && min > 0 && totalNum < min) return false;
        if (max != null && !Number.isNaN(max) && max > 0 && totalNum > max) return false;
      }
      return true;
    });
  } catch (_) {
    return [];
  }
};

const shouldApplyRuleDiscount = (selectedRuleObj, ruleDiscountValue, existingCartDiscountValue) => {
  const code = selectedRuleObj?.discount_code?.trim();
  return !!(code && (ruleDiscountValue > existingCartDiscountValue || existingCartDiscountValue === 0));
};

const lineLevelDiscountCents = (items) =>
  (items || []).reduce((sum, item) => {
    const allocs = item?.line_level_discount_allocations;
    if (!allocs?.length) return sum;
    const cents =
      item?.line_level_total_discount ||
      allocs.reduce((s, a) => s + (a?.amount || 0), 0);
    return sum + cents / 100;
  }, 0);

const handleSimpleFlow = async (
  cart,
  selectedRuleObj,
  isFullPercentage,
  isCOD,
  setIsPartialPaymentCartReadyAndUpdated,
) => {
  try {
    const settings = getSessionValue("settingSession");
    const v = settings?.partialPaymentFlowVersion;
    if (v === 2) {
      addCartAttributesWithOtpStore({
        _codkAmountType: selectedRuleObj?.amount_type != null ? selectedRuleObj.amount_type : "0",
        _codkAmountValue: selectedRuleObj?.amount != null ? selectedRuleObj.amount : "0",
        // COD-only checkout restriction signal (empty unless a COD rule opted in).
        _codkCheckoutMode:
          isCOD &&
          (selectedRuleObj?.checkout_cod_only === true ||
            selectedRuleObj?.checkout_cod_only === "true")
            ? "cod_only"
            : "",
      });
    }
    const currentCartState = get(otpStore)?.cart;
    const total = ((currentCartState?.total_price || 0) - giftFinalCents(currentCartState?.items)) / 100;
    const existingDisc = ((currentCartState?.total_discount || 0) - giftDiscountCents(currentCartState?.items)) / 100;
    const originalTotal = total + existingDisc;
    const ruleDisc = calcRuleDiscount(selectedRuleObj, originalTotal);
    const code = selectedRuleObj?.discount_code?.trim();
    const shouldApply = shouldApplyRuleDiscount(selectedRuleObj, ruleDisc, existingDisc);
    if (shouldApply && code) applyDiscountCodeToOtpStore(code);
    else if (code) removeDiscountCodeFromOtpStore();

    const attributes = { _codkSessionId: getMachineId() || "", _codkPrepaidDiscount: "" };
    try {
      const effectiveCart = currentCartState || cart || {};
      const rawBaseTotal =
        typeof effectiveCart?.original_total_price === "number"
          ? effectiveCart.original_total_price / 100
          : ((effectiveCart?.total_price || 0) + (effectiveCart?.total_discount || 0)) / 100;
      const baseTotal = Math.max(0, rawBaseTotal - giftOriginalCents(effectiveCart?.items) / 100);
      const lineDisc = lineLevelDiscountCents((effectiveCart?.items || []).filter((item) => !isGiftLine(item)));
      const valNum = parseFloat(String(selectedRuleObj?.discount_value ?? "0"));
      const type = selectedRuleObj?.discount_type || "";
      const ruleCode = (selectedRuleObj?.discount_code || "").trim();
      let orderAmt = 0;
      if (ruleCode && valNum > 0) {
        orderAmt =
          type === "percentage"
            ? (Math.max(0, baseTotal - lineDisc) * valNum) / 100
            : valNum;
      }
      const ruleOrder = orderAmt > 0 && ruleCode ? { amount: orderAmt, code: ruleCode } : null;
      attributes._codkPrepaidDiscount = prepaidDiscountAttribute(isFullPercentage, ruleOrder);
      const codkDiscounts = getCodkDiscounts(
        effectiveCart?.items || [],
        effectiveCart?.cart_level_discount_applications || [],
        { ruleOrderLevelDiscount: ruleOrder, skipFreeItems: isFullPercentage || isCOD },
      );
      if (codkDiscounts) attributes._codkDiscounts = codkDiscounts;
      const imgUrls = getCodkImageURLs(effectiveCart?.items || []);
      if (imgUrls?.trim()) attributes._codkImageURLs = imgUrls;
    } catch (_) {}

    if (isFullPercentage) {
      attributes.partial_payment_variants = null;
      attributes._partialPaymentProduct = true;
      const prepaidDiscount = parseFloat(String(selectedRuleObj?.discount_value ?? "0"));
     if(prepaidDiscount < 1) attributes._codkDiscounts = "";
    } else if (isCOD) {
      attributes.partial_payment_variants = null;
      attributes._partialPaymentProduct = null;
    } else {
      const variants = (cart?.items || [])
        .map((i) => i?.variant_id ?? i?.id)
        .filter((id) => id != null);
      if (variants.length > 0) {
        attributes.partial_payment_variants = JSON.stringify(
          variants.map((v) => Number(v)).filter((n) => !isNaN(n)),
        );
        attributes._partialPaymentProduct = true;
      }
    }
    await syncCartAttributesToShopify(attributes);
    if (v === 2) {
      // Calculate tax info for tax-aware description
      const taxInfo = calculateTaxForRule(selectedRuleObj, cart);
      const desc = getDescBundle(selectedRuleObj, cart, taxInfo) || "Payment option selected";
      const { updateAllLineItemsDescription } = await import("./bundlePaymentUtils.js");
      await updateAllLineItemsDescription(desc, cart);
    }
    setIsPartialPaymentCartReadyAndUpdated(true);
  } catch (error) {
    throw new Error(`Simple flow failed: ${error.message}`);
  }
};

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
  const amountType = selectedRuleObj?.amount_type != null ? selectedRuleObj.amount_type : "0";
  const isCOD = selectedRuleObj?.amount_type === "cod";
  const isFullPercentage =
    selectedRuleObj?.amount_type === "percentage" && selectedRuleObj?.amount === "100.0";
  if (isCOD || isFullPercentage) return;

  const amountValue = selectedRuleObj?.amount != null ? selectedRuleObj.amount : "0";
  const nonGiftDiscount = (cart.total_discount || 0) - giftDiscountCents(cart.items);
  const actualDiscountValue = nonGiftDiscount > 0 ? String(nonGiftDiscount / 100) : "0";
  const rawCodes = (cart.discount_codes || [])
    .map((dc) => (typeof dc === "string" ? dc : dc?.code))
    .filter((c) => c && typeof c === "string");
  const actualDiscountCodes = Number(actualDiscountValue) > 0 ? rawCodes : [];
  const freeVariantsValue = getFreeVariantIds(cart?.items || []);
  const discountValueMatch = cartResult?.discountValueMatch ?? false;
  const currentTotal = ((cart.total_price || 0) - giftFinalCents(cart.items)) / 100;
  const existingCartDiscountValueDecimal = parseFloat(String(actualDiscountValue || "0"));
  const originalCartTotalDecimal = currentTotal + existingCartDiscountValueDecimal;
  const ruleDiscountValue = calcRuleDiscount(selectedRuleObj, originalCartTotalDecimal);
  const existingCartDiscountValue = existingCartDiscountValueDecimal;
  const shouldApplyRuleDiscountValue = shouldApplyRuleDiscount(
    selectedRuleObj,
    ruleDiscountValue,
    existingCartDiscountValue,
  );
  const ruleDiscountCode = selectedRuleObj?.discount_code?.trim();
  const discountValueNum = parseFloat(String(actualDiscountValue || "0"));
  const shouldCreateDiscountCodeForValue =
    !hasBOGOItems(cart?.items || []) &&
    !discountValueMatch &&
    discountValueNum > 0 &&
    !isNaN(discountValueNum) &&
    !!cartResult?.createdDiscountCode;
  const needsDiscountCodeSwitch =
    ruleDiscountCode &&
    !actualDiscountCodes.some(
      (c) => c.trim().toLowerCase() === ruleDiscountCode.trim().toLowerCase(),
    ) &&
    (ruleDiscountValue >= existingCartDiscountValue || existingCartDiscountValue === 0);
  const shouldApplyDiscount =
    shouldApplyRuleDiscountValue || shouldCreateDiscountCodeForValue || needsDiscountCodeSwitch;

  if (!shouldApplyDiscount) {
    if (actualDiscountCodes.length > 0) {
      try {
        await removeAllDiscountCodesHelper();
      } catch (_) {}
    }
  } else {
    try {
      let discountCode = null;
      if (shouldApplyRuleDiscountValue || needsDiscountCodeSwitch) {
        const already = actualDiscountCodes.some(
          (c) => c.trim().toLowerCase() === ruleDiscountCode.trim().toLowerCase(),
        );
        if (!already) discountCode = ruleDiscountCode;
      } else if (shouldCreateDiscountCodeForValue && cartResult?.createdDiscountCode) {
        discountCode = cartResult.createdDiscountCode;
      }
      if (discountCode) await applyDiscountCodeToCartHelper(discountCode);
    } catch (_) {}
  }

  // Calculate tax info for tax-aware description
  const taxInfo = calculateTaxForRule(selectedRuleObj, cart);
  const ruleDescription =
    getDescBundle(selectedRuleObj, cart, taxInfo) || "Partial payment option selected";
  const attributes = await buildCartAttributes({
    amountType,
    amountValue,
    actualDiscountValue,
    freeVariantsValue,
    isCOD,
    isFullPercentage,
    ruleDescription,
    cart,
    rule: selectedRuleObj,
  });

  addCartAttributesWithOtpStore(attributes);
  const { updateAllLineItemsDescription } = await import("./bundlePaymentUtils.js");
  await updateAllLineItemsDescription(ruleDescription, cart);
  setIsPartialPaymentCartReadyAndUpdated(true);
};

const getShop = () =>
  (typeof window !== "undefined" &&
    window.parent !== window &&
    window.parent?.Shopify?.shop) ||
  (typeof window !== "undefined" && window.Shopify?.shop) ||
  null;

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
  setError("");
  setIsPartialLoading(true);
  try {
    if (!selectedRule) throw new Error("Please select a payment option");
    if (!Array.isArray(ruleSets) || ruleSets.length === 0) throw new Error("No payment options available");
    const selectedRuleObj = ruleSets.find((r) => r.id === selectedRule);
    if (!selectedRuleObj) throw new Error("Selected payment option is no longer available");
    const shop = getShop();
    if (!shop) throw new Error("Shop information not available");

    let cart = get(otpStore).cart;
    if (!cart) cart = await getCart(false);
    if (!cart?.items?.length) throw new Error("Your cart is empty");

    const isCOD = selectedRuleObj?.amount_type === "cod";
    const isFullPercentage =
      selectedRuleObj?.amount_type === "percentage" && selectedRuleObj?.amount === "100.0";

    if (isCOD || isFullPercentage) {
      await handleSimpleFlow(
        cart,
        selectedRuleObj,
        isFullPercentage,
        isCOD,
        setIsPartialPaymentCartReadyAndUpdated,
      );
      otpStoreActions.setIsCartManipulationProcessCompleted(true);
      const { getCurrentStep } = await import("./stepUtils.js");
      const nextStep = await getCurrentStep();
      if (typeof setStep === "function") setStep(nextStep);
      return;
    }

    const cartResults = getSessionValue("partial_payment_cart_results") || [];
    const cartResult = cartResults.find((r) => r.ruleId === selectedRule);

    const currencyCode =
      (typeof window !== "undefined" &&
        window.Shopify &&
        typeof window.Shopify.currency === "object" &&
        /** @type {{ active?: string }} */ (window.Shopify.currency)?.active) ||
      "INR";

    if (!cartResult) {
      try {
        await handlePartialPaymentBundleFlow(
          cart,
          selectedRuleObj,
          shop,
          selectedRule,
          currencyCode,
          setIsPartialPaymentCartReadyAndUpdated,
          cartTotal,
          orderSummary,
          null,
        );
        otpStoreActions.setIsCartManipulationProcessCompleted(true);
        actions.setScreen("processing");
        return;
      } catch (_) {
        throw new Error("Cart results not found. Please refresh the page and try again.");
      }
    }

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
    otpStoreActions.setIsCartManipulationProcessCompleted(true);
    actions.setScreen("processing");
  } catch (error) {
    setError(error?.message || "An unexpected error occurred. Please try again.");
  } finally {
    setTimeout(() => setIsPartialLoading(false), 100);
  }
};

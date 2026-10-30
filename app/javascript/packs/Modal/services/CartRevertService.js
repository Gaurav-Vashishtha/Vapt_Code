import {
  getLocalValue,
  removeLocalValue,
  setLocalValue,
  debugLog,
  getSessionValue,
} from "../utilities/otpUtils";
import { clearCart, executePost, getCart } from "./otpService";
import useOtpStore from "../stores/otpStore";

/**
 * Service to revert the cart to its original state using AJAX API.
 * This is triggered if codk-updated-cart flag exists in localStorage.
 * @param {boolean} [isCartPage=false] - When true (called from cart page with bundler_product_created), reverts then reloads and clears bundler flag.
 */
export const CartRevertService = async (isCartPage = false) => {
  const { setIsPartialCartRevertToOriginalCartCompleted } =
    useOtpStore.getState();
  try {
    const updatedCartFlag = getLocalValue("codk-updated-cart");
    const currentCartData = getLocalValue("codk-current-cart");

    if (!updatedCartFlag || !currentCartData) {
      debugLog(
        "[CartRevertService] No updated cart flag found. Skipping revert.",
      );
      setIsPartialCartRevertToOriginalCartCompleted(true);
      return;
    }

    debugLog("[CartRevertService] Starting cart revert process...");
    // await clearCart();
    const settings = getSessionValue("settingSession");
    const revertDiscountRaw =
      settings?.revertDiscount ?? settings?.revert_discount;
    const revertDiscount =
      revertDiscountRaw === true ||
      revertDiscountRaw === "true" ||
      revertDiscountRaw === 1 ||
      revertDiscountRaw === "1";
    const partialPaymentEnabled = settings?.partialPaymentEnabled === true;
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;
    const partialCartData = getLocalValue("partialCartData") || [];

    // 1. Clear the entire cart first
    // await clearCart();
    // 2. Prepare original line items back from the stored currentCartData (Only for Flow V1)
    const updates = {};
    if (partialPaymentEnabled && partialPaymentFlowVersion == 1) {
      // Use getCart(true) to fetch fresh cart data to identify partial payment items
      const freshCartData = await getCart(true);

      // Process all items from fresh cart
      (freshCartData.items || []).forEach((item) => {
        const currentVariantId = item.variant_id || item.id;
        const currentQuantity = parseInt(item.quantity) || 1;

        // Check if this is a partial payment variant
        const partialMatch = partialCartData.find(
          (pc) => String(pc.variantId) === String(currentVariantId),
        );

        if (partialMatch && partialMatch.originalVariantId) {
          // This is a partial payment variant - remove it and add its quantity to original variant
          debugLog(
            `[CartRevertService] Matching partial variant ${currentVariantId} to original ${partialMatch.originalVariantId}`,
          );
          // Remove current partial variant (set to 0)
          updates[currentVariantId] = 0;
          // Add partial payment variant's quantity to original variant (accumulate, don't replace)
          const originalVariantId = partialMatch.originalVariantId;
          if (updates[originalVariantId]) {
            // Original variant already exists in updates, add to it
            updates[originalVariantId] += currentQuantity;
          } else {
            // Original variant doesn't exist yet, set it to partial payment quantity
            updates[originalVariantId] = currentQuantity;
          }
        } else {
          // Item not in partialCartData - add it to updates as-is from fresh cart
          updates[currentVariantId] = currentQuantity;
        }
      });

      console.log("updates", updates);
    }
    // 3. Restore original items (Only for Flow V1), clear partial payment attributes and discount codes
    // Matches the logic in cartService.js (removeDiscountCodeAndAttribute) and Svelte cartRevertService.
    // Clear _codkDiscounts so the payment customization (cod-king-discount-function) does not re-apply
    // rule-based discounts when user goes to checkout again; discount: "" removes all discounts from cart.
    const revertBody = {
      ...(partialPaymentEnabled &&
        partialPaymentFlowVersion == 1 && {
          updates,
        }),
      attributes: {
        _codkFinalDiscountValue: "",
        _codkFreeVariants: "",
        _codkDiscounts: "",
        _codkImageURLs: "",
        _codkAmountType: "",
        _codkAmountValue: "",
        _partialPaymentProduct: "",
        partial_payment_variants: "",
        _codkPaymentDescription: "",
      },
    };
    await executePost({
      ...revertBody,
      ...(revertDiscount ? { discount: "" } : {}),
    });
    if (!isCartPage) {
      // 4. Cleanup localStorage flags
      removeLocalValue("codk-updated-cart");

      debugLog(
        "[CartRevertService] Cart successfully reverted to original state.",
      );
      setIsPartialCartRevertToOriginalCartCompleted(true);
    } else {
      (window.parent || window).location.reload();
      setLocalValue("bundler_product_created", false);
    }
  } catch (error) {
    console.error("[CartRevertService] Revert failed:", error);
    setIsPartialCartRevertToOriginalCartCompleted(true);
  }
};

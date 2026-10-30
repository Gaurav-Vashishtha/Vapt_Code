import { get } from "svelte/store";
import {
  getLocalValue,
  isRedirectInProgress,
  removeLocalValue,
  setLocalValue,
} from "../utils/helpers.js";
import { getSessionValue, setSessionValue } from "./sessionService.js";
import { executePost, getCart } from "./otpService.js";
import { otpStore as otpStoreActions } from "../stores/otpStore.js";
import { appStore } from "../stores/buttonManager.js";
import { debugLog } from "./otpService.js";

/** Mutex: prevents concurrent cart revert when main.js and OrderSummaryCard both call it */
let revertInProgress = null;

/**
 * Service to revert the cart to its original state using AJAX API.
 * This mirrors the legacy React CartRevertService and should run
 * when a locally stored flag indicates the cart was manipulated for checkout.
 * Uses a mutex so concurrent callers (e.g. main.js + OrderSummaryCard) wait for the same run.
 */
export const cartRevertService = async () => {
  if (isRedirectInProgress()) {
    debugLog("[CartRevertService] Redirect in progress, skipping revert");
    return;
  }
  if (revertInProgress) {
    debugLog("[CartRevertService] Revert already in progress, waiting...");
    return revertInProgress;
  }

  const run = async () => {
    const setIsPartialCartRevertToOriginalCartCompleted =
      otpStoreActions.setIsPartialCartRevertToOriginalCartCompleted;
    try {
      const updatedCartFlag = getLocalValue("codk-updated-cart");
      const currentCartData = getLocalValue("codk-current-cart");

      // if (!updatedCartFlag || !currentCartData) {
      //   debugLog(
      //     "[CartRevertService] No updated cart flag found. Skipping revert.",
      //   );
      //   setIsPartialCartRevertToOriginalCartCompleted(true);
      //   return;
      // }

      debugLog("[CartRevertService] Starting cart revert process...");
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

      // Prepare original line items back from the stored currentCartData (Only for Flow V1)
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
      }
      // debugger;
      // Restore original items (Only for Flow V1), clear partial payment attributes and discount codes
      try {
        const revertBody = {
          ...(partialPaymentEnabled &&
            partialPaymentFlowVersion == 1 && {
              updates,
            }),
          attributes: {
            _codkFinalDiscountValue: "",
            _codkPrepaidDiscount: "",
            _codkFreeVariants: "",
            _codkDiscounts: "",
            _codkImageURLs: "",
            _codkAmountType: "",
            _codkAmountValue: "",
            _partialPaymentProduct: "",
            _partial_payment_variants: "",
            _codkPaymentDescription: "",
            partial_payment_variants: "",
            _partial_product_variant: "",
            _codkBundleMode: "",
          },
        };
        const response = await executePost({
          ...revertBody,
          ...(revertDiscount ? { discount: "" } : {}),
        });

        // Only clear flags when cart/update.js returned success; otherwise keep them so
        // OrderSummary (or main.js on next load) can retry revert.
        if (!response?.ok) {
          console.warn(
            "[CartRevertService] cart/update.js did not return success. Flags kept so revert can be retried from OrderSummary.",
            response?.status,
            response?.statusText,
          );
          throw new Error(
            `Cart update did not succeed: ${response?.status ?? "unknown"}`,
          );
        }

        // Wait for cart/update.js to fully persist before clearing flags and reloading
        await new Promise((r) => setTimeout(r, 300));

        removeLocalValue("codk-updated-cart");
        removeLocalValue("codk-current-cart");
        setLocalValue("bundler_product_created", false);

        debugLog(
          "[CartRevertService] Cart successfully reverted to original state.",
        );
        setIsPartialCartRevertToOriginalCartCompleted(true);

        const isPopupOpen = get(appStore)?.isOpen === true;
        if (!isPopupOpen && typeof window !== "undefined" && window.parent) {
          try {
            (window.parent || window).location.reload();
          } catch (_e) {}
        }
      } catch (postError) {
        console.error("[CartRevertService] Cart update failed:", postError);
        // Do not clear flags so OrderSummary can trigger revert again when user opens popup
        throw postError;
      }
    } catch (error) {
      console.error("[CartRevertService] Revert failed:", error);
      setIsPartialCartRevertToOriginalCartCompleted(true);
    } finally {
      // debugger;
      revertInProgress = null;
    }
  };

  revertInProgress = run();
  return revertInProgress;
};

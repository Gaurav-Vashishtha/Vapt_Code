import useOtpStore from "../stores/otpStore";
import {
  setLocalValue,
  getSessionValue,
  handleCheckoutError,
  debugLog,
} from "../utilities/otpUtils";
import { executePost } from "./otpService";

export const redirectOtpStoreToCheckout = async function () {
  try {
    const { currentCartData } = useOtpStore.getState();

    if (!currentCartData) throw new Error("Cart data is missing");

    const settings = getSessionValue("settingSession");
    const partialPaymentEnabled = settings?.partialPaymentEnabled === true;
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

    const attributes = currentCartData.attributes || {};
    const note = currentCartData.note || "";
    const discountCodes = (currentCartData.discount_codes || []).map(
      (dc) => dc.code || dc,
    );

    const sessionCart = getSessionValue("shopify_cart");
    const updates = {};
    if (partialPaymentEnabled && partialPaymentFlowVersion == 1) {
      // 1. Get current session cart to see what's already there from session storage
      if (sessionCart && sessionCart.items) {
        sessionCart.items.forEach((item) => {
          updates[item.variant_id || item.id] = 0;
        });
      }

      // 2. Set items from currentCartData (from store) to their desired quantity
      if (currentCartData.items) {
        currentCartData.items.forEach((item) => {
          updates[item.variant_id || item.id] = parseInt(item.quantity) || 1;
        });
      }
    }

    // 3. Update line item properties using properties from currentCartData.items (Flow V2 only)
    const updateLineItemProperties = async () => {
      if (!currentCartData.items || currentCartData.items.length === 0) return;

      try {
        // For Flow V2, directly update properties based on line number (index + 1)
        for (let index = 0; index < currentCartData.items.length; index++) {
          const item = currentCartData.items[index];
          if (!item.properties) continue;

          // Prepare properties object from currentCartData item
          let properties = {};
          if (
            typeof item.properties === "object" &&
            !Array.isArray(item.properties)
          ) {
            properties = { ...item.properties };
          } else if (Array.isArray(item.properties)) {
            item.properties.forEach((prop) => {
              if (prop && prop.name && prop.value !== undefined) {
                properties[prop.name] = prop.value;
              }
            });
          }

          if (Object.keys(properties).length === 0) continue;

          // Use index + 1 as line number (1-indexed)
          const lineNumber = index + 1;
          const quantity = item.quantity || 1;

          await fetch(`${window.Shopify.routes.root}cart/change.js`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Requested-With": "XMLHttpRequest",
            },
            body: JSON.stringify({
              line: lineNumber,
              quantity: quantity,
              properties: properties,
            }),
          });
        }
      } catch (error) {
        console.error(
          "[redirectOtpStoreToCheckout] Error updating line item properties:",
          error,
        );
        // Don't throw - properties update is not critical for checkout
      }
    };

    // For Flow V2, update line item properties only when partial payment (not full payment, not COD)
    const { isFullPercentage = false, isCOD = false } =
      useOtpStore.getState() || {};
    const isSimpleFlow = isFullPercentage || isCOD;

    if (partialPaymentEnabled && !isSimpleFlow) {
      await updateLineItemProperties();
    }

    if (
      partialPaymentEnabled &&
      !isSimpleFlow &&
      partialPaymentFlowVersion == 2
    ) {
      setLocalValue("bundler_product_created", true);
    }

    // 4. Update the cart via AJAX API
    await executePost({
      ...(partialPaymentEnabled &&
        partialPaymentFlowVersion == 1 && {
          updates,
        }),
      attributes,
      note,
      ...(discountCodes &&
        discountCodes.length > 0 && {
          discount: discountCodes.join(","),
        }),
    });

    // 5. Set flags for revert service if needed
    setLocalValue("codk-updated-cart", "true");
    setLocalValue("codk-current-cart", currentCartData);

    // 6. Build checkout URL
    const checkoutUrl = "/checkout";

    debugLog("[redirectOtpStoreToCheckout] Redirecting to:", checkoutUrl);
    window.location.href = checkoutUrl;
  } catch (error) {
    console.error("[redirectOtpStoreToCheckout] Error:", error);
    handleCheckoutError(error);
  }
};

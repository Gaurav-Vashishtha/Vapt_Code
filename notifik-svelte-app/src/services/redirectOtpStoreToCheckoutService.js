import { get } from "svelte/store";
import { otpStore } from "../stores/otpStore.js";
import {
  setLocalValue,
  getSessionValue,
  handleCheckoutError,
} from "../utilities/otpUtils.js";
import { executePost } from "./otpService.js";
import { waitForPendingBuyerIdentity } from "./cartService.js";
import {
  getShopifyRootPath,
  setRedirectInProgress,
  redirectToCheckout,
} from "../utils/helpers.js";

export const redirectOtpStoreToCheckout = async function () {
  setRedirectInProgress();
  try {
    const { currentCartData } = get(otpStore);

    if (!currentCartData) throw new Error("Cart data is missing");

    const settings = getSessionValue("settingSession");
    const partialPaymentEnabled = settings?.partialPaymentEnabled === true;
    const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

    const attributes = currentCartData.attributes || {};
    const note = "";
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

    // 3. Update line item properties using properties from currentCartData.items (Flow V2)
    const updateLineItemProperties = async (opts = {}) => {
      const { descriptionAsEmpty = false } = opts;
      if (!currentCartData.items || currentCartData.items.length === 0) return;

      try {
        const variantsWithFreeItem = new Set();
        const variantTotalQty = new Map();
        const variantAnchorIndex = new Map();
        if (descriptionAsEmpty) {
          currentCartData.items.forEach((it) => {
            const vid = it?.variant_id || it?.id;
            if (!vid) return;
            if (!it?.final_price) variantsWithFreeItem.add(vid);
          });

          currentCartData.items.forEach((it, idx) => {
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
        }

        const root = getShopifyRootPath();
        for (let index = currentCartData.items.length - 1; index >= 0; index--) {
          const item = currentCartData.items[index];
          const variantId = item?.variant_id || item?.id;
          let properties = {};

          if (item.properties) {
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
          }

          if (descriptionAsEmpty) {
            properties = { ...properties, description: "" };
          }

          if (Object.keys(properties).length === 0) continue;

          let quantity = parseInt(item.quantity) || 1;

          if (descriptionAsEmpty && variantsWithFreeItem.has(variantId)) {
            if (!item?.final_price) continue;
            if (variantAnchorIndex.get(variantId) !== index) continue;
            quantity = variantTotalQty.get(variantId) || quantity;
          }
          continue;
          await fetch(`${root}cart/change.js`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Requested-With": "XMLHttpRequest",
            },
            body: JSON.stringify({
              line: index + 1,
              quantity: quantity,
              properties: properties,
            }),
          });
        }
      } catch (error) {
        // Don't throw - properties update is not critical for checkout
      }
    };

    const { isFullPercentage = false, isCOD = false } = get(otpStore) || {};
    const isSimpleFlow = isFullPercentage || isCOD;

    // Flow V2: update line item properties via change.js
    // Partial (not simple): use properties from cart. Simple flow: pass description as ""
    if (partialPaymentEnabled && partialPaymentFlowVersion == 2) {
      await updateLineItemProperties({
        descriptionAsEmpty: isSimpleFlow,
      });
    }
    if (
      partialPaymentEnabled &&
      !isSimpleFlow &&
      partialPaymentFlowVersion == 2
    ) {
      setLocalValue("bundler_product_created", true);
    }

    // 4. Update the cart via AJAX API
    const postResponse = await executePost({
      ...(partialPaymentEnabled &&
        partialPaymentFlowVersion == 1 && {
          updates,
        }),
      attributes,
      note,
    });
    if (!postResponse?.ok) {
      throw new Error(
        `Cart update failed: ${postResponse?.status ?? ""} ${postResponse?.statusText ?? ""}`.trim() ||
          "Cart update did not succeed",
      );
    }

    // 5. Set flags for revert service if needed
    setLocalValue("codk-updated-cart", "true");
    setLocalValue("codk-current-cart", currentCartData);
    // 6. Build checkout URL, then redirect with the in-progress overlay.
    // redirectToCheckout keeps the modal mounted (shows "Redirection in
    // progress"), navigates the top window, and destroys the iframe via a
    // delayed fallback — so the widget never blanks out mid-redirect.
    const originalUrl = "/checkout";
    let checkoutUrl = "/checkout";
    const apployAppManager = window?.apployAppManager || window?.parent?.apployAppManager;
    const channelId = sessionStorage.getItem('apploy_ma_channel_id');
    if(apployAppManager?.isMobileApp() && channelId){
    // use it to update the checkout url
      checkoutUrl = `${originalUrl}?access_token=${encodeURIComponent(channelId)}`
   }
    // Let any backgrounded buyer-identity save finish so the address persists.
    await waitForPendingBuyerIdentity();
    redirectToCheckout(checkoutUrl);
  } catch (error) {
    handleCheckoutError(error);
  }
};

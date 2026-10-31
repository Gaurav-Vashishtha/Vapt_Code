import {
  applyDiscountCodeToCart,
  removeSelectiveDiscountCodes,
  shopifyAddToCart,
  updateBuyerIdentity,
} from "../../services/cartService";
import { getIsBuyNowButton } from "../../services/domUtils";
import {
  callPartialRuleSets,
  clearCart,
  // createPartialCart,
  executePost,
  getCart,
} from "../../services/otpService";
import { sendErrorToAPI } from "../../services/errorReporter";
import useOtpStore from "../../stores/otpStore";
import {
  debugLog,
  getCurrentStep,
  getLocalValue,
  getSessionValue,
  removeSessionValue,
  setSessionValue,
  removeDiscountCodeFromOtpStore,
  getStorefrontCartId,
} from "../../utilities/otpUtils";
import { removePartialPaymentRuleSetDiscountCodeFromCart } from "../Layout/CommonComponent/paymentOptionsUtils";

let ruleVariantArray = [];
const settings = getSessionValue("settingSession");

/**
 * Function to save the rule-variant array to sessionStorage
 */
function saveRuleVariantArrayToSession() {
  sessionStorage.setItem("ruleVariantArray", JSON.stringify(ruleVariantArray));
  debugLog("Rule-Variant Array saved to sessionStorage:", ruleVariantArray);
}

// export async function operatePartialPayment(cartData) {
//   const otpStoreState = useOtpStore.getState();
//   const {
//     setIsPartialPaymentCartReadyAndUpdated,
//     setSelectedRuleId,
//     showOTPModal,
//   } = otpStoreState;

//   try {
//     debugLog("cartData received:", cartData);

//     // Observe showOTPModal at the start
//     if (!showOTPModal) {
//       debugLog("OTP Modal closed at the start, resetting state...");
//       await resetState();
//       return null;
//     }

//     // Function to observe modal state at each step
//     const observeModalState = async () => {
//       if (!showOTPModal) {
//         debugLog("OTP Modal closed during process, stopping execution...");
//         await resetState();
//         throw new Error("Process stopped due to OTP modal closure.");
//       }
//     };

//     if (getIsBuyNowButton()) {
//       await observeModalState(); // Check before processing
//       const result = await processBuyNow(cartData);
//       await observeModalState(); // Check after processing
//       return result;
//     } else {
//       await observeModalState();
//       const result = await processDrawerCheckout(cartData);
//       await observeModalState();
//       return result;
//     }
//   } catch (error) {
//     console.error("Error in operatePartialPayment:", error);
//     setIsPartialPaymentCartReadyAndUpdated(true);
//     return null;
//   }

//   // Function to reset the state when modal closes
//   async function resetState() {
//     if (getIsBuyNowButton()) {
//       await clearCart();
//     }
//     setIsPartialPaymentCartReadyAndUpdated(false);
//     setSelectedRuleId(null);
//   }
// }

// Process "Buy Now" scenario using ruleVariantArray
// async function processBuyNow(cartData) {
//   debugLog("Processing Buy Now...");

//   const ruleVariantArray = JSON.parse(
//     sessionStorage.getItem("ruleVariantArray") || "[]"
//   );

//   const inputCart = cartData.items.map((item) => {
//     const ruleVariantMatch = ruleVariantArray.find(
//       (entry) => entry.variantId === item.variant_id.toString()
//     );
//     return {
//       cost: item.presentment_price,
//       totalQuantity: item.quantity,
//       title: item.title,
//       imageUrl: item.image,
//       variantId: item.variant_id.toString(),
//       ...(ruleVariantMatch &&
//         ruleVariantMatch.ruleId !== "full_payment" && {
//           ruleId: ruleVariantMatch.ruleId,
//         }),
//     };
//   });

//   debugLog("Generated InputCart:", inputCart);

//   const shop = window.Shopify.shop;
//   const createCartResponse = await createPartialCart(shop, inputCart);

//   removeSessionValue("ruleVariantArray");
//   // setSelectedRuleId("full_payment");

//   return await processCartResponse(createCartResponse);
// }

// Process "Drawer Checkout" scenario
// async function processDrawerCheckout(cartData) {
//   debugLog("Processing drawer checkout...");

//   const ruleVariantArray = JSON.parse(
//     sessionStorage.getItem("ruleVariantArray") || "[]"
//   );

//   const processedItems = cartData.items.map((item) => {
//     const ruleVariantMatch = ruleVariantArray.find(
//       (entry) => entry.variantId === item.variant_id.toString()
//     );

//     return {
//       cost: item.presentment_price,
//       totalQuantity: item.quantity,
//       title: item.title,
//       imageUrl: item.image,
//       variantId: item.variant_id.toString(),
//       ...(ruleVariantMatch &&
//         ruleVariantMatch.ruleId !== "full_payment" && {
//           ruleId: ruleVariantMatch.ruleId,
//         }),
//     };
//   });

//   debugLog("Processed Items:", processedItems);

//   const shop = window.Shopify.shop;
//   const createCartResponse = await createPartialCart(shop, processedItems);
//   //after createPartialCart , update the partialProduct variant in session storage from ruleVariant ID
//   function getVariantIds() {
//     // Retrieve the ruleVariantArray from sessionStorage, defaulting to an empty array if not found.
//     const ruleVariantArray = JSON.parse(
//       sessionStorage.getItem("ruleVariantArray") || "[]"
//     );

//     // Map the array to extract only the variantId values.
//     const variantIds = ruleVariantArray.map((item) => item.variantId);

//     return variantIds;
//   }
//   const variantIdsArray = getVariantIds();
//   debugLog(variantIdsArray);

//   setSessionValue("partial_payment_variants", variantIdsArray);

//   removeSessionValue("ruleVariantArray");
//   // setSelectedRuleId("full_payment");

//   return await processCartResponse(createCartResponse);
// }

// export async function processCartResponse(createCartResponse) {
//   const otpStoreState = useOtpStore.getState();
//   const { setIsPartialPaymentCartReadyAndUpdated, setSelectedRuleId } =
//     otpStoreState;

//   // Helper function to reset state. This also clears the cart if in Buy Now flow.
//   async function resetState() {
//     if (getIsBuyNowButton()) {
//       await clearCart();
//     }
//     setIsPartialPaymentCartReadyAndUpdated(false);
//     setSelectedRuleId(null);
//   }

//   // Helper function to check if the OTP modal is still open.
//   async function observerModalState() {
//     const currentModalState = useOtpStore.getState().showOTPModal;
//     if (!currentModalState) {
//       debugLog(
//         "OTP Modal closed during processCartResponse, aborting process."
//       );
//       await resetState();
//       throw new Error(
//         "Process stopped due to OTP modal closure in processCartResponse."
//       );
//     }
//   }

//   const partCartData =
//     createCartResponse?.data?.cartItems || createCartResponse?.data;
//   if (!partCartData || partCartData.length === 0) {
//     console.error(
//       "Invalid response from createPartialCart: partCartData is missing or empty."
//     );
//     return null;
//   }

//   const cartItems = partCartData
//     .filter((item) => item.variantId && item.totalQuantity)
//     .map((item) => {
//       const originalCost = item.originalCost; // Assuming originalCost is available in item
//       const totalOriginalCost = (
//         parseFloat(originalCost) * parseFloat(item.totalQuantity)
//       ).toFixed(2); // Calculate total original cost
//       const totalCost = (
//         parseFloat(item.cost) * parseFloat(item.totalQuantity)
//       ).toFixed(2); // Calculate total cost
//       const remainingAmount = totalOriginalCost - totalCost; // Calculate remaining amount

//       return {
//         id: item.variantId,
//         quantity: item.totalQuantity,
//         properties: {
//           description: `Part Payment Details: Actual Cost: ₹${totalOriginalCost} | Remaining Amount: ₹${remainingAmount}`,
//         },
//       };
//     });

//   if (cartItems.length === 0) {
//     console.error("No valid items found in partCartData.");
//     return null;
//   }

//   try {
//     await observerModalState();
//     await clearCart();
//     debugLog("Cart cleared successfully.");
//     await observerModalState();
//     const createdCart = getSessionValue("created-cart");
//     const checkoutUrl = createdCart?.checkoutUrl;
//     if (checkoutUrl) {
//       // removed created-cart so that it redirects to /checkout insteal of checkout url
//       debugLog("createdCart removed");
//       removeSessionValue("created-cart");
//     }
//     const cart = await shopifyAddToCart(cartItems);

//     await observerModalState();

//     if (!cart) {
//       console.error("Failed to create cart.");
//       return null;
//     }

//     debugLog("Cart updated successfully:", cart);
//   } catch (error) {
//     console.error("Error while adding items to cart:", error);
//     return null;
//   }

//   let updatedCartData;
//   try {
//     await observerModalState();
//     updatedCartData = await getCart();
//     await observerModalState();
//     setIsPartialPaymentCartReadyAndUpdated(true);
//   } catch (error) {
//     console.error("Error while fetching updated cart data:", error);
//     return null;
//   }

//   if (!updatedCartData) {
//     console.error("Failed to fetch updated cart data.");
//     return null;
//   }

//   debugLog("Updated Cart Data:", updatedCartData);
//   return updatedCartData;
// }

const rebuildCartWithPartialVariants = async (cart, partialCartItems) => {
  try {
    const newItems = [];
    cart.items.forEach((item) => {
      // Find if this cart item is a partial payment variant
      const match = partialCartItems.find(
        (p) => p.variantId == item.variant_id // match against partial variant ID
      );

      const variantId = match
        ? parseInt(match.originalVariantId) // replace with original
        : item.variant_id;

      newItems.push({
        id: variantId,
        quantity: item.quantity,
      });
    });
    await clearCart();
    await shopifyAddToCart(newItems);
    debugLog("✅ Cart rebuilt successfully with original variants.", newItems);
    const { setIsPartialCartRevertToOriginalCartCompleted } =
      useOtpStore.getState();
    setIsPartialCartRevertToOriginalCartCompleted(true);
  } catch (error) {
    console.error("❌ Failed to rebuild cart:", error);
  }
};

export const checkPartialPayment = async () => {
  const isPartialEnabled = settings?.partialPaymentEnabled === true;
  if (!getIsBuyNowButton() && isPartialEnabled) {
    try {
      const cart = await getCart(true);

      /* 2️⃣  Normal partial-cart reconciliation flow */
      const stored = getLocalValue("partialCartData");
      const partialCartItems = Array.isArray(stored)
        ? stored
        : (() => {
            try {
              return JSON.parse(stored);
            } catch {
              return [];
            }
          })();

      if (!Array.isArray(partialCartItems) || !cart?.items?.length) {
        debugLog(
          "No partial cart items or cart is empty, setting revert flag to true"
        );
        const { setIsPartialCartRevertToOriginalCartCompleted } =
          useOtpStore.getState();
        setIsPartialCartRevertToOriginalCartCompleted(true);
        return;
      }

      const cartVariantIds = cart.items.map((i) => String(i.variant_id));
      const shouldUpdateCart = partialCartItems.some((i) =>
        cartVariantIds.includes(String(i.variantId))
      );

      const { setIsPartialCartRevertToOriginalCartCompleted } =
        useOtpStore.getState();
      if (shouldUpdateCart) {
        debugLog("Partial cart update triggered.");
        debugLog("Partial cart update triggered. Clearing discounts...");

        await rebuildCartWithPartialVariants(cart, partialCartItems);
      } else {
        const hasInvalidItem = cart?.items?.some((item) =>
          item.title?.toLowerCase().includes("partial payment")
        );

        // here check the order SUmmary completed or not
        if (hasInvalidItem) {
          debugLog(
            "Cart has partial payment item — clearing cart and redirecting."
          );
          await clearCart();

          window.location.href = "/";

          return; // stop right here
        }
        debugLog("No changes required in cart so updating the cart");
        setIsPartialCartRevertToOriginalCartCompleted(true);
      }
    } catch (err) {
      console.error("Error in checkPartialPayment:", err);
    }
  }
};

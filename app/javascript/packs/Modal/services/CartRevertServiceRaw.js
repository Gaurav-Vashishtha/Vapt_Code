// /**
//  * Revert Cart Service (Raw Fetch version)
//  * This version uses standard browser APIs (fetch, localStorage) to revert the cart
//  * to its original state without relying on project-specific utility imports.
//  */
// export const CartRevertServiceRaw = async () => {
//   try {
//     // 1. Retrieve required data from localStorage
//     const updatedCartFlag = localStorage.getItem("codk-updated-cart");
//     const currentCartDataString = localStorage.getItem("codk-current-cart");
//     const partialCartDataString = localStorage.getItem("partialCartData");

//     if (!updatedCartFlag || !currentCartDataString) {
//       console.log("[CartRevertService] No updated cart found to revert.");
//       return;
//     }

//     const currentCartData = JSON.parse(currentCartDataString);
//     const partialCartData = partialCartDataString
//       ? JSON.parse(partialCartDataString)
//       : [];

//     console.log("[CartRevertService] Starting raw revert process...");

//     // 2. Prepare original line items and matching logic
//     const updates = {};
//     (currentCartData.items || []).forEach((item) => {
//       let variantIdToUse = item.variant_id || item.id;

//       // Special handling for Partial Payment matching
//       if (partialCartData && partialCartData.length > 0) {
//         const partialMatch = partialCartData.find(
//           (pc) => String(pc.variantId) === String(variantIdToUse)
//         );
//         if (partialMatch && partialMatch.originalVariantId) {
//           variantIdToUse = partialMatch.originalVariantId;
//         }
//       }

//       // Remove the "dirty" variant and restore the original variant
//       updates[item.variant_id || item.id] = 0;
//       updates[variantIdToUse] = parseInt(item.quantity) || 1;
//     });

//     // 4. Restore original items, clear partial payment attributes and discount codes
//     const updatePayload = {
//       updates,
//       attributes: {
//         _codkFinalDiscountValue: "",
//         _codkFreeVariants: "",
//         _codkAmountType: "",
//         _codkAmountValue: "",
//         _partialPaymentProduct: "",
//         partial_payment_variants: "",
//         _codkPaymentDescription: "",
//       },
//       discount: "",
//     };

//     const updateResponse = await fetch(
//       `${window.Shopify?.routes?.root || "/"}cart/update.js`,
//       {
//         method: "POST",
//         headers: {
//           "Content-Type": "application/json",
//           "X-Requested-With": "XMLHttpRequest",
//         },
//         body: JSON.stringify(updatePayload),
//       }
//     );

//     if (!updateResponse.ok) {
//       throw new Error(`Failed to restore cart: ${updateResponse.statusText}`);
//     }

//     // 5. Cleanup localStorage flags
//     localStorage.removeItem("codk-updated-cart");

//     console.log(
//       "[CartRevertService] Cart successfully reverted using raw fetch."
//     );
//   } catch (error) {
//     console.error("[CartRevertService] Raw revert failed:", error);
//   }
// };

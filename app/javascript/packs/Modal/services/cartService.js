// CartService.js
import { createLightweightGraphQLClient } from "./lightweightGraphQLClient";
import { executeWithErrorHandling, retryOperation } from "./errorHandler";
import {
  debugLog,
  getLocalValue,
  getSessionValue,
  getVariantIdQuantityAndProperties,
  setSessionValue,
} from "../utilities/otpUtils";
import useOtpStore from "../stores/otpStore";
import { clearCart, getCart, executePost } from "./otpService";
import { sendErrorToAPI } from "./errorReporter";
const CART_CREATE_MUTATION = `
  mutation CartCreate(
    $lines: [CartLineInput!]!
    $email: String
    $countryCode: CountryCode
    $address1: String
    $address2: String
    $city: String
    $province: String
    $country: String
    $zip: String
    $cartAttributes: [AttributeInput!]!
    $phone: String
    $firstName: String
    $lastName: String
  ) {
    cartCreate(
      input: {
        lines: $lines
        buyerIdentity: {
          email: $email
          countryCode: $countryCode
          deliveryAddressPreferences: {
            oneTimeUse: false
            deliveryAddress: {
              address1: $address1
              address2: $address2
              city: $city
              province: $province
              country: $country
              zip: $zip
              phone: $phone
              firstName: $firstName
              lastName: $lastName
            }
          }
          preferences: { delivery: { deliveryMethod: SHIPPING } }
        }
        attributes: $cartAttributes
      }
    ) {
      cart {
        id
        checkoutUrl
        attributes { key value }
        discountCodes {
          code
          applicable
        }
        lines(first: 10) {
          edges {
            node {
              id
              quantity
              merchandise {
                ... on ProductVariant {
                  id
                }
              }
              cost {
                totalAmount {
                  amount
                  currencyCode
                }
                amountPerQuantity {
                  amount
                  currencyCode
                }
                subtotalAmount {
                  amount
                  currencyCode
                }
              }
              discountAllocations {
                discountedAmount {
                  amount
                  currencyCode
                }
              }
            }
          }
        }
        cost {
          totalAmount {
            amount
            currencyCode
          }
          subtotalAmount {
            amount
            currencyCode
          }
          totalTaxAmount {
            amount
            currencyCode
          }
          totalDutyAmount {
            amount
            currencyCode
          }
        }
        discountAllocations {
          discountedAmount {
            amount
            currencyCode
          }
        }
      }
    }
  }
`;
// Minimal cart create mutation without buyerIdentity, for fallback
const CART_CREATE_MIN_MUTATION = `
  mutation CartCreate($lines: [CartLineInput!]!, $cartAttributes: [AttributeInput!]!) {
    cartCreate(input: { lines: $lines, attributes: $cartAttributes }) {
      cart {
        id
        checkoutUrl
        attributes { key value }
        discountCodes {
          code
          applicable
        }
        lines(first: 10) {
          edges {
            node {
              id
              quantity
              cost {
                totalAmount { amount currencyCode }
                amountPerQuantity { amount currencyCode }
                subtotalAmount { amount currencyCode }
              }
              discountAllocations {
                discountedAmount {
                  amount
                  currencyCode
                }
              }
            }
          }
        }
        cost {
          totalAmount { amount currencyCode }
          subtotalAmount { amount currencyCode }
          totalTaxAmount { amount currencyCode }
          totalDutyAmount { amount currencyCode }
        }
        discountAllocations {
          discountedAmount {
            amount
            currencyCode
          }
        }
      }
      userErrors { field message }
    }
  }
`;
// Define the cartBuyerIdentityUpdate mutation

// const CART_CREATE_MUTATION = gql`
//   mutation CartCreate(
//     $lines: [CartLineInput!]!
//     $cartAttributes: [AttributeInput!]!
//   ) {
//     cartCreate(input: { lines: $lines, attributes: $cartAttributes }) {
//       cart {
//         id
//         checkoutUrl
//         lines(first: 10) {
//           edges {
//             node {
//               id
//               merchandise {
//                 ... on ProductVariant {
//                   id
//                 }
//               }
//             }
//           }
//         }
//         cost {
//           totalAmount {
//             amount
//             currencyCode
//           }
//         }
//       }
//     }
//   }
// `;

const CART_BUYER_IDENTITY_UPDATE_MUTATION = `
  mutation cartBuyerIdentityUpdate(
    $cartId: ID!
    $buyerIdentity: CartBuyerIdentityInput!
  ) {
    cartBuyerIdentityUpdate(cartId: $cartId, buyerIdentity: $buyerIdentity) {
      cart {
        id
        checkoutUrl
        buyerIdentity {
          email
          phone
          countryCode
          deliveryAddressPreferences {
            ... on MailingAddress {
              address1
              address2
              city
              province
              country
              zip
              firstName
              lastName
              phone
            }
          }
        }
      }
      userErrors {
        field
        message
      }
    }
  }
`;

const CART_DISCOUNT_CODES_UPDATE = `
  mutation cartDiscountCodesUpdate($cartId: ID!, $discountCodes: [String!]) {
    cartDiscountCodesUpdate(cartId: $cartId, discountCodes: $discountCodes) {
      cart {
        id
        discountCodes {
          code
          applicable
        }
        checkoutUrl
        cost {
          totalAmount {
            amount
            currencyCode
          }
        }
      }
      userErrors {
        field
        message
      }
    }
  }
`;

export const updateBuyerIdentity = async (cartId, buyerIdentity) => {
  return executeWithErrorHandling(
    async () => {
      const settings = getSessionValue("settingSession");
      const shopifyDomain = window.Shopify?.shop;
      const storefrontToken = settings?.storeFrontToken;

      if (!shopifyDomain || !storefrontToken) {
        throw new Error("Shopify configuration not found");
      }

      const client = createLightweightGraphQLClient(
        shopifyDomain,
        storefrontToken
      );

      const { data } = await client.mutateWithCacheClear(
        CART_BUYER_IDENTITY_UPDATE_MUTATION,
        {
          cartId,
          buyerIdentity,
        }
      );

      if (data?.cartBuyerIdentityUpdate?.userErrors?.length) {
        console.error("User errors:", data.cartBuyerIdentityUpdate.userErrors);
        throw new Error(data?.cartBuyerIdentityUpdate?.userErrors[0]?.message);
      }

      if (data?.cartBuyerIdentityUpdate?.cart) {
        debugLog(
          "Buyer identity successfully updated:",
          data.cartBuyerIdentityUpdate.cart
        );
        return data.cartBuyerIdentityUpdate.cart;
      } else {
        console.error("Failed to update buyer identity. Response:", data);
        throw new Error("Buyer identity update failed");
      }
    },
    { operation: "updateBuyerIdentity" }
  );
};

// Create a function that uses the lightweight GraphQL client to run the mutation
export const createCart = async (variables) => {
  return executeWithErrorHandling(
    async () => {
      const settings = getSessionValue("settingSession");
      const shopifyDomain = window.Shopify?.shop;
      const storefrontToken = settings?.storeFrontToken;

      if (!shopifyDomain || !storefrontToken) {
        throw new Error("Shopify configuration not found");
      }

      const client = createLightweightGraphQLClient(
        shopifyDomain,
        storefrontToken
      );

      const { data } = await client.mutateWithCacheClear(
        CART_CREATE_MUTATION,
        variables
      );

      // Surface userErrors if present
      if (data?.cartCreate?.userErrors?.length) {
        console.error("CartCreate userErrors:", data.cartCreate.userErrors);
        throw new Error(
          data.cartCreate.userErrors[0]?.message || "Cart creation failed"
        );
      }

      if (data?.cartCreate?.cart) {
        debugLog("Cart successfully created:", data.cartCreate.cart);
        return data.cartCreate.cart;
      } else {
        console.error(
          "Failed to create cart. Full response:",
          data,
          "Variables:",
          variables,
          "— Retrying with minimal mutation"
        );
        // Fallback: retry with minimal mutation (no buyerIdentity)
        const { data: dataMin } = await client.mutateWithCacheClear(
          CART_CREATE_MIN_MUTATION,
          { lines: variables.lines, cartAttributes: variables.cartAttributes }
        );

        if (dataMin?.cartCreate?.userErrors?.length) {
          console.error(
            "CartCreate (min) userErrors:",
            dataMin.cartCreate.userErrors
          );
          throw new Error(
            dataMin.cartCreate.userErrors[0]?.message || "Cart creation failed"
          );
        }

        if (dataMin?.cartCreate?.cart) {
          debugLog("Cart successfully created (min):", dataMin.cartCreate.cart);
          return dataMin.cartCreate.cart;
        }

        console.error("Cart creation failed (min). Response:", dataMin);
        throw new Error("Cart creation failed");
      }
    },
    { operation: "createCart" }
  );
};

//important function to handle partial product  with zero amount

const checkInvalidPartialProductAndRedirect = async () => {
  const cart = await getCart(true);
  const { setIsPartialCartRevertToOriginalCartCompleted } =
    useOtpStore.getState();

  const hasInvalidItem = cart.items?.some((item) =>
    item.title?.toLowerCase().includes("partial payment")
  );

  if (hasInvalidItem) {
    debugLog(
      "Cart has partial payment item with zero price — clearing cart and redirecting."
    );
    await clearCart();
    window.location.href = "/";
    return true;
  }

  if (!cart?.items?.length) {
    debugLog("Cart is empty, setting revert flag to true");
    setIsPartialCartRevertToOriginalCartCompleted(true);
    return false;
  }

  return false;
};

export async function shopifyAddToCartForBuyNow() {
  const otpStoreState = useOtpStore.getState();

  await clearCart();

  const { variantID, quantity, properties } =
    getVariantIdQuantityAndProperties();

  const formData = {
    items: [
      {
        id: variantID,
        quantity: quantity,
        properties: properties,
      },
    ],
  };

  try {
    // Clear the cart before adding the new item
    // await clearCart();

    let success = false;
    let attempts = 0;
    while (!success && attempts < 5) {
      try {
        const response = await fetch(
          window.Shopify.routes.root + "cart/add.js",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify(formData),
          }
        );

        if (!response.ok)
          throw new Error(`Add to cart failed: ${response.status}`);
        await response.json();
        success = true;
      } catch (err) {
        await clearCart();
        attempts++;
        console.warn(`Attempt ${attempts} failed to add to cart. Retrying...`);
        if (attempts >= 5) throw err;
      }
    }

    debugLog("cart is updated here");
    setSessionValue("fetchProductDetailsTrigger", "true");
    // return true;

    // Check if partial payment is enabled and set the revert flag
    const settings = getSessionValue("settingSession");
    if (settings?.partialPaymentEnabled === true) {
      // const { setIsPartialCartRevertToOriginalCartCompleted } =
      //   useOtpStore.getState();
      const redirected = await checkInvalidPartialProductAndRedirect();

      // setIsPartialCartRevertToOriginalCartCompleted(true);

      if (redirected) return;
    }

    debugLog("Item added to cart successfully!");
  } catch (error) {
    console.error("Error during Buy Now process:", error);
    sendErrorToAPI(error, "shopifyAddToCartForBuyNow", "error", {
      operation: "shopifyAddToCartForBuyNow",
      variantId,
      quantity,
      properties,
      isBuyNow: true,
    });
    throw error;
  }
}

export async function shopifyAddToCart(itemOrItems) {
  let lastError = null;
  const maxRetries = 5;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      // Validate the input
      if (!itemOrItems) {
        throw new Error(
          "Invalid input. Must include an item or an array of items."
        );
      }

      // Determine if the input is a single item or an array of items
      const items = Array.isArray(itemOrItems) ? itemOrItems : [itemOrItems];

      // Validate each item
      items.forEach((item) => {
        if (!item.id || !item.quantity) {
          throw new Error("Each item must include id and quantity.");
        }
      });

      // Prepare the payload
      const payload = items.map((item) => ({
        id: item.id,
        quantity: item.quantity,
        properties: item.properties || {},
      }));

      // Perform the fetch request
      const response = await fetch(window.Shopify.routes.root + "cart/add.js", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ items: payload }),
      });

      // Check if the response is successful
      if (!response.ok) {
        throw new Error("Failed to add item(s) to cart.");
      }

      // Parse the JSON response
      const cartData = await response.json();
      debugLog("Item(s) added to cart successfully:", cartData);
      return cartData; // Success: exit the retry loop
    } catch (error) {
      lastError = error;
      console.error(`Attempt ${attempt}/${maxRetries} failed:`, error);

      // Linear backoff: 1s, 2s, 3s, 4s
      if (attempt < maxRetries) {
        const delay = attempt * 1000; // 1000ms, 2000ms, 3000ms
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  // If all retries failed
  console.error("All retries failed. Last error:", lastError);
  sendErrorToAPI(lastError, "shopifyAddToCart", "error", {
    operation: "shopifyAddToCart",
    itemOrItems: Array.isArray(itemOrItems) ? itemOrItems.length : 1,
    retryCount: MAX_RETRIES,
    isBuyNow: false,
  });
  return null;
}

export const applyDiscountCodeToCart = async (cartId, discountCode) => {
  return executeWithErrorHandling(
    async () => {
      const settings = getSessionValue("settingSession");
      const shopifyDomain = window.Shopify?.shop;
      const storefrontToken = settings?.storeFrontToken;

      if (!shopifyDomain || !storefrontToken) {
        throw new Error("Shopify configuration not found");
      }

      const client = createLightweightGraphQLClient(
        shopifyDomain,
        storefrontToken
      );

      const { data } = await client.mutateWithCacheClear(
        CART_DISCOUNT_CODES_UPDATE,
        {
          cartId,
          discountCodes: [discountCode],
        }
      );

      const response = data?.cartDiscountCodesUpdate;

      if (response?.userErrors?.length) {
        console.error("Discount code error:", response.userErrors);
        throw new Error(response.userErrors[0].message);
      }

      debugLog("Discount applied successfully:", response.cart);
      return response.cart;
    },
    { operation: "applyDiscountCode" }
  );
};

/**
 * Remove all discount codes from cart by directly setting discount to blank in cart.js
 * Simple and direct approach using Shopify's REST API
 *
 * @param {string} cartId - Storefront cart ID (optional, not used for REST API)
 * @param {string[]} discountCodesToKeep - Array of discount codes to keep (ignored - removes all)
 * @returns {Promise<Object>} Updated cart object from cart.js
 */
export const removeSelectiveDiscountCodes = async (
  cartId,
  discountCodesToKeep = []
) => {
  // Clear discount codes and rule-based discount attributes; discount: "" removes all discounts.
  const response = await executePost({
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
    discount: "",
  });

  return response.json();
};

export const removeDiscountCodeAndAttribute = async () => {
  // Clear discount codes and rule-based discount attributes so payment customization
  // (cod-king-discount-function) does not re-apply discounts; discount: "" removes all discounts.
  const response = await executePost({
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
    discount: "",
  });

  return response.json();
};

const verifyDiscountCodeRemoval = async (
  discountCodesToKeep = [],
  maxAttempts = 5,
  delayMs = 300
) => {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, delayMs));

    try {
      const verifiedCart = await getCart(true);
      const verifiedCodes = verifiedCart?.discount_codes || [];
      const expectedCount = discountCodesToKeep.length;
      const actualCount = verifiedCodes.length;

      debugLog(
        `🔍 [verifyDiscountCodeRemoval] Attempt ${attempt}/${maxAttempts}`,
        {
          expectedCount,
          actualCount,
          verifiedCodes,
          codesToKeep: discountCodesToKeep,
        }
      );

      if (discountCodesToKeep.length === 0) {
        // Removing all codes - verify none remain
        if (actualCount === 0) {
          debugLog(
            `✅ [verifyDiscountCodeRemoval] All discount codes successfully removed`
          );
          return true;
        }
      } else {
        // Keeping specific codes - verify they match
        const codesMatch = discountCodesToKeep.every((code) =>
          verifiedCodes.includes(code)
        );
        if (codesMatch && actualCount === expectedCount) {
          debugLog(
            `✅ [verifyDiscountCodeRemoval] Discount codes match expected values`
          );
          return true;
        }
      }

      // If this is the last attempt, return false
      if (attempt === maxAttempts) {
        console.warn(
          `⚠️ [verifyDiscountCodeRemoval] Verification failed after ${maxAttempts} attempts. Remaining codes:`,
          verifiedCodes
        );
        return false;
      }
    } catch (verifyError) {
      console.warn(
        `⚠️ [verifyDiscountCodeRemoval] Verification attempt ${attempt} failed:`,
        verifyError
      );
      if (attempt === maxAttempts) {
        return false;
      }
    }
  }

  return false;
};

/**
 * Remove discount codes individually (one by one)
 * This is a fallback when bulk removal fails
 * @param {string} cartId - Storefront cart ID
 * @param {string[]} discountCodesToKeep - Array of codes to keep
 * @returns {Promise<boolean>} True if successful, false otherwise
 */
const removeDiscountCodesIndividually = async (
  cartId,
  discountCodesToKeep = []
) => {
  try {
    // Get current cart to see what codes exist
    const currentCart = await getCart(true);
    const existingCodes = currentCart?.discount_codes || [];

    if (existingCodes.length === 0) {
      debugLog(
        `✅ [removeDiscountCodesIndividually] No discount codes to remove`
      );
      return true;
    }

    // Filter out codes we want to keep
    const codesToRemove = existingCodes.filter(
      (code) => !discountCodesToKeep.includes(code)
    );

    if (codesToRemove.length === 0) {
      debugLog(
        `✅ [removeDiscountCodesIndividually] All codes are already in keep list`
      );
      return true;
    }

    debugLog(
      `🔄 [removeDiscountCodesIndividually] Removing ${codesToRemove.length} codes individually...`,
      codesToRemove
    );

    const settings = getSessionValue("settingSession");
    const shopifyDomain = window.Shopify?.shop;
    const storefrontToken = settings?.storeFrontToken;

    if (!shopifyDomain || !storefrontToken) {
      console.warn(
        "⚠️ [removeDiscountCodesIndividually] Shopify configuration not found"
      );
      return false;
    }

    const client = createLightweightGraphQLClient(
      shopifyDomain,
      storefrontToken
    );

    // Strategy: Remove all codes, then re-add the ones we want to keep
    // This is more reliable than removing individually
    const codesToKeepArray = discountCodesToKeep || [];

    debugLog(
      `🔄 [removeDiscountCodesIndividually] Setting discount codes to:`,
      codesToKeepArray
    );

    const { data } = await client.mutateWithCacheClear(
      CART_DISCOUNT_CODES_UPDATE,
      {
        cartId,
        discountCodes: codesToKeepArray, // Empty array removes all, then we can re-add if needed
      }
    );

    const response = data?.cartDiscountCodesUpdate;

    if (response?.userErrors?.length) {
      console.warn(
        "⚠️ [removeDiscountCodesIndividually] User errors:",
        response.userErrors
      );
      return false;
    }

    // Verify removal succeeded
    await new Promise((resolve) => setTimeout(resolve, 500));
    const verified = await verifyDiscountCodeRemoval(
      discountCodesToKeep,
      3,
      400
    );

    return verified;
  } catch (error) {
    console.error(
      "❌ [removeDiscountCodesIndividually] Individual removal failed:",
      error
    );
    return false;
  }
};

/**
 * Fallback method to verify discount code removal
 * Since GraphQL mutations are eventually consistent, we wait and verify
 * @param {string[]} discountCodesToKeep - Array of discount codes to keep
 * @returns {Promise<Object>} Updated cart object
 */
const removeDiscountCodesFallback = async (discountCodesToKeep = []) => {
  try {
    debugLog(
      "🔄 [removeDiscountCodesFallback] Waiting for GraphQL changes to propagate and verifying..."
    );

    // Wait for GraphQL mutation to propagate (Shopify's GraphQL is eventually consistent)
    const maxVerificationAttempts = 5;
    const verificationDelay = 400; // ms between attempts

    for (
      let verifyAttempt = 1;
      verifyAttempt <= maxVerificationAttempts;
      verifyAttempt++
    ) {
      await new Promise((resolve) => setTimeout(resolve, verificationDelay));

      // Fetch fresh cart to verify discount codes were removed
      const updatedCart = await getCart(true);
      const remainingCodes = updatedCart?.discount_codes || [];
      const remainingApplicableCodes = remainingCodes.filter((code) => {
        // Check if code exists in discount_codes array
        return code && typeof code === "string" && code.trim().length > 0;
      });

      const expectedCodeCount = discountCodesToKeep.length;
      const actualCodeCount = remainingApplicableCodes.length;

      debugLog(
        `🔍 [removeDiscountCodesFallback] Verification attempt ${verifyAttempt}/${maxVerificationAttempts}`,
        {
          remainingCodes: remainingApplicableCodes,
          expectedCount: expectedCodeCount,
          actualCount: actualCodeCount,
        }
      );

      // If codes match expected count, success!
      if (actualCodeCount === expectedCodeCount) {
        // Verify the codes match what we want to keep
        if (discountCodesToKeep.length === 0) {
          // Removing all codes - verify none remain
          if (actualCodeCount === 0) {
            debugLog(
              `✅ [removeDiscountCodesFallback] All discount codes successfully removed`
            );
            return updatedCart;
          }
        } else {
          // Keeping specific codes - verify they match
          const codesMatch = discountCodesToKeep.every((code) =>
            remainingApplicableCodes.includes(code)
          );
          if (codesMatch && actualCodeCount === expectedCodeCount) {
            debugLog(
              `✅ [removeDiscountCodesFallback] Discount codes match expected values`
            );
            return updatedCart;
          }
        }
      }

      // If this is the last verification attempt, return current state anyway
      if (verifyAttempt === maxVerificationAttempts) {
        console.warn(
          `⚠️ [removeDiscountCodesFallback] Verification timeout. Remaining codes:`,
          remainingApplicableCodes
        );
        return updatedCart;
      }
    }

    // Fallback: return the last fetched cart
    const finalCart = await getCart(true);
    return finalCart;
  } catch (fallbackError) {
    console.error(
      "❌ [removeDiscountCodesFallback] Fallback method failed:",
      fallbackError
    );
    // Don't throw - return null to allow flow to continue
    return null;
  }
};

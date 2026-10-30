/**
 * Cart Service
 *
 * Handles cart operations: fetching, syncing, and reverting
 * Matches notifik-js-app cart service functionality
 */

import {
  getShopDomain,
  hashJsonObject,
  simplifyCartItems,
} from "../utils/helpers.js";
import { updateCartDetailsForPreCreation } from "./api.js";
import { sendErrorToAPI } from "./errorReporter.js";
import {
  getSessionValue,
  setSessionValue,
  getSettings,
} from "./sessionService.js";
import {
  isNoEmailPlaceholder,
  isPreEmailMandatory,
  getNoEmailPlaceholder,
  normalizePhoneForShopify,
} from "../utilities/otpUtils.js";
import { cartFetch, getShopifyRootPath } from "../utils/shopifyCartApi.js";
import { get } from "svelte/store";
import otpStore, { otpStoreActions } from "../stores/otpStore.js";
import { createLightweightGraphQLClient } from "./lightweightGraphQLClient.js";
import { getVariantIdQuantityAndProperties } from "../utils/cartHydration.js";
// import { checkInvalidPartialProductAndRedirect } from "./buyNowService.js";

/**
 * Sync cart with backend
 * Updates backend with current cart state
 * @param {Object} cart - Shopify cart object
 * @returns {Promise<Object>} Sync result
 */
export const syncCartWithBackend = async (cart) => {
  try {
    if (!cart || !cart.items || cart.items.length === 0) {
      return { success: true, skipped: true };
    }

    // Simplify cart items for API
    const simplifiedItems = simplifyCartItems(cart.items);

    // Update cart details via API
    const result = await updateCartDetailsForPreCreation(simplifiedItems);

    if (result) {
      return { success: true, data: result };
    }

    return { success: false, error: "No result from API" };
  } catch (error) {

    return { success: false, error: error.message };
  }
};

/**
 * Check if cart has changed and sync if needed
 * Uses hash-based change detection
 * @param {Object} cartData - Fresh cart data from Shopify
 * @param {Object} cachedCart - Previously cached cart data
 * @returns {Promise<Object>} Update result
 */
export const updateCartIfNeeded = async (cartData, cachedCart) => {
  try {
    // Get session data for OTP verification check
    let isOTPVerified = false;
    try {
      const verifiedData = sessionStorage.getItem("verifiedNumberData");
      if (verifiedData) {
        const parsed = JSON.parse(verifiedData);
        isOTPVerified = !!(parsed && parsed.isOTPVerified);
      }
    } catch (e) {

    }

    // Get settings from sessionStorage
    let settings = {};
    try {
      const settingsStr = sessionStorage.getItem("settingSession");
      if (settingsStr) {
        settings = JSON.parse(settingsStr);
      }
    } catch (e) {

    }

    // Only sync if OTP is verified (matching React app behavior)
    if (!isOTPVerified) {
      return { success: true, skipped: true };
    }

    if (!cartData) {
      return { success: true, skipped: true };
    }

    // First cart load of a verified session (e.g. restored by persistent sign-in): there is no cached
    // cart to diff against, so sync once per tab so the backend knows this session's cart.
    if (!cachedCart) {
      const SYNCED_ONCE_KEY = "codkCartSyncedOnce";
      let alreadySynced = false;
      try {
        alreadySynced = sessionStorage.getItem(SYNCED_ONCE_KEY) === "1";
      } catch (e) {}
      if (alreadySynced || !cartData.items?.length) {
        return { success: true, skipped: true };
      }
      const firstSync = await syncCartWithBackend(cartData);
      if (firstSync.success) {
        try {
          sessionStorage.setItem(SYNCED_ONCE_KEY, "1");
        } catch (e) {}
      }
      return firstSync;
    }

    // Create hash of both carts for comparison
    const currentHash = await hashJsonObject({
      items:
        cartData.items?.map((item) => ({
          variant_id: item.variant_id,
          quantity: item.quantity,
          price: item.price,
        })) || [],
      total_price: cartData.total_price,
    });

    const cachedHash = await hashJsonObject({
      items:
        cachedCart.items?.map((item) => ({
          variant_id: item.variant_id,
          quantity: item.quantity,
          price: item.price,
        })) || [],
      total_price: cachedCart.total_price,
    });

    // If hashes match, no sync needed
    if (currentHash === cachedHash) {
      return { success: true, skipped: true, hashMatch: true };
    }

    // Sync cart with backend
    const syncResult = await syncCartWithBackend(cartData);

    // Update cached cart in sessionStorage
    if (syncResult.success) {
      sessionStorage.setItem("shopify_cart", JSON.stringify(cartData));
    }

    return syncResult;
  } catch (error) {

    sendErrorToAPI(error, "cartService.updateCartIfNeeded", "error", {
      operation: "updateCartIfNeeded",
      hasCartData: !!cartData,
      hasCachedCart: !!cachedCart,
    });
    return { success: false, error: error.message };
  }
};

/**
 * Clear cart via Shopify API
 * Browser API call for cart/clear.js
 * @returns {Promise<Object>} Cleared cart response
 */
export const clearCart = async () => {
  const response = await cartFetch("/cart/clear.js", {
    method: "POST",
    headers: {
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `cart/clear.js failed: ${response.status} ${response.statusText} - ${text}`,
    );
  }

  return response.json();
};

export async function shopifyAddToCartForBuyNow() {
  const otpStoreState = otpStoreActions;

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
        const response = await fetch(`${getShopifyRootPath()}cart/add.js`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(formData),
        });

        if (response.status === 422) {
          let body = null;
          try { body = await response.json(); } catch (_) {}
          const message =
            body?.description || body?.message || "This product can't be added to cart.";
          const blob = `${body?.message ?? ""} ${body?.description ?? ""}`.toLowerCase();
          const isSoldOut =
            blob.includes("sold out") ||
            blob.includes("out of stock") ||
            blob.includes("inventory") ||
            blob.includes("not available");
          const cartErr = new Error(message);
          cartErr.code = isSoldOut ? "OUT_OF_STOCK" : "CART_ADD_FAILED";
          cartErr.status = 422;
          throw cartErr;
        }

        if (!response.ok)
          throw new Error(`Add to cart failed: ${response.status}`);
        await response.json();
        success = true;
      } catch (err) {
        if (err?.code === "OUT_OF_STOCK" || err?.code === "CART_ADD_FAILED") throw err;
        await clearCart();
        attempts++;

        if (attempts >= 5) throw err;
      }
    }

    setSessionValue("fetchProductDetailsTrigger", "true");
  } catch (error) {

    sendErrorToAPI(error, "shopifyAddToCartForBuyNow", "error", {
      operation: "shopifyAddToCartForBuyNow",
      quantity,
      properties,
      isBuyNow: true,
    });
    throw error;
  }
}

/**
 * Get email for buyer identity from session storage (customer-email or cod_king_customer_email).
 * Checks iframe sessionStorage then parent window sessionStorage.
 */
function getEmailFromSessionForBuyerIdentity() {
  const fromIframe =
    getSessionValue("customer-email") ||
    getSessionValue("cod_king_customer_email") ||
    null;
  if (fromIframe) return fromIframe;
  if (
    typeof window !== "undefined" &&
    window.parent &&
    window.parent !== window &&
    window.parent.sessionStorage
  ) {
    try {
      return (
        window.parent.sessionStorage.getItem("customer-email") ||
        window.parent.sessionStorage.getItem("cod_king_customer_email") ||
        null
      );
    } catch (_) {}
  }
  return null;
}

let pendingBuyerIdentity = null;

// Backgrounded buyer-identity saves must land before we navigate to /checkout,
// otherwise the redirect cancels the in-flight mutation and the address is lost.
export const waitForPendingBuyerIdentity = async (timeoutMs = 3000) => {
  const pending = pendingBuyerIdentity;
  if (!pending) return;
  await Promise.race([
    pending,
    new Promise((resolve) => setTimeout(resolve, timeoutMs)),
  ]);
};

export const updateBuyerIdentity = (cartId, buyerIdentity) => {
  const promise = performBuyerIdentityUpdate(cartId, buyerIdentity);
  const tracked = promise.catch(() => null);
  pendingBuyerIdentity = tracked;
  tracked.then(() => {
    if (pendingBuyerIdentity === tracked) pendingBuyerIdentity = null;
  });
  return promise;
};

const performBuyerIdentityUpdate = async (cartId, buyerIdentity) => {
  const settings = getSettings();
  const shopifyDomain = getShopDomain();
  const storefrontToken = settings?.storeFrontToken;

  if (!shopifyDomain || !storefrontToken) {
    throw new Error("Shopify configuration not found");
  }

  if (!cartId) {
    throw new Error("Cart ID is required");
  }

  const storeEmail = get(otpStore)?.verifiedEmail;
  const sessionEmail = getEmailFromSessionForBuyerIdentity();
  const candidateEmail =
    buyerIdentity.email || storeEmail || sessionEmail || "";
  const resolvedEmail = isPreEmailMandatory(settings)
    ? candidateEmail && !isNoEmailPlaceholder(candidateEmail)
      ? String(candidateEmail).trim()
      : null
    : candidateEmail || getNoEmailPlaceholder(buyerIdentity.phone) || "";
  const ensurePlus = (p) => (p && !String(p).startsWith("+") ? `+${p}` : p);
  // Normalize phone to E.164 for Shopify (e.g. India +9106295529286 → +916295529286) so API accepts it
  const normalizedPhone = ensurePlus(normalizePhoneForShopify(buyerIdentity.phone) || buyerIdentity.phone);
  const enrichedIdentity = {
    ...buyerIdentity,
    phone: normalizedPhone,
    email: resolvedEmail,
    deliveryAddressPreferences: Array.isArray(buyerIdentity.deliveryAddressPreferences)
      ? buyerIdentity.deliveryAddressPreferences.map((pref) => ({
          ...pref,
          deliveryAddress: pref.deliveryAddress
            ? {
                ...pref.deliveryAddress,
                phone: ensurePlus(normalizePhoneForShopify(pref.deliveryAddress.phone) || pref.deliveryAddress.phone),
              }
            : pref.deliveryAddress,
        }))
      : buyerIdentity.deliveryAddressPreferences,
  };

  const client = createLightweightGraphQLClient(shopifyDomain, storefrontToken);

  const UPDATE_BUYER_IDENTITY = `
    mutation cartBuyerIdentityUpdate($cartId: ID!, $buyerIdentity: CartBuyerIdentityInput!) {
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

  const { data } = await client.mutateWithCacheClear(UPDATE_BUYER_IDENTITY, {
    cartId,
    buyerIdentity: enrichedIdentity,
  });

  const response = data?.cartBuyerIdentityUpdate;

  if (response?.userErrors?.length) {

    throw new Error(response.userErrors[0].message);
  }

  if (response?.cart) {
    return response.cart;
  } else {

    throw new Error("Buyer identity update failed");
  }
};

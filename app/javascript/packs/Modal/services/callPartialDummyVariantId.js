import { debugLog } from "../utilities/otpUtils";

// Shopify variant ids are numeric, or a numeric gid. The value reaches us from
// the API in a response keyed off a shop domain the parent page supplies, so it
// is validated before it is persisted and used anywhere else.
const VARIANT_ID_PATTERN = /^(?:\d{1,20}|gid:\/\/shopify\/ProductVariant\/\d{1,20})$/;

export const callPartialDummyVariantId = async function () {
  try {
    const shopifyDomain = window.parent.Shopify?.shop || window.Shopify?.shop;
    const response = await fetch(
      `https://${process.env.APP_HOST}/order_confirmations/partial_dummy_variant_id?shopifyDomain=${encodeURIComponent(
        shopifyDomain || "",
      )}`,
      {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
        },
      },
    );

    if (response.ok) {
      const data = await response.json();
      const variantId = data?.variant_id;

      if (variantId && VARIANT_ID_PATTERN.test(String(variantId))) {
        debugLog("Fetched partial dummy variant ID:", variantId);
        sessionStorage.setItem("partialDummyVariantId", String(variantId));
        return variantId;
      } else if (variantId) {
        debugLog("Rejected malformed partial dummy variant ID:", variantId);
        return null;
      } else {
        debugLog("No variant ID in response:", data);
        return null;
      }
    } else {
      debugLog(
        "Failed to fetch Partial Dummy Variant ID:",
        response.statusText,
      );
      return null;
    }
  } catch (error) {
    debugLog("Error fetching Partial Dummy Variant ID:", error);
    return null;
  }
};

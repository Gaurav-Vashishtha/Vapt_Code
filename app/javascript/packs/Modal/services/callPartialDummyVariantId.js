import { debugLog } from "../utilities/otpUtils";

export const callPartialDummyVariantId = async function () {
  try {
    const shopifyDomain = window.parent.Shopify?.shop || window.Shopify?.shop;
    const response = await fetch(
      `https://${process.env.APP_HOST}/order_confirmations/partial_dummy_variant_id?shopifyDomain=${shopifyDomain}`,
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

      if (variantId) {
        debugLog("Fetched partial dummy variant ID:", variantId);
        sessionStorage.setItem("partialDummyVariantId", variantId);
        return variantId;
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

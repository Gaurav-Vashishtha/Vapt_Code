import { getRouteUrl } from "./api";

export const callPartialDummyVariantId = async function () {
  try {
    const cachedVariantId = sessionStorage.getItem("partialDummyVariantId");
    if (cachedVariantId) {
      return cachedVariantId;
    }

    const shopifyDomain = window.parent.Shopify?.shop || window.Shopify?.shop;
    const routeUrl = getRouteUrl();
    const response = await fetch(
      `${routeUrl}order_confirmations/partial_dummy_variant_id?shopifyDomain=${shopifyDomain}`,
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
        sessionStorage.setItem("partialDummyVariantId", variantId);
        return variantId;
      }
      return null;
    }
    return null;
  } catch (_error) {
    return null;
  }
};

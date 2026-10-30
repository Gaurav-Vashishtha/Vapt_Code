import { getRouteUrl } from "./api.js";
import { getCart } from "./otpService.js";
import { cartFetch } from "../utils/shopifyCartApi.js";
import { getShopDomain } from "../utils/helpers.js";
import { getSessionValue, setSessionValue } from "./sessionService.js";

export const UPSELL_PROPERTY = "_codk_upsell_product";

export const fetchUpsellProducts = async (productIds) => {
  const params = new URLSearchParams({
    shop: getShopDomain() || "",
    product_ids: productIds.join(","),
  });
  const response = await fetch(`${getRouteUrl().replace(/\/+$/, "")}/upsells/products?${params}`, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error(`upsells ${response.status}`);
  return response.json();
};

const AUTO_ADDED_KEY = "codkUpsellAutoAdded";

export const autoAddUpsells = async (variantIds, cartToken) => {
  if (!variantIds?.length || !cartToken) return [];
  const stored = getSessionValue(AUTO_ADDED_KEY, {}) || {};
  const done = Array.isArray(stored[cartToken]) ? stored[cartToken] : [];
  const pending = variantIds.filter((id) => !done.includes(id));
  if (!pending.length) return [];

  setSessionValue(AUTO_ADDED_KEY, { [cartToken]: [...done, ...pending] });
  const added = [];
  for (const id of pending) {
    try {
      await addUpsellToCart(id, false);
      added.push(id);
    } catch (_e) {}
  }
  if (added.length) await getCart(true);
  return added;
};

export const addUpsellToCart = async (variantId, refreshCart = true, quantity = 1) => {
  const response = await cartFetch("/cart/add.js", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      items: [{ id: Number(variantId), quantity: Math.max(1, Math.floor(Number(quantity)) || 1), properties: { [UPSELL_PROPERTY]: "true" } }],
    }),
  });
  if (!response.ok) {
    let body = null;
    try {
      body = await response.json();
    } catch (_e) {}
    throw new Error(body?.description || body?.message || "Could not add this item.");
  }
  if (refreshCart) await getCart(true);
};

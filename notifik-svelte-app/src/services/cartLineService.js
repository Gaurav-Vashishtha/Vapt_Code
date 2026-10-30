import { get } from "svelte/store";
import { getCart } from "./otpService.js";
import { cartFetch } from "../utils/shopifyCartApi.js";
import otpStore from "../stores/otpStore.js";
import { settingsStore } from "../stores/settingsStore.js";
import { giftKeysDroppedBy } from "./freeGiftService.js";

const giftKeysToDrop = (key, quantity) => {
  const settings = get(settingsStore);
  const config = settings?.freeGift ?? settings?.free_gift;
  return giftKeysDroppedBy(config, get(otpStore).currentCartData?.items, key, quantity);
};

export const changeCartLineQuantity = async (key, quantity) => {
  const dropped = giftKeysToDrop(key, quantity);
  const response = dropped.length
    ? await cartFetch("/cart/update.js", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ updates: { [key]: quantity, ...Object.fromEntries(dropped.map((k) => [k, 0])) } }),
      })
    : await cartFetch("/cart/change.js", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ id: key, quantity }),
      });
  if (!response.ok) {
    let body = null;
    try {
      body = await response.json();
    } catch (_e) {}
    throw new Error(body?.description || body?.message || "Could not update quantity.");
  }
  await getCart(true);
};

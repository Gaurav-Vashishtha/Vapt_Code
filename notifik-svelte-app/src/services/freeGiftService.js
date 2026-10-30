import { getCart } from "./otpService.js";
import { cartFetch } from "../utils/shopifyCartApi.js";
import { getSessionValue, setSessionValue } from "./sessionService.js";

export const FREE_GIFT_PROPERTY = "_codk_free_gift";
export const GIFT_ICON_URL = "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/gift-icon-animated.svg?v=1792401393";

const ADDED_KEY = "codkFreeGiftAdded";

export const isGiftLine = (item) => Boolean(item?.properties?.[FREE_GIFT_PROPERTY]);

export const giftDiscountCents = (items = []) =>
  (items || []).filter(isGiftLine).reduce((sum, item) => sum + (item.total_discount || 0), 0);

export const cartSummary = (items = []) => {
  const lines = items.filter((item) => !isGiftLine(item));
  return {
    lines,
    subtotal: lines.reduce((sum, item) => sum + Number(item.final_line_price ?? item.line_price ?? 0), 0) / 100,
    count: lines.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    productIds: new Set(lines.map((item) => Number(item.product_id)).filter(Boolean)),
  };
};

const ruleMatches = (rule, cart) => {
  switch (rule.trigger) {
    case "cart_range":
      return cart.subtotal >= Number(rule.min_amount || 0) && (rule.max_amount == null || cart.subtotal < Number(rule.max_amount));
    case "cart_items":
      return cart.count >= Number(rule.min_items || 1);
    case "product": {
      const ids = (rule.product_ids || []).map(Number);
      if (!ids.length) return false;
      return rule.match === "all" ? ids.every((id) => cart.productIds.has(id)) : ids.some((id) => cart.productIds.has(id));
    }
    case "collection": {
      const ids = new Set((rule.collection_product_ids || []).map(Number));
      const qty = cart.lines.filter((item) => ids.has(Number(item.product_id))).reduce((sum, item) => sum + Number(item.quantity || 0), 0);
      return qty >= Number(rule.min_quantity || 1);
    }
    default:
      return false;
  }
};

export const matchedRules = (config, items) => {
  const rules = config?.enabled ? config.rules || [] : [];
  const cart = cartSummary(items);
  const matched = rules.filter((rule) => ruleMatches(rule, cart));
  const picked = config?.stacking ? matched : matched.slice(0, 1);
  const seen = new Set();
  return picked.filter((rule) => !seen.has(rule.gift_variant_id) && seen.add(rule.gift_variant_id));
};

export const nextGoal = (config, items) => {
  if (!config?.enabled) return null;
  const cart = cartSummary(items);
  const upcoming = (config.rules || [])
    .filter((rule) => rule.trigger === "cart_range" && Number(rule.min_amount) > cart.subtotal)
    .sort((a, b) => Number(a.min_amount) - Number(b.min_amount))[0];
  if (!upcoming) return null;
  return {
    rule: upcoming,
    remaining: Number(upcoming.min_amount) - cart.subtotal,
    progress: Math.min(100, Math.round((cart.subtotal / Number(upcoming.min_amount)) * 100)),
  };
};

export const giftKeysDroppedBy = (config, items, key, quantity) => {
  if (!config?.enabled || config.remove_when_ineligible === false) return [];
  const next = (items || []).flatMap((item) => {
    if (item.key !== key) return [item];
    if (quantity <= 0) return [];
    const unit = Number(item.final_line_price || 0) / Math.max(Number(item.quantity) || 1, 1);
    return [{ ...item, quantity, final_line_price: Math.round(unit * quantity) }];
  });
  const kept = new Set(matchedRules(config, next).map((rule) => rule.id));
  return next.filter((item) => isGiftLine(item) && !kept.has(item.properties[FREE_GIFT_PROPERTY])).map((item) => item.key);
};

const readAdded = (token) => {
  const stored = getSessionValue(ADDED_KEY, {}) || {};
  return Array.isArray(stored[token]) ? stored[token] : [];
};

const writeAdded = (token, ids) => setSessionValue(ADDED_KEY, { [token]: ids });

const addGift = (rule) =>
  cartFetch("/cart/add.js", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      items: [{ id: Number(rule.gift_variant_id), quantity: Number(rule.gift_quantity || 1), properties: { [FREE_GIFT_PROPERTY]: rule.id } }],
    }),
  });

const removeLine = (key) =>
  cartFetch("/cart/change.js", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ id: key, quantity: 0 }),
  });

let syncing = false;

export const syncFreeGifts = async (config, cart) => {
  if (syncing || !cart?.token) return { added: [], removed: [] };
  const items = cart.items || [];
  const matched = matchedRules(config, items);
  const matchedIds = new Set(matched.map((rule) => rule.id));
  const giftLines = items.filter(isGiftLine);
  const inCart = new Set(giftLines.map((item) => item.properties[FREE_GIFT_PROPERTY]));
  let added = readAdded(cart.token);

  const toRemove = config?.remove_when_ineligible !== false
    ? giftLines.filter((item) => !matchedIds.has(item.properties[FREE_GIFT_PROPERTY]))
    : [];
  const toAdd = matched.filter((rule) => !inCart.has(rule.id) && !added.includes(rule.id));

  if (!toAdd.length && !toRemove.length) {
    const stale = added.filter((id) => matchedIds.has(id) || inCart.has(id));
    if (stale.length !== added.length) writeAdded(cart.token, stale);
    return { added: [], removed: [] };
  }

  syncing = true;
  const result = { added: [], removed: [] };
  try {
    for (const item of toRemove) {
      const response = await removeLine(item.key);
      if (response.ok) result.removed.push(item.properties[FREE_GIFT_PROPERTY]);
    }
    added = added.filter((id) => !result.removed.includes(id));
    for (const rule of toAdd) {
      added = [...added, rule.id];
      writeAdded(cart.token, added);
      const response = await addGift(rule);
      if (response.ok) result.added.push(rule);
    }
    writeAdded(cart.token, added);
    await getCart(true);
  } catch (_e) {
  } finally {
    syncing = false;
  }
  return result;
};

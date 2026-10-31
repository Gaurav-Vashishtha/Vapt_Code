import { FALLBACK_TEXTS } from "../defaults";

/**
 * Text resolution used by the designer and its preview, the same order as the
 * storefront (G.7): shipped default for the locale < merchant `texts.en` <
 * merchant `texts[locale]` — where `texts.en` counts in another language only for keys
 * COD King has no text of its own for in that language (custom fields, content blocks).
 */
export const defaultText = (defaultsTexts, locale, key) => {
  const shipped = defaultsTexts || {};
  const language = String(locale || "en").split("-")[0];
  const candidates = [shipped[locale], shipped[language], shipped.en, FALLBACK_TEXTS];
  for (let i = 0; i < candidates.length; i += 1) {
    const set = candidates[i];
    if (set && typeof set[key] === "string") return set[key];
  }
  return "";
};

export const resolveText = (config, defaultsTexts, locale, key) => {
  const texts = (config && config.texts) || {};
  const own = texts[locale];
  if (own && typeof own[key] === "string" && own[key] !== "") return own[key];
  const language = String(locale || "en").split("-")[0];
  const shipped = (defaultsTexts || {})[locale] || (defaultsTexts || {})[language];
  const englishCounts = language === "en" || !shipped || typeof shipped[key] !== "string";
  if (englishCounts && texts.en && typeof texts.en[key] === "string" && texts.en[key] !== "") return texts.en[key];
  return defaultText(defaultsTexts, locale, key);
};

/**
 * Write (or clear, when empty) one merchant override. The locale's entry stays even when its
 * last override is cleared: a language the merchant added must stay selectable and be saved
 * with the form (only "Reset this language" removes it).
 */
export const setTextOverride = (config, locale, key, value) => {
  const texts = { ...((config && config.texts) || {}) };
  const set = { ...(texts[locale] || {}) };
  if (value === "" || value === null || value === undefined) delete set[key];
  else set[key] = value;
  texts[locale] = set;
  return { ...config, texts };
};

/** Adds an (empty) language to the form's texts so it is saved and listed after a reload. */
export const addTextLocale = (config, locale) => {
  const texts = { ...((config && config.texts) || {}) };
  if (texts[locale]) return config;
  texts[locale] = {};
  return { ...config, texts };
};

// "secure_note" is no longer shown. The others translate COD King's English defaults of offers,
// buttons and the WhatsApp message (edited where those are set up, with their own languages).
const HIDDEN_TEXT_KEYS = [
  "secure_note", "offer_qty_title", "tier_pack_one", "tier_pack_other", "tier_badge_popular", "tier_badge_best",
  "offer_accept", "offer_decline", "downsell_title", "downsell_body", "downsell_accept", "upsell_title", "bundle_title",
  "pre_upsell_title", "pre_upsell_body", "pre_upsell_decline", "button_buy", "button_checkout", "thank_you_whatsapp_message",
];

/** All text keys the editor lists: shipped keys plus keys of custom fields and content blocks. */
export const allTextKeys = (config, defaultsTexts) => {
  const keys = new Set(Object.keys((defaultsTexts && defaultsTexts.en) || {}));
  Object.keys(FALLBACK_TEXTS).forEach((key) => keys.add(key));
  ((config && config.fields) || []).forEach((field) => {
    keys.add(`label_${field.key}`);
    if (!["consent", "checkbox", "radio", "select", "country", "date"].includes(field.type)) {
      keys.add(`placeholder_${field.key}`);
    }
    keys.add(`error_${field.key}`);
  });
  ((config && config.blocks) || []).forEach((block) => {
    if (block.type === "countdown" || block.type === "rich_text") keys.add(`block_${block.id}_text`);
  });
  // No longer shown in the form (the "Pay in cash when your order arrives" line was removed).
  HIDDEN_TEXT_KEYS.forEach((key) => keys.delete(key));
  return Array.from(keys);
};

export const TEXT_GROUPS = [
  { id: "general", prefixes: ["title", "close", "loading", "powered_by", "secure_note", "summary_", "quantity", "item_", "you_save", "saved_so_far", "out_of_stock", "contact_title", "address_title"] },
  { id: "labels", prefixes: ["label_"] },
  { id: "placeholders", prefixes: ["placeholder_"] },
  { id: "errors", prefixes: ["error_"] },
  { id: "shipping", prefixes: ["shipping_", "discount_", "subtotal", "discount", "shipping", "cod_fee", "tax", "total", "savings", "bill_summary"] },
  { id: "submit", prefixes: ["submit", "pay_online", "processing_", "exit_"] },
  { id: "otp", prefixes: ["otp_"] },
  { id: "payment", prefixes: ["payment_", "bump_", "upsell_"] },
  { id: "thank_you", prefixes: ["thank_you_"] },
  { id: "blocks", prefixes: ["block_"] },
];

export const textGroupOf = (key) => {
  for (let i = 0; i < TEXT_GROUPS.length; i += 1) {
    const group = TEXT_GROUPS[i];
    if (group.prefixes.some((prefix) => key === prefix || key.startsWith(prefix))) return group.id;
  }
  return "general";
};

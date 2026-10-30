import countries from "../../Components/Country";
import { t } from "./i18n";

/* Country list shared with the rest of the admin ([{value: "HU", label}]).
   Six rows of Components/Country.jsx carry a name fragment where the ISO code
   should be ("Republic of", "State of", …). This module needs real ISO-2
   codes, so those rows are dropped here and the six countries added back. */
const MISSING_COUNTRIES = [
  { value: "BQ", label: "Bonaire, Sint Eustatius and Saba" },
  { value: "CD", label: "Congo, Democratic Republic of the" },
  { value: "KR", label: "Korea, Republic of" },
  { value: "MD", label: "Moldova, Republic of" },
  { value: "PS", label: "Palestine, State of" },
  { value: "SH", label: "Saint Helena, Ascension and Tristan da Cunha" },
];

export const COUNTRIES = (() => {
  const seen = new Set();
  const list = [];
  countries.forEach((country) => {
    if (/^[A-Z]{2}$/.test(country.value) && !seen.has(country.value)) {
      seen.add(country.value);
      list.push(country);
    }
  });
  MISSING_COUNTRIES.forEach((country) => {
    if (!seen.has(country.value)) list.push(country);
  });
  return list;
})();

export const countryName = (code) => {
  const match = COUNTRIES.find((country) => country.value === code);
  return match ? match.label : code;
};

/* Locales the storefront package ships defaults for (G.7), then common extras. */
export const SHIPPED_LOCALES = ["en", "hi", "ar", "fr", "es", "hu", "sr", "ur"];
export const RTL_LOCALES = ["ar", "ur", "he", "fa"];
export const LOCALE_NAMES = {
  en: "English", hi: "हिन्दी", ar: "العربية", fr: "Français", es: "Español", hu: "Magyar",
  sr: "Srpski", ur: "اردو", de: "Deutsch", it: "Italiano", pt: "Português", tr: "Türkçe",
  nl: "Nederlands", pl: "Polski", ro: "Română", cs: "Čeština", el: "Ελληνικά", bg: "Български",
  hr: "Hrvatski", sk: "Slovenčina", sl: "Slovenščina", bn: "বাংলা", id: "Bahasa Indonesia",
  ms: "Bahasa Melayu", th: "ไทย", vi: "Tiếng Việt", he: "עברית", fa: "فارسی", ru: "Русский",
  uk: "Українська", zh: "中文", ja: "日本語", ko: "한국어", sv: "Svenska", da: "Dansk", fi: "Suomi",
  nb: "Norsk",
};
export const localeName = (code) => LOCALE_NAMES[code] || code;

/* Feature keys of the gate table (J.1). */
export const FEATURES = {
  CORE: "cod_form_core",
  QUANTITY_OFFERS: "quantity_offers",
  BLOCK_LISTS: "block_lists",
  VELOCITY_LIMITS: "velocity_limits",
  BASIC_ANALYTICS: "basic_analytics",
  FIRST_PIXEL: "first_pixel",
  ABANDONMENT: "abandonment_recovery",
  DISCOUNT_CODE_FIELD: "discount_code_field",
  CUSTOM_FIELDS: "custom_fields",
  PRESET_A: "preset_a",
  TEMPLATES: "templates",
  EMBEDDED_MODE: "embedded_mode",
  ORDER_BUMPS: "order_bumps",
  DOWNSELL: "downsell",
  UPSELL: "upsell",
  GOOGLE_SHEETS: "google_sheets",
  EXTRA_PIXELS: "extra_pixels",
  PIXELS_P3: "pixels_p3",
  ADDRESS_AUTOCOMPLETE: "address_autocomplete",
  THRESHOLD_OFFERS: "threshold_offers",
  MULTIPLE_FORMS: "multiple_forms",
  ADVANCED_ANALYTICS: "advanced_analytics",
  KLAVIYO_OMNISEND: "klaviyo_omnisend",
  RISK_BASED_OTP: "risk_based_otp",
  RTO_GATING: "rto_gating",
  BRANDING_REMOVAL: "branding_removal",
  AB_TESTS: "ab_tests",
};

export const TIER_ORDER = ["free", "pro", "enterprise", "enterprise_plus"];

export const tierName = (tier) => {
  switch (tier) {
    case "pro":
      return t("common.tier_pro", "Pro");
    case "enterprise":
      return t("common.tier_enterprise", "Enterprise");
    case "enterprise_plus":
      return t("common.tier_enterprise_plus", "Enterprise Plus");
    default:
      return t("common.tier_free", "Free");
  }
};

export const nextTier = (tier) => {
  const index = TIER_ORDER.indexOf(tier);
  return index >= 0 && index < TIER_ORDER.length - 1 ? TIER_ORDER[index + 1] : null;
};

/* Product limits (PM decisions, "Limits"). The server enforces them too. */
export const LIMITS = {
  FORMS_WITHOUT_GATE: 1,
  FORMS_MAX: 5,
  ACTIVE_QUANTITY_OFFERS: 50,
  TIERS_PER_OFFER: 5,
  ACTIVE_BUMPS: 20,
  BUMPS_SHOWN: 3,
  ACTIVE_DOWNSELLS: 1,
  BLOCK_ENTRIES_PER_KIND: 5000,
  SHIPPING_PAGE_SIZE: 200,
  AB_VARIANTS_MIN: 2,
  AB_VARIANTS_MAX: 4,
  PIXELS_PER_PLATFORM: 5,
  TEXT_MAX_CHARS: 300,
  TEXT_LOCALES_MAX: 12,
  REGEX_MAX_CHARS: 200,
};

/* Paths of the module (H.4). */
export const BASE_PATH = "/features/cod-form";
export const PATHS = {
  setup: BASE_PATH,
  advanced: `${BASE_PATH}/advanced`,
  buttons: `${BASE_PATH}/buttons`,
  designer: `${BASE_PATH}/designer`,
  forms: `${BASE_PATH}/designer/forms`,
  shipping: `${BASE_PATH}/shipping`,
  fraud: `${BASE_PATH}/fraud`,
  offers: `${BASE_PATH}/offers`,
  abTests: `${BASE_PATH}/offers/ab-tests`,
  formPixels: "/integrations/form-pixels",
  tiktok: "/integrations/tiktok",
  googleSheets: "/integrations/google-sheets",
  analytics: "/usage-analytics/cod-form",
  subscription: "/subscription",
};

export const PIXEL_PLATFORMS = ["meta", "tiktok", "ga4", "google_ads", "snapchat", "pinterest"];
export const P3_PIXEL_PLATFORMS = ["snapchat", "pinterest"];

/* Column keys a Google Sheets row can carry (I.5). */
export const SHEET_COLUMNS = [
  "order_name", "order_id", "created_at", "first_name", "last_name", "phone", "email",
  "address1", "address2", "city", "province", "zip", "country", "items", "quantity",
  "subtotal", "discount", "shipping", "cod_fee", "total", "currency", "shipping_rate",
  "discount_code", "utm_source", "utm_medium", "utm_campaign", "note",
];
export const DEFAULT_SHEET_COLUMNS = [
  "order_name", "created_at", "first_name", "last_name", "phone", "address1", "city",
  "province", "zip", "country", "items", "quantity", "total", "currency",
];

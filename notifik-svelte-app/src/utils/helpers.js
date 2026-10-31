import { getSessionValue } from "../services/sessionService.js";

import { postToParent } from "./parentMessaging";
export const uuidv4 = () => {
  // Backs getMachineId(), which is sent as deviceId with OTP requests, so the
  // value must not come from a predictable source.
  const rng =
    typeof globalThis !== "undefined" && globalThis.crypto ? globalThis.crypto : null;
  if (rng && typeof rng.randomUUID === "function") return rng.randomUUID();
  if (rng && typeof rng.getRandomValues === "function") {
    const bytes = new Uint8Array(16);
    rng.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0"));
    return `${hex.slice(0,4).join("")}-${hex.slice(4,6).join("")}-${hex.slice(6,8).join("")}-${hex.slice(8,10).join("")}-${hex.slice(10,16).join("")}`;
  }
  throw new Error("Secure random source unavailable; cannot generate id");
};

export const getShopDomain = () => {
  if (typeof window === "undefined") return null;

  try {
    return (
      window.Shopify?.shop ||
      window.parent?.Shopify?.shop ||
      getSessionValue("settingSession")?.shopDomain ||
      null
    );
  } catch (error) {
    return null;
  }
};

/**
 * Merchant setting: product/catalog prices already include tax.
 * When true, COD UI must not add or show a separate tax line on top of cart totals.
 * @param {Record<string, unknown>|null|undefined} settings
 */
export const isTaxIncludedWithProduct = (settings) => {
  if (!settings || typeof settings !== "object" || Array.isArray(settings))
    return false;
  const v =
    settings.is_tax_included_with_product ?? settings.isTaxIncludedWithProduct;
  if (v === true || v === 1) return true;
  if (typeof v === "string") {
    const t = v.trim().toLowerCase();
    return t === "true" || t === "1" || t === "yes";
  }
  return false;
};

/** True if any settings blob (session, store, props) has tax-in-prices enabled. */
export const isTaxIncludedWithProductAny = (...sources) =>
  sources.some((s) => isTaxIncludedWithProduct(s));

export const isCartPage = () => {
  if (typeof window === "undefined") return false;
  try {
    const parentWindow = window.parent || window;
    const pathname =
      (parentWindow.location && parentWindow.location.pathname) ||
      window.location.pathname ||
      "";
    return pathname.includes("/cart");
  } catch {
    return (window.location.pathname || "").includes("/cart");
  }
};

/**
 * True when the user's number is an Indian (+91) number.
 * Prefers an explicit calling code; otherwise infers from a stored phone
 * (verified numbers carry the +91 prefix, e.g. "+919141520002").
 * @param {string} [phone] - Phone number, may include "+", country code, spaces
 * @param {string|number} [callingCode] - Country calling code (e.g. "91", "+91", 1)
 * @returns {boolean}
 */
export const isIndianPhoneNumber = (phone, callingCode) => {
  const digits = String(phone ?? "").replace(/\D/g, "");
  if (digits.startsWith("0091")) return true;
  // A verified/E.164 number carries its country code (+91 → "91" + 10 digits).
  // "91" uniquely identifies India, so a length-bearing phone is authoritative.
  if (digits.length >= 11) return digits.startsWith("91");
  // Codeless (e.g. bare 10-digit local) → fall back to an explicit calling code.
  const cc = String(callingCode ?? "").replace(/\D/g, "");
  if (cc) return cc === "91";
  return false;
};

/**
 * True when two phone numbers refer to the same subscriber, ignoring formatting
 * and whether a country code is present (compares the trailing national digits).
 * @param {string} [a]
 * @param {string} [b]
 * @returns {boolean}
 */
export const samePhoneNumber = (a, b) => {
  const da = String(a ?? "").replace(/\D/g, "");
  const db = String(b ?? "").replace(/\D/g, "");
  if (!da || !db) return false;
  const tail = (s) => (s.length > 10 ? s.slice(-10) : s);
  return tail(da) === tail(db);
};

export const isPhoneInList = (phone, list) =>
  Array.isArray(list) && list.some((entry) => samePhoneNumber(phone, entry));

const normalizeEmail = (email) => String(email ?? "").trim().toLowerCase();

export const isEmailInList = (email, list) =>
  !!normalizeEmail(email) &&
  Array.isArray(list) &&
  list.some((entry) => normalizeEmail(entry) === normalizeEmail(email));

export const getMachineId = () => {
  if (typeof window === "undefined") return null;
  let machineId;
 machineId = sessionStorage.getItem("MachineId");
  if(machineId){
    sessionStorage.setItem("MachineId",machineId);
    return machineId;
  }
  if (!machineId) {
    machineId = uuidv4();
    sessionStorage.setItem("MachineId", machineId);
  }
  return machineId;
};

/**
 * Format title with title case and truncation
 * React equivalent: DesktopHeader.js → formatTitle()
 * @param {string} str - Title to format
 * @param {number} maxLen - Maximum length (default 20)
 * @returns {string} Formatted title
 */
export const formatTitle = (str, maxLen = 20) => {
  if (!str) return "";
  const titleCase = str
    .toLowerCase()
    .split(" ")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
  return titleCase.length > maxLen
    ? titleCase.slice(0, maxLen - 3) + "..."
    : titleCase;
};

/**
 * Format a phone number for display: "+91 91415 20002".
 * The store keeps the number either national or country-code prefixed, so
 * `countryCode` is prepended only when the value looks national.
 * @param {string} value - Raw or already prefixed number
 * @param {string} [countryCode] - Calling code ("91" or "+91")
 * @returns {string} Display-ready number ("" when nothing usable)
 */
export const formatPhoneNumber = (value, countryCode = "") => {
  let digits = (value ?? "").toString().replace(/\D/g, "");
  if (!digits) return "";
  const code = (countryCode ?? "").toString().replace(/\D/g, "");
  if (code && !(digits.length > 10 && digits.startsWith(code))) {
    digits = `${code}${digits}`;
  }
  const india = /^91(\d{10})$/.exec(digits);
  if (india) return `+91 ${india[1].slice(0, 5)} ${india[1].slice(5)}`;
  return `+${digits}`;
};

/**
 * Decode HTML entities in a string (e.g. &quot; → ", &amp; → &).
 * Use for display when API/cart returns entity-encoded text.
 * @param {string} str - Possibly entity-encoded string
 * @returns {string} Decoded string (or original if not a string)
 */
export const decodeHtmlEntities = (str) => {
  if (str == null) return "";
  if (typeof str !== "string") return String(str);
  const s = str.trim();
  if (!s) return "";
  try {
    const el = typeof document !== "undefined" ? document.createElement("textarea") : null;
    if (el) {
      el.innerHTML = s;
      return el.value;
    }
    return s.replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
  } catch {
    return s;
  }
};

/**
 * Truncate product/order summary title to avoid overflow (20–40 chars as per layout).
 * @param {string} text - Title text (e.g. product name)
 * @param {number} maxLength - Max characters before "..." (default 35; use 20–40 for dynamics)
 * @returns {string} Truncated text with "..." if longer than maxLength
 */
export const truncateProductTitle = (text, maxLength = 35) => {
  if (!text || typeof text !== "string") return "";
  const str = String(text).trim();
  if (str.length <= maxLength) return str;
  return str.slice(0, maxLength) + "...";
};

/**
 * Get Shopify root path (e.g. '/en/')
 * Matches helper from React/notifik-js implementations.
 */
export const getShopifyRootPath = () => {
  if (typeof window === "undefined") {
    return "";
  }

  try {
    const routes = /** @type {{ root?: string } | undefined } */ (
      window.parent?.Shopify?.routes || window.Shopify?.routes
    );
    return routes?.root || "";
  } catch (error) {

    return "";
  }
};

/**
 * Hash JSON object for comparison
 * React equivalent: otpUtils.js → hashJsonObject()
 * Purpose: Create hash of cart data to detect changes
 * @param {Object} obj - Object to hash
 * @returns {Promise<string>} Hash string
 */
export const hashJsonObject = async (obj) => {
  try {
    // Convert object to stable JSON string (sorted keys for consistency)
    const jsonString = JSON.stringify(obj, Object.keys(obj || {}).sort());

    // Use browser's SubtleCrypto API if available
    if (
      typeof window !== "undefined" &&
      window.crypto &&
      window.crypto.subtle
    ) {
      const encoder = new TextEncoder();
      const data = encoder.encode(jsonString);
      const hashBuffer = await window.crypto.subtle.digest("SHA-256", data);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const hashHex = hashArray
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      return hashHex;
    }

    // Fallback: simple hash using string length and content sampling
    // Not cryptographically secure, but sufficient for change detection
    let hash = 0;
    for (let i = 0; i < jsonString.length; i++) {
      const char = jsonString.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return hash.toString(36);
  } catch (error) {

    // Fallback: return stringified length as basic "hash"
    return JSON.stringify(obj || {}).length.toString();
  }
};

/**
 * Format currency amount
 * @param {number} amount - Amount to format
 * @param {string} currencyCode - Currency code (default: 'INR')
 * @returns {string} Formatted currency string
 */
export const formatCurrency = (amount, currencyCode = "INR") => {
  try {
    let numAmount =
      typeof amount === "number" ? amount : parseFloat(`${amount}`) || 0;
    if (!Number.isFinite(numAmount) || Number.isNaN(numAmount)) {
      numAmount = 0;
    }

    // Currency symbols mapping
    const currencySymbols = {
      INR: "₹",
      USD: "$",
      EUR: "€",
      GBP: "£",
      JPY: "¥",
      CAD: "C$",
      AUD: "A$",
    };

    const symbol = currencySymbols[currencyCode] || currencyCode;

    // Format number with commas
    const formatted = numAmount.toLocaleString("en-IN", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    });

    // Remove .00 for whole numbers
    const result = `${symbol}${formatted}`;
    return result.replace(/\.00$/, "");
  } catch (error) {

    const fallback = `${currencyCode} ${amount}`;
    return fallback.replace(/\.00$/, "");
  }
};

/** Resolve cart line item to a single image URL (Shopify cart.js / Storefront API). */
export function resolveCartItemImageUrl(item) {
  if (!item) return "";
  const img = item.image;
  if (typeof img === "string" && img) return img;
  if (img && typeof img === "object" && img.url) return img.url;
  if (item.featured_image?.url) return item.featured_image.url;
  if (typeof item.featured_image === "string" && item.featured_image)
    return item.featured_image;
  const v = item.variant;
  if (v?.image?.url) return v.image.url;
  if (typeof v?.image === "string" && v.image) return v.image;
  if (typeof item.image_url === "string" && item.image_url) return item.image_url;
  return "";
}

export const mapCartToOrderSummary = (cart, currencyFallback = "INR") => {
  if (!cart || !Array.isArray(cart.items)) {

    return {
      items: [],
      itemCount: 0,
      total: 0,
      originalTotal: 0,
      discountAmount: 0,
      hasDiscount: false,
      currency: currencyFallback,
      discountCode: "",
      discountName: "",
      discountType: "",
      discountValue: "",
      taxAmount: 0,
    };
  }

  const currency = cart.currency || currencyFallback;
  const totalPrice = (cart.total_price || 0) / 100;
  const originalTotal =
    (cart.original_total_price ?? cart.total_price ?? 0) / 100;
  const discountAmount = (cart.total_discount || 0) / 100;

  // DEBUG: Log if we're getting zero totals but have items
  if (cart.items.length > 0 && totalPrice === 0 && originalTotal === 0) {

  }
  const itemCount = cart.items.reduce(
    (sum, item) => sum + (item.quantity || 0),
    0,
  );

  // Extract discount information (matching React app logic)
  let discountCode = "";
  let discountName = "";
  let discountType = "";
  let discountValue = "";

  // First check cart level discounts
  const cartDiscountApplications = cart.cart_level_discount_applications || [];
  if (cartDiscountApplications.length > 0) {
    const firstDiscount = cartDiscountApplications[0];
    discountName = firstDiscount.title || "";
    discountCode = firstDiscount.title || "";
    discountType = firstDiscount.value_type || "";
    discountValue = firstDiscount.value || "";
  } else {
    // If no cart level discounts, check line level discounts
    for (const item of cart.items || []) {
      if (
        item.line_level_discount_allocations &&
        item.line_level_discount_allocations.length > 0
      ) {
        const discount =
          item.line_level_discount_allocations[0].discount_application;
        discountName = discount.title || "";
        discountCode = discount.title || "";
        discountType = discount.value_type || "";
        discountValue = discount.value || "";
        break; // Use first discount found
      }
    }
  }

  // Fallback to discount_codes if no discount application found
  if (!discountCode && cart.discount_codes && cart.discount_codes.length > 0) {
    discountCode = cart.discount_codes[0].code || "";
    discountName = cart.discount_codes[0].code || "";
  }

  const items = cart.items.map((item, index) => ({
    id: item.id || item.key || index,
    title: item.title,
    quantity: item.quantity || 0,
    variantTitle: item.variant_title || "",
    image: resolveCartItemImageUrl(item),
    finalPrice: (item.final_line_price ?? item.price ?? 0) / 100,
    originalPrice:
      (item.original_line_price ??
        item.original_price ??
        item.final_line_price ??
        0) / 100,
    discounts: item.discounts || [],
    sku: item.sku || "",
  }));

  // Calculate tax amount
  // Tax can be in cart.total_tax (in cents) or calculated from totals
  let taxAmount = 0;
  if (cart.total_tax !== undefined && cart.total_tax !== null && cart.total_tax > 0) {
    taxAmount = cart.total_tax / 100;
  } else {
    taxAmount = 0;
  }

  return {
    items,
    itemCount,
    total: totalPrice,
    originalTotal,
    discountAmount,
    hasDiscount: discountAmount > 0,
    currency,
    discountCode,
    discountName,
    discountType,
    discountValue,
    taxAmount,
  };
};

/**
 * Get country key by country code
 * Maps country calling codes to country keys
 * @param {string} code - Country calling code (e.g., '91' for India)
 * @returns {string} Country key (e.g., 'IN' for India)
 */
export const getCountryKeyByCode = (code) => {
  // Common country code mappings
  const countryCodeMap = {
    91: "IN", // India
    1: "US", // United States
    44: "GB", // United Kingdom
    86: "CN", // China
    81: "JP", // Japan
    49: "DE", // Germany
    33: "FR", // France
    39: "IT", // Italy
    34: "ES", // Spain
    61: "AU", // Australia
    971: "AE", // UAE
    966: "SA", // Saudi Arabia
    65: "SG", // Singapore
    60: "MY", // Malaysia
    62: "ID", // Indonesia
    84: "VN", // Vietnam
    66: "TH", // Thailand
    63: "PH", // Philippines
    92: "PK", // Pakistan
    94: "LK", // Sri Lanka
    977: "NP", // Nepal
  };

  // Remove + prefix if present
  const cleanCode = code.replace(/^\+/, "");

  return countryCodeMap[cleanCode] || "IN"; // Default to India
};

/**
 * Check image aspect ratio (square vs wide)
 * React equivalent: otpUtils.js → checkImageAspectRatio()
 * @param {string} url - Image URL
 * @returns {Promise<string>} "Wide image" or "Square image"
 */
export const checkImageAspectRatio = (url) => {
  return new Promise((resolve, reject) => {
    if (typeof window === "undefined") {
      reject(new Error("Window not available"));
      return;
    }

    const img = new Image();
    img.onload = () => {
      const aspectRatio = img.width / img.height;
      if (aspectRatio > 1.5) {
        resolve("Wide image");
      } else {
        resolve("Square image");
      }
    };
    img.onerror = (error) => {

      reject(error);
    };
    img.src = url;
  });
};

/**
 * Get device type (Desktop/Mobile/Tablet)
 * React equivalent: otpUtils.js → getDeviceType()
 * Purpose: Detect device type from user agent
 * @returns {string} "Desktop" | "Mobile" | "Tablet"
 */
export const getDeviceType = () => {
  if (typeof window === "undefined" || typeof navigator === "undefined") {
    return "Desktop"; // Default fallback
  }

  const ua = navigator.userAgent;
  if (/tablet|ipad|playbook|silk/i.test(ua)) return "Tablet";
  if (/mobile|android|iphone|ipod|blackberry|iemobile|opera mini/i.test(ua))
    return "Mobile";
  return "Desktop";
};

export const simplifyCartItems = (cartItems) => {
  if (!Array.isArray(cartItems)) return [];

  return cartItems.map((item) => ({
    product_id: item.product_id?.toString(),
    variant_id: item.variant_id.toString(),
    title: item.title,
    quantity: item.quantity,
    price: Math.round(item.price / 100), // assuming price is in cents
    featured_image: item.featured_image?.url || null,
  }));
};

/**
 * Close modal and send message to parent window
 * This ensures the iframe is properly hidden before redirecting
 * @param {Function} closeModalAction - The closeModal action from buttonManager
 * @param {boolean} isCompletion - true if completing flow, false if manual close
 */
export const closeModalAndNotifyParent = (
  closeModalAction,
  isCompletion = false,
) => {
  // Close modal in Svelte store
  if (closeModalAction) {
    closeModalAction();
  }

  // ⚡ CRITICAL: Reset order summary flag on close to ensure fresh state on return
  try {
    import("../services/sessionService.js")
      .then((sessionService) => {
        sessionService.resetOrderSummaryComplete();
        sessionService.resetCartRevertIsComplete();
        sessionService.setSessionValue("partial_payment_cart_results", null);
        sessionService.removeSessionValue("partial_payment_no_eligible_rules");
      })
      .catch((err) => {

      });
  } catch (e) {
    // ignore
  }

  // Send message to parent window to trigger Liquid file's closeModal()
  // This is critical - the Liquid file's closeModal() actually hides the iframe
  try {
    if (typeof window.parent !== "undefined" && window.parent.postMessage) {
      postToParent("codk-close-modal");
    } else {

    }
  } catch (error) {

  }
};

/**
 * Get value from localStorage
 * React equivalent: otpUtils.js → getLocalValue()
 * @param {string} key - Storage key
 * @returns {any} Stored value or null
 */
export const getLocalValue = (key) => {
  if (typeof window === "undefined" || typeof localStorage === "undefined") {
    return null;
  }

  try {
    // Check parent window's localStorage first (for iframe context)
    if (
      window.parent &&
      window.parent !== window &&
      window.parent.localStorage
    ) {
      try {
        const parentValue = window.parent.localStorage.getItem(key);
        if (parentValue !== null) {
          try {
            return JSON.parse(parentValue);
          } catch {
            return parentValue;
          }
        }
      } catch (error) {}
    }

    // Fallback to iframe localStorage
    const jsonString = localStorage.getItem(key);
    if (!jsonString) {
      return null;
    }
    try {
      return JSON.parse(jsonString);
    } catch {
      return jsonString;
    }
  } catch (error) {

    return null;
  }
};

/**
 * Set value in localStorage
 * React equivalent: otpUtils.js → setLocalValue()
 * @param {string} key - Storage key
 * @param {any} value - Value to store (will be JSON stringified)
 */
export const setLocalValue = (key, value) => {
  if (typeof window === "undefined" || typeof localStorage === "undefined") {
    return;
  }

  try {
    const jsonString = JSON.stringify(value);

    // Save to parent window's localStorage (for iframe context)
    if (
      window.parent &&
      window.parent !== window &&
      window.parent.localStorage
    ) {
      try {
        window.parent.localStorage.setItem(key, jsonString);
      } catch (error) {}
    }

    // Also save to iframe localStorage
    localStorage.setItem(key, jsonString);
  } catch (error) {

  }
};

export const REDIRECT_IN_PROGRESS_KEY = "codk-redirect-in-progress";
export const REDIRECT_IN_PROGRESS_TTL_MS = 1500; // 1.5 sec

export const setRedirectInProgress = () => {
  setLocalValue(REDIRECT_IN_PROGRESS_KEY, Date.now());
};

export const clearRedirectInProgress = () => {
  removeLocalValue(REDIRECT_IN_PROGRESS_KEY);
};

export const isRedirectInProgress = (ttlMs = REDIRECT_IN_PROGRESS_TTL_MS) => {
  const raw = getLocalValue(REDIRECT_IN_PROGRESS_KEY);
  const ts = typeof raw === "number" ? raw : Number(raw);
  if (!ts || Number.isNaN(ts)) return false;
  return Date.now() - ts < ttlMs;
};

/**
 * Redirect the top window to checkout while leaving the widget mounted.
 *
 * The old flow called closeModal() (which unmounts the modal) right before
 * navigating, so the iframe blanked out until the top page unloaded. Callers
 * now keep the existing "processing" screen (PaymentProcessingContent —
 * "Redirecting to checkout…") visible; this just navigates and, as a fallback,
 * destroys the iframe after a delay in case the navigation is blocked/slow
 * (normally the page unloads first and this never runs).
 *
 * @param {string} url - target URL (default "/checkout")
 * @param {{ delayMs?: number }} [opts] - fallback destroy delay (default 3000ms)
 */
export const redirectToCheckout = (url = "/checkout", { delayMs = 3000 } = {}) => {
  if (typeof window === "undefined") return;

  setRedirectInProgress();

  // Fallback: if navigation hasn't unloaded the page yet, close the iframe.
  setTimeout(() => {
    import("../utilities/otpUtils.js")
      .then(({ notifyParentToDestroyIframe }) => notifyParentToDestroyIframe())
      .catch(() => {});
  }, delayMs);

  (window.top || window).location.href = url;
};

/**
 * Remove value from localStorage
 * React equivalent: otpUtils.js → removeLocalValue()
 * @param {string} key - Storage key
 */
export const removeLocalValue = (key) => {
  if (typeof window === "undefined" || typeof localStorage === "undefined") {
    return;
  }

  try {
    // Remove from parent window's localStorage
    if (
      window.parent &&
      window.parent !== window &&
      window.parent.localStorage
    ) {
      try {
        window.parent.localStorage.removeItem(key);
      } catch (error) {}
    }

    // Remove from iframe localStorage
    localStorage.removeItem(key);
  } catch (error) {

  }
};

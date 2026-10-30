//@ts-nocheck

import { actions, appStore } from "../stores/buttonManager.js";
import { otpStoreActions } from "../stores/otpStore.js";
import { get } from "svelte/store";
import { cartFetch } from "./shopifyCartApi.js";
import { getSessionValue } from "../services/sessionService.js";
import { QUICK_VIEW_CONTAINERS } from "./cartDrawerManager.js";

const logPrefix = "[CartHydration]";
let isHandlingBuyNow = false;
const BUY_NOW_FLAG_KEY = "cod_king_isBuyNow";
const BUY_NOW_PROCESSING_VALUE = "processing";

const extractAndStoreBuyNowVariantAndQuantity = () => {
  const doc =
    typeof window !== "undefined" ? window.parent?.document : document;
  if (!doc) return { variantId: null, quantity: 1 };
  let variantId = null;
  let variantIdFromCartForm = null;
  let quantity = 1;
  try {
   const addToCartForms = doc.querySelectorAll('form[action="/cart/add"]');
   for (const form of addToCartForms) {
  const idInput = form.querySelector(
    'input[name="id"]'
  );
  const isProductForm = form?.getAttribute('id')?.startsWith('product-form') || form?.classList?.contains('product-form');
  const openQuickDrawer = form.closest(QUICK_VIEW_CONTAINERS.join(","));
  if (idInput && isProductForm && openQuickDrawer) {
    // @ts-ignore
    variantIdFromCartForm = idInput?.value || null;
    break;
  }
  }
    const acceleratedCheckout = doc.querySelector(
      "shopify-accelerated-checkout",
    );

    if (acceleratedCheckout) {
      const variantParams = acceleratedCheckout.getAttribute("variant-params");
      if (variantParams) {
        try {
          const decodedParams = variantParams.replace(/&quot;/g, '"');
          const variantArray = JSON.parse(decodedParams);
          if (variantArray && variantArray.length > 0 && variantArray[0].id) {
            variantId = parseInt(variantArray[0].id, 10);
          }
        } catch (e) {}
      } else {
      }
    } else {
    }
    if (!variantId) {
      const urlParams = new URLSearchParams(
        window.parent?.location.search || window.location.search,
      );
      const variantIdFromURL = urlParams.get("variant");
      if (variantIdFromURL) {
        variantId = parseInt(variantIdFromURL, 10);
      }
    }
    if (!variantId) {
      const variantInput =
        /** @type {HTMLInputElement | HTMLSelectElement | null} */ (
          doc.querySelector('input[name="id"], select[name="id"]')
        );
      if (variantInput && variantInput.value) {
        variantId = parseInt(variantInput.value, 10);
      }
    }
    if (!variantId) {
      const variantInput = /** @type {HTMLInputElement | null} */ (
        doc.querySelector("input.product-variant-id")
      );
      if (variantInput && variantInput.value) {
        variantId = parseInt(variantInput.value, 10);
      }
    }
    const quantityInput =
      /** @type {HTMLInputElement | HTMLSelectElement | null} */ (
        doc.querySelector(
          'quantity-selector input[name="quantity"], quantity-input input[name="quantity"], form[action*="/cart/add"] [name="quantity"], input[name="quantity"], select[name="quantity"]',
        )
      );
    if (quantityInput && quantityInput.value) {
      const n = parseInt(quantityInput.value, 10);
      quantity = n > 0 ? n : 1;
    }
  } catch (e) {}
  if (variantIdFromCartForm) {
    const parsedFromForm = parseInt(variantIdFromCartForm, 10);
    if (!isNaN(parsedFromForm) && parsedFromForm !== variantId) {
      variantId = parsedFromForm;
    }
  }
  return { variantId, quantity };
};

export const getVariantIdQuantityAndProperties = () => {
  const settings = getSessionValue("settingSession");
  // NaN when unset, which fails every comparison below and falls through to
  // auto-detection — same as the previous raw read.
  const variantPickCondition = Number(settings?.variantPickCondition);
  const doc = typeof window !== "undefined" ? window.parent?.document : null;
  if (!doc) {
    return { variantID: null, quantity: 1, properties: {} };
  }

  const getQuantity = () => {
    const quantityInput =
      /** @type {HTMLInputElement | null} */ (
        doc.querySelector('quantity-selector input[name="quantity"]')
      ) ||
      /** @type {HTMLInputElement | null} */ (
        doc.querySelector('quantity-input input[name="quantity"]')
      ) ||
      /** @type {HTMLInputElement | null} */ (
        doc.querySelector('form[action*="/cart/add"] [name="quantity"]')
      ) ||
      /** @type {HTMLInputElement | null} */ (
        doc.querySelector('[name="quantity"]')
      );
    const forms = doc.querySelectorAll('form[action*="/cart/add"]');
    const productForm =
      quantityInput?.form ||
      [...forms].find((form) =>
        form.getAttribute("id")?.startsWith("product-form"),
      );

    let pFQuantity = null;
    if (productForm) {
      const fd = new FormData(productForm);
      const raw = parseInt(fd.get("quantity"), 10);
      if (!isNaN(raw) && raw > 0) {
        pFQuantity = raw;
      }
    }

    if (quantityInput?.value) {
      const parsed = parseInt(quantityInput.value, 10);
      if (!isNaN(parsed) && parsed > 0) {
        if (pFQuantity && pFQuantity !== parsed) {
          return pFQuantity;
        }
        return parsed;
      }
    }

    return pFQuantity || 1;
  };

  const getProperties = () => {
    const properties = {};

    const propertyInputs = doc.querySelectorAll(
      'input[name^="properties["], textarea[name^="properties["], select[name^="properties["]',
    );

    propertyInputs.forEach((inputEl) => {
      const input =
        /** @type {HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement} */ (
          inputEl
        );
      const name = input.name || "";
      const match = name.match(/properties\[([^\]]+)\]/);
      const value = input.value?.trim?.() ?? "";
      if (match && value) {
        properties[match[1]] = value;
      }
    });

    const dataPropertyInputs = doc.querySelectorAll("[data-property]");
    dataPropertyInputs.forEach((inputEl) => {
      const input =
        /** @type {HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement} */ (
          inputEl
        );
      const propertyName = input.getAttribute("data-property");
      const value = input.value?.trim?.() ?? "";
      if (propertyName && value) {
        properties[propertyName] = value;
      }
    });

    const form = /** @type {HTMLFormElement | null} */ (
      doc.querySelector('form[action*="/cart/add"]')
    );
    if (form) {
      const formData = new FormData(form);
      for (const [key, value] of formData.entries()) {
        if (
          key.startsWith("properties[") &&
          typeof value === "string" &&
          value.trim()
        ) {
          const match = key.match(/properties\[([^\]]+)\]/);
          if (match) {
            properties[match[1]] = value.trim();
          }
        }
      }
    }

    return properties;
  };

  const getFromURL = () => {
    const urlParams = new URLSearchParams(window.parent.location.search);
    const variantIdFromURL = urlParams.get("variant");
    if (variantIdFromURL) {
      const variantId = parseInt(variantIdFromURL, 10);

      return {
        variantID: variantId,
        quantity: getQuantity(),
        properties: getProperties(),
      };
    }

    return null;
  };

  const getFromShopifyAnalytics = () => {
    try {
      const metaVariantId =
        window?.parent?.meta.product.variants[0].id ||
        window?.meta.product.variants[0].id;
      if (metaVariantId) {
        const variantId = parseInt(String(metaVariantId), 10);

        return {
          variantID: variantId,
          quantity: getQuantity(),
          properties: getProperties(),
        };
      }
    } catch (error) {}
    return null;
  };

  const getFromInputNameId = () => {
    const variantIdInput = /** @type {HTMLInputElement | null} */ (
      doc.querySelector('[name="id"]')
    );
    if (variantIdInput?.value) {
      const variantId = parseInt(variantIdInput.value, 10);

      return {
        variantID: variantId,
        quantity: getQuantity(),
        properties: getProperties(),
      };
    }

    return null;
  };

  const getFromAcceleratedCheckout = () => {
    const acceleratedCheckout = doc.querySelector(
      "shopify-accelerated-checkout",
    );
    if (acceleratedCheckout) {
      const variantParams = acceleratedCheckout.getAttribute("variant-params");
      if (variantParams) {
        try {
          const variantArray = JSON.parse(variantParams);
          if (Array.isArray(variantArray) && variantArray[0]?.id) {
            const variantId = parseInt(variantArray[0].id, 10);

            return {
              variantID: variantId,
              quantity: getQuantity(),
              properties: getProperties(),
            };
          }
        } catch (error) {}
      } else {
      }
    } else {
    }
    return null;
  };

  const getFromSelectNameId = () => {
    const variantSelect = /** @type {HTMLSelectElement | null} */ (
      doc.querySelector('select[name="id"]')
    );
    if (variantSelect?.value) {
      const variantId = parseInt(variantSelect.value, 10);

      return {
        variantID: variantId,
        quantity: getQuantity(),
        properties: getProperties(),
      };
    }

    return null;
  };

  const getFromBuyNowExtraction = () => {
    try {
      const { variantId, quantity: extractedQuantity } =
        extractAndStoreBuyNowVariantAndQuantity();

      if (variantId) {
        return {
          variantID: variantId,
          quantity: extractedQuantity,
          properties: getProperties(),
        };
      }
    } catch (e) {}
    return null;
  };

  const getFromLiquidProductData = () => {
    try {
      const liquidData =
        window.parent?.codkProductDataFromLiquid ||
        window.codkProductDataFromLiquid;

      if (liquidData && liquidData.selectedVariantId) {
        const variantId = parseInt(String(liquidData.selectedVariantId), 10);
        if (!isNaN(variantId) && variantId > 0) {
          return {
            variantID: variantId,
            quantity: getQuantity(),
            properties: getProperties(),
          };
        }
      }
    } catch (e) {}
    return null;
  };

  // Themes on Shopify's ref="" convention (Horizon and its derivatives) keep the
  // live selection in the product form's hidden id input, marked ref="variantId".
  // Bundle/tier widgets rewrite that input on every click and leave the URL,
  // meta.product and shopify-accelerated-checkout untouched, so it is the only
  // node that tracks what the customer actually picked — and it is exactly what
  // the theme's own Add to cart submits.
  const getFromProductFormRef = () => {
    const inForms = [
      ...doc.querySelectorAll('form[action*="/cart/add"] [ref="variantId"]'),
    ];
    const candidates = (
      inForms.length ? inForms : [...doc.querySelectorAll('[ref="variantId"]')]
    ).filter((el) => {
      const parsed = parseInt(/** @type {HTMLInputElement} */ (el).value, 10);
      return !isNaN(parsed) && parsed > 0;
    });
    if (!candidates.length) return null;

    // A hidden input is never itself visible, so judge its form instead — that
    // skips the hidden quick-add forms themes render for related products.
    const formVisible = (el) => {
      const form = el.closest("form");
      if (!form) return false;
      return form.offsetParent !== null || form.getClientRects().length > 0;
    };
    // Layout-free hidden check, so a theme that hides quick-add markup without a
    // layout difference (and any non-browser caller) still ranks correctly.
    const explicitlyHidden = (el) => {
      let node = el.closest("form") || el;
      while (node && node.nodeType === 1) {
        if (
          node.hasAttribute("hidden") ||
          node.getAttribute("aria-hidden") === "true" ||
          node.style?.display === "none" ||
          node.style?.visibility === "hidden"
        ) {
          return true;
        }
        node = node.parentElement;
      }
      return false;
    };
    const isAddToCartForm = (el) =>
      el.closest("form")?.getAttribute("data-type") === "add-to-cart-form";

    const pick =
      candidates.find(
        (el) => formVisible(el) && isAddToCartForm(el) && !explicitlyHidden(el),
      ) ||
      candidates.find((el) => formVisible(el) && !explicitlyHidden(el)) ||
      candidates.find((el) => !explicitlyHidden(el) && isAddToCartForm(el)) ||
      candidates.find((el) => !explicitlyHidden(el)) ||
      candidates[0];

    return {
      variantID: parseInt(/** @type {HTMLInputElement} */ (pick).value, 10),
      quantity: getQuantity(),
      properties: getProperties(),
    };
  };

  const strategies = {
    1: getFromLiquidProductData,
    2: getFromShopifyAnalytics,
    3: getFromInputNameId,
    4: getFromAcceleratedCheckout,
    5: getFromSelectNameId,
    6: getFromBuyNowExtraction,
    7: getFromURL,
    8: getFromProductFormRef,
  };
  const storeVariantStrategy = {
    "1b86a7-cc.myshopify.com": 3,
    "mavani-fashion.myshopify.com": 3,
  };

  const currentShop =
    window.parent?.Shopify?.shop || window.parent.location.hostname;
  const preferredMethod = storeVariantStrategy[currentShop] || null;

  let selectedStrategy = null;
  let result = null;
  // ?variant= reflects page load, not a bundle/tier click, so condition 8 opts
  // out of the URL shortcut — it would otherwise win before the strategy runs.
  // Every other condition keeps its existing precedence.
  if (variantPickCondition !== 8) {
    const urlResult = getFromURL();
    if (urlResult) return urlResult;
  }
  if (variantPickCondition >= 1 && variantPickCondition <= 8) {
    selectedStrategy = variantPickCondition;
    result = strategies[variantPickCondition]?.();
    if (!result) {
    }
  } else {
    if (preferredMethod && strategies[preferredMethod]) {
      selectedStrategy = preferredMethod;
      result = strategies[preferredMethod]();
      if (!result) {
      }
    }
    if (!result) {
      for (const method of [1, 2, 3, 4, 5, 6, 7, 8]) {
        if (method === preferredMethod) continue;
        const strategyResult = strategies[method]?.();
        if (strategyResult) {
          selectedStrategy = method;
          result = strategyResult;

          break;
        }
      }
    }
  }

  if (result) {
    return result;
  }

  return { variantID: null, quantity: 1, properties: {} };
};

/**
 * Detect whether a quick-view / quick-add container is currently open on the
 * page. Mirrors the container selection used by getOptimisticCartFromDOM so the
 * two stay consistent. Themes only inject the /cart/add form once the quick view
 * is actually opened, so requiring the form (or visibility) avoids false
 * positives from hidden related-product quick-add templates on a PDP.
 */
export const isQuickViewOpen = () => {
  try {
    const doc =
      typeof window !== "undefined" ? window.parent?.document : document;
    if (!doc) return false;
    const isVisible = (el) =>
      !!el && (el.offsetParent !== null || el.getClientRects().length > 0);
    const qvContainers = [
      ...doc.querySelectorAll(QUICK_VIEW_CONTAINERS.join(",")),
    ];
    const quickView =
      qvContainers.find(
        (el) => isVisible(el) && el.querySelector('form[action*="/cart/add"]'),
      ) ||
      qvContainers.find((el) => el.querySelector('form[action*="/cart/add"]')) ||
      qvContainers.find(isVisible) ||
      null;
    return !!quickView;
  } catch {
    return false;
  }
};

/**
 * Scan `<script type="application/json">` blocks within a scope for a Shopify
 * product object (has a `variants` array). Returns { product, variant } where
 * variant matches variantID (or the product's first variant). This is the most
 * reliable source in quick-view/quick-add, where CSS selectors and window.meta
 * point at the wrong (underlying page) product.
 */
const findProductJsonForVariant = (scope, variantID) => {
  try {
    const scripts = scope.querySelectorAll('script[type="application/json"]');
    for (const s of scripts) {
      let data;
      try {
        data = JSON.parse(s.textContent || "null");
      } catch {
        continue;
      }
      // Themes expose this in three shapes:
      //   { variants: [...] }            (product JSON)
      //   { product: { variants: [...] }}
      //   [ {id,title,price,...}, ... ]  (Dawn <variant-radios>: a bare array)
      let productObj = null;
      let variants = null;
      if (data && Array.isArray(data.variants)) {
        productObj = data;
        variants = data.variants;
      } else if (data && data.product && Array.isArray(data.product.variants)) {
        productObj = data.product;
        variants = data.product.variants;
      } else if (Array.isArray(data) && data[0] && data[0].id != null) {
        // Bare variant array — no product-level fields; title derived from variant.name later.
        productObj = null;
        variants = data;
      }
      if (!variants || !variants.length) continue;
      const variant =
        (variantID &&
          variants.find((v) => String(v.id) === String(variantID))) ||
        null;
      if (variant || !variantID) {
        return { product: productObj, variant: variant || variants[0] };
      }
    }
  } catch {}
  return { product: null, variant: null };
};

/**
 * Build an OPTIMISTIC cart object by scraping the PDP / quick-view DOM so the
 * order summary can paint instantly, before the real /cart/add.js + /cart.js
 * round-trips finish. Prices are in minor units (cents) to match the shape that
 * OrderSummaryCard / otpStore expect. Reconciled with the authoritative cart in
 * fetchProductDetails() once it returns.
 *
 * Source priority (per product data): embedded product JSON -> meta.product ->
 * liquid -> DOM. Returns null when we can't scrape enough (falls back to skeleton).
 */
export const getOptimisticCartFromDOM = () => {
  try {
    const doc =
      typeof window !== "undefined" ? window.parent?.document : document;
    if (!doc) return null;

    const { variantID, quantity, properties } =
      getVariantIdQuantityAndProperties();
    const qty = quantity > 0 ? quantity : 1;

    // --- Scope: when a quick-view/quick-add is open, scrape from INSIDE it so we
    // don't pick up the underlying collection/PDP page's product. On a PDP the
    // scope is the whole document. ---
    const qvSelector = QUICK_VIEW_CONTAINERS.join(",");
    const isVisible = (el) =>
      !!el && (el.offsetParent !== null || el.getClientRects().length > 0);
    const qvContainers = [...doc.querySelectorAll(qvSelector)];
    const quickView =
      qvContainers.find(
        (el) => isVisible(el) && el.querySelector('form[action*="/cart/add"]'),
      ) ||
      qvContainers.find((el) => el.querySelector('form[action*="/cart/add"]')) ||
      qvContainers.find(isVisible) ||
      null;
    const scope = quickView || doc;
    const inQuickView = !!quickView;

    const metaProduct =
      window.parent?.meta?.product || window.meta?.product || null;
    const liquid =
      window.parent?.codkProductDataFromLiquid ||
      window.codkProductDataFromLiquid ||
      null;

    // In quick view, meta.product / liquid reflect the underlying page's product,
    // not the quick-viewed one — only trust a meta variant whose id matches the
    // scraped variant, and prefer the scoped DOM for everything else.
    let metaVariant = null;
    if (metaProduct && Array.isArray(metaProduct.variants)) {
      const matched =
        variantID &&
        metaProduct.variants.find((v) => String(v.id) === String(variantID));
      metaVariant = matched || (inQuickView ? null : metaProduct.variants[0]) || null;
    }
    const trustPageData = !inQuickView; // meta/liquid are reliable only outside quick view

    // --- Embedded product JSON (most reliable, esp. in quick view) ---
    // Look inside the quick-view scope first, then the whole document.
    let { product: jsonProduct, variant: jsonVariant } =
      findProductJsonForVariant(scope, variantID);
    if (!jsonProduct && scope !== doc) {
      ({ product: jsonProduct, variant: jsonVariant } =
        findProductJsonForVariant(doc, variantID));
    }
    // Only trust doc-level JSON outside quick view (in quick view it may be the page product).
    if (jsonProduct && inQuickView && scope === doc) {
      jsonProduct = null;
      jsonVariant = null;
    }

    // --- Price (cents) ---
    let priceCents = null;
    if (jsonVariant && typeof jsonVariant.price === "number") {
      priceCents = jsonVariant.price; // Shopify product JSON prices are in cents
    } else if (jsonProduct && typeof jsonProduct.price === "number") {
      priceCents = jsonProduct.price;
    } else if (metaVariant && typeof metaVariant.price === "number") {
      priceCents = metaVariant.price; // Shopify meta variant price is already in cents
    } else if (trustPageData && liquid && liquid.price != null) {
      const p = Number(liquid.price);
      // Liquid may expose price in cents (Shopify default) or in currency units
      if (!isNaN(p)) priceCents = p >= 1000 ? Math.round(p) : Math.round(p * 100);
    }
    if (priceCents == null) {
      const priceEl = scope.querySelector(
        "[data-product-price], .price-item--sale, .price-item--regular, .price__regular .price-item, .product__price, .price__current, .price, [class*='price']",
      );
      const raw = priceEl?.getAttribute?.("content") || priceEl?.textContent || "";
      const num = parseFloat(String(raw).replace(/[^0-9.]/g, ""));
      if (!isNaN(num) && num > 0) priceCents = Math.round(num * 100);
    }

    // meta/json variant.name is "Product Title - Variant"; strip the variant suffix.
    const titleFromVariantName = (v) => {
      if (!v?.name) return "";
      const pub = v.public_title;
      return pub && v.name.endsWith(` - ${pub}`)
        ? v.name.slice(0, -(` - ${pub}`.length))
        : v.name;
    };

    // --- Title ---
    let title = jsonProduct?.title || titleFromVariantName(jsonVariant) || "";
    if (!title) title = (trustPageData && (liquid?.title || liquid?.productTitle)) || "";
    if (!title) title = titleFromVariantName(metaVariant);
    if (!title) {
      const titleEl = scope.querySelector(
        "h1.product__title, .product__title, .product-single__title, .product-title, .card__heading, .card__heading a, [class*='product-title'], [class*='product__title'], h1, h2",
      );
      title = titleEl?.textContent?.trim() || "";
    }

    // --- Image ---
    const jsonImage =
      jsonVariant?.featured_image?.src ||
      jsonProduct?.featured_image ||
      (Array.isArray(jsonProduct?.images) ? jsonProduct.images[0] : null) ||
      (Array.isArray(jsonProduct?.media)
        ? jsonProduct.media.find((m) => m?.src || m?.preview_image?.src)?.src ||
          jsonProduct.media[0]?.preview_image?.src
        : null) ||
      null;
    let image =
      jsonImage ||
      (trustPageData && (liquid?.image || liquid?.featuredImage)) ||
      scope
        .querySelector(
          ".product__media img, .product-single__photo img, .product-gallery img, .card__media img, [class*='product'] img, img",
        )
        ?.getAttribute?.("src") ||
      (trustPageData
        ? doc.querySelector('meta[property="og:image"]')?.getAttribute?.("content")
        : "") ||
      "";
    if (image && image.startsWith("//")) image = `https:${image}`;

    // --- Product ID (needed for product/collection rule filtering) ---
    // Prefer an id scoped to the quick-view/product form; fall back to page meta
    // only when NOT in quick view (page meta would be the wrong product there).
    let productId = null;
    if (jsonProduct?.id != null && /^\d+$/.test(String(jsonProduct.id)))
      productId = String(jsonProduct.id);
    if (!productId) {
      const pidEl = scope.querySelector(
        '[data-product-id], input[name="product-id"], input[name="product_id"]',
      );
      const pidAttr =
        pidEl?.getAttribute?.("data-product-id") || pidEl?.value || null;
      if (pidAttr && /^\d+$/.test(String(pidAttr))) productId = String(pidAttr);
    }
    if (!productId && trustPageData) {
      if (metaProduct?.id != null) productId = String(metaProduct.id);
      else if (liquid?.productId != null) productId = String(liquid.productId);
      else if (liquid?.id != null) productId = String(liquid.id);
    }

    // --- Variant title (size/color). Prefer product JSON, then meta, then the
    // selected option in the quick-view/product form, then scraped properties. ---
    let variantTitle =
      jsonVariant?.public_title || jsonVariant?.title || metaVariant?.public_title || "";
    if (!variantTitle) {
      const selectedOpt = scope.querySelector(
        'input[type="radio"][name^="options" i]:checked, input[type="radio"][name*="option" i]:checked',
      );
      const optSelect = scope.querySelector('select[name^="options" i], select[name*="option" i]');
      variantTitle =
        selectedOpt?.value ||
        optSelect?.value ||
        (properties && Object.values(properties).filter(Boolean).join(" • ")) ||
        "";
    }

    // Not enough to be useful — let the skeleton show instead.
    if (!variantID && !title && priceCents == null) return null;

    const linePrice = (priceCents || 0) * qty;
    const currency =
      window.parent?.Shopify?.currency?.active ||
      window.Shopify?.currency?.active ||
      "INR";

    return {
      __optimistic: true,
      token: null,
      currency,
      item_count: qty,
      total_price: linePrice,
      original_total_price: linePrice,
      total_discount: 0,
      cart_level_discount_applications: [],
      items: [
        {
          variant_id: variantID,
          product_id: productId,
          quantity: qty,
          title: title || "Your item",
          price: priceCents || 0,
          line_price: linePrice,
          final_line_price: linePrice,
          original_line_price: linePrice,
          discounted_price: linePrice,
          featured_image: image ? { url: image } : null,
          image: image || null,
          variant_title: variantTitle,
          line_level_discount_allocations: [],
          properties: properties || {},
        },
      ],
    };
  } catch (_e) {
    return null;
  }
};

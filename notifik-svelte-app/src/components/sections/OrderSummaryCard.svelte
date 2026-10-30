<script>
  /**
   * OrderSummaryCard - Compact order summary widget matching React DesktopOrderSummary.js
   * Displays compact order summary with sliding details panel
   * @component
   */
  import { onMount } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { get } from "svelte/store";
  import { saveDiscountSummaryToSession } from "../../utils/partialPaymentUtils.js";
  import { shopifyAddToCartForBuyNow } from "../../services/cartService.js";
  import { getOptimisticCartFromDOM, isQuickViewOpen } from "../../utils/cartHydration.js";
  import { cartRevertService } from "../../services/cartRevertService.js";
  import { getSessionValue, isOptimizedBuyNowEnabled } from "../../services/sessionService.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import { appStore } from "../../stores/buttonManager.js";
  import OrderSummarySkeleton from "../shared/OrderSummarySkeleton.svelte";
  import Card from "../ui/Card.svelte";
  import Sheet from "../ui/Sheet.svelte";
  import OrderSummaryDetails from "./OrderSummaryDetails.svelte";
  import { isGiftLine, GIFT_ICON_URL, FREE_GIFT_PROPERTY } from "../../services/freeGiftService.js";
  import "../../styles/components/sections/OrderSummaryCard.css";
  import { IS_BUY_NOW_BUTTON } from "../../services/otpService.js";
  import { callPartialDummyVariantId } from "../../services/callPartialDummyVariantId.js";
  import { decodeHtmlEntities, isTaxIncludedWithProductAny } from "../../utils/helpers.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  const OFFER_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/automatic_coupon.svg?v=1784796941";
  const CELEBRATION_EMOJI =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/CelebrationEmoji.png?v=1784797043";

  // Props
  let { onExpand = null, showDisplay = false } = $props();

  // State
  let isSliderOpen = $state(false);
  let isExpanded = $state(false);

  // Subscribe to otpStore
  let otpState = $derived($otpStore);
  let currentCartData = $derived(otpState.currentCartData);
  let sheetBannerColor = $derived.by(() => {
    const s = /** @type {any} */ (otpState?.settings || {});
    return s.promoBannerColor || s.promo_banner_color || "";
  });
  // Same text colour as the promo banner, so a light brand colour stays readable.
  let sheetBannerTextColor = $derived.by(() => {
    const s = /** @type {any} */ (otpState?.settings || {});
    return s.promoTextColor || s.promo_text_color || "";
  });
  let isPrefilledAddressEnabled = $derived(
    (() => {
      const a = otpState?.settings?.isPrefilledAddressEnabled;
      const b = otpState?.settings?.is_prefilled_address_enabled;
      return a === true || String(a) === "true" || b === true || String(b) === "true";
    })(),
  );
  let taxInclusiveMerchant = $derived(
    isTaxIncludedWithProductAny(
      otpState?.settings,
      $settingsStore,
      get(appStore)?.settings,
    ),
  );
  // Opt-in (default off), mirroring PaymentOptionsSection. No address needed —
  // the charge is merchant-set per option, not calculated by Shopify.
  let showShippingInfo = $derived.by(() => {
    const sources = [otpState?.settings, $settingsStore];
    return sources.some((s) => {
      const v =
        s?.includeShippingInPaymentOptions ??
        s?.include_shipping_in_payment_options;
      return v === true || String(v) === "true";
    });
  });
  // Mirrors the charge on the selected payment option, published by
  // PaymentOptionsSection so both surfaces always agree.
  let shippingAmount = $derived(
    showShippingInfo ? Math.max(0, Number(otpState?.optionShippingAmount) || 0) : 0,
  );
  let shippingKnown = $derived(showShippingInfo && shippingAmount > 0);
  // If cod_form_enabled is ON, show tax unless prices already include tax.
  let showTax = $derived(
    !taxInclusiveMerchant &&
      (otpState?.settings?.cod_form_enabled === true ||
        otpState?.settings?.cod_form_enabled === "true" ||
        otpState?.settings?.codFormEnabled === true ||
        otpState?.settings?.codFormEnabled === "true" ||
        (isPrefilledAddressEnabled &&
          otpState?.settings?.preV2ShowTaxInfo === true)),
  );

  // Use currentCartData from OTP store instead of transformed cart from CartStore
  const cartState = $derived(currentCartData || {});

  // Map items to compact product data for UI (variant, pricing for details panel)
  // Note: discounted_price might be line total, price is per-unit
  let productData = $derived(
    (cartState.items || []).map((item) => {
      const quantity = item.quantity || 1;
      let linePrice;
      if (typeof item.discounted_price === "number") {
        linePrice = item.discounted_price;
      } else if (item.final_line_price) {
        linePrice = item.final_line_price;
      } else if (item.line_price) {
        linePrice = item.line_price;
      } else {
        linePrice = (item.price || 0) * quantity;
      }
      const originalLine =
        item.original_line_price != null
          ? item.original_line_price
          : item.original_price != null
            ? (item.original_price || 0) * quantity
            : linePrice;
      // Variant: use variant_title or build from options (e.g. "Size M • Color Brown")
      let variantDisplay = item.variant_title || item.variantTitle || "";
      if (!variantDisplay && Array.isArray(item.options) && item.options.length > 0) {
        variantDisplay = item.options
          .filter(Boolean)
          .map((o) => (typeof o === "string" ? o : o?.value ?? o?.name ?? ""))
          .filter(Boolean)
          .join(" • ") || "";
      }
      if (variantDisplay && !/^variant:/i.test(variantDisplay.trim())) {
        variantDisplay = variantDisplay.trim();
      }
      variantDisplay = decodeHtmlEntities(variantDisplay);
      const decodedTitle = decodeHtmlEntities(item.title || "");

      // MRP line: compare-at price when the merchant set one, else the
      // pre-discount line price.
      const compareAt = Number(item.compare_at_price) || 0;
      const mrpLine = compareAt > 0 ? compareAt * quantity : originalLine;

      return {
        key: item.key,
        name: decodedTitle,
        title: decodedTitle,
        imageSrc: item?.featured_image?.url || item.image || "NA",
        quantity,
        price: linePrice / 100,
        finalPrice: linePrice / 100,
        originalPrice: mrpLine / 100,
        lineOriginalPrice: originalLine / 100,
        variant_title: variantDisplay || "",
        variantTitle: variantDisplay || "",
        isFreeGift: isGiftLine(item),
        rowKey: isGiftLine(item) ? `gift:${item.properties[FREE_GIFT_PROPERTY]}` : item.key,
      };
    }),
  );

  const hasFreeGift = $derived(productData.some((p) => p.isFreeGift));

  const totalQuantity = $derived(
    cartState.item_count ||
      productData.reduce((acc, p) => acc + (p.quantity || 0), 0),
  );
  const currencyCode = $derived(cartState.currency || "INR");

  // Use transformed cart totals directly (values are in minor units)
  const cartOriginalPrice = $derived((cartState.original_total_price || 0) / 100);
  // Subtotal at MRP: what the items list for before any strike-through saving.
  const originalPrice = $derived(
    productData.reduce((sum, p) => sum + (p.originalPrice || 0), 0) ||
      cartOriginalPrice,
  );
  const discountOnMrp = $derived(
    Math.max(0, Math.round((originalPrice - cartOriginalPrice) * 100) / 100),
  );
  const discountedPrice = $derived((cartState.total_price || 0) / 100);
  const discountAmount = $derived((cartState.total_discount || 0) / 100);
  const hasDiscount = $derived((cartState.total_discount || 0) > 0);
  const taxRate = $derived.by(() => {
    if (taxInclusiveMerchant) return 0;
    const taxData = otpState?.calculatedTaxData;
    if (!taxData || !taxData.total_tax || taxData.total_tax <= 0) return 0;
    const taxLines = taxData.tax_lines;
    if (taxLines?.length > 0) {
      const sum = taxLines.reduce((s, l) => s + (parseFloat(l.rate) || 0), 0);
      if (sum > 0) return sum;
    }
    const rawTax = taxData.total_tax > 10000 ? taxData.total_tax / 100 : taxData.total_tax;
    const rawTotal = (taxData.subtotal_price || 0) > 10000
      ? (taxData.subtotal_price || 0) / 100
      : (taxData.subtotal_price || 0);
    if (rawTax > 0 && rawTotal > 0) {
      return Math.round((rawTax / rawTotal) * 10000) / 10000;
    }
    return 0;
  });
  const taxAmount = $derived(
    showTax && taxRate > 0
      ? Math.floor(discountedPrice * taxRate * 100) / 100
      : 0,
  );
  // Total price including tax and shipping
  const totalWithTax = $derived(discountedPrice + taxAmount + shippingAmount);
  const firstCartDiscount = $derived(
    cartState.cart_level_discount_applications?.[0],
  );

  // Every applied discount listed individually with its own allocated amount
  // (cart-level + line-level), so multiple coupons don't collapse into one line.
  const appliedDiscounts = $derived.by(() => {
    const appliedCodes = new Set(
      (cartState.discount_codes || [])
        .filter((dc) => dc && dc.applicable !== false)
        .map((dc) => String(dc.code || "").trim().toLowerCase())
        .filter(Boolean),
    );
    const map = new Map();
    const add = (title, type, cents) => {
      const label = String(title || "").trim();
      if (!label) return;
      const isCode =
        type === "discount_code" || appliedCodes.has(label.toLowerCase());
      const key = `${isCode ? "code" : "auto"}:${label.toLowerCase()}`;
      const prev =
        map.get(key) || { label, isAutomatic: !isCode, amount: 0 };
      prev.amount += (Number(cents) || 0) / 100;
      map.set(key, prev);
    };
    for (const app of cartState.cart_level_discount_applications || []) {
      add(app.title, app.type, app.total_allocated_amount);
    }
    for (const item of cartState.items || []) {
      for (const alloc of item.line_level_discount_allocations || []) {
        const da = alloc.discount_application || {};
        add(da.title, da.type, alloc.amount);
      }
    }
    return [...map.values()]
      .filter((d) => d.amount > 0)
      .map((d) => ({ ...d, code: d.isAutomatic ? null : d.label }));
  });

  // Get discount name from session as fallback
  const sessionDiscount = $derived.by(() => {
    try {
      const summary = getSessionValue("codk_discount_summary", null);
      return summary?.discountName || summary?.discountTitle || "";
    } catch {
      return "";
    }
  });

  // Prioritize discount title/name, then code, then session, then empty string
  const discountTitle = $derived(
    firstCartDiscount?.title ||
      firstCartDiscount?.description ||
      cartState.discount_codes?.[0]?.code ||
      sessionDiscount ||
      "",
  );

  const fmtMoney = (v) => {
    const sym = currencyCode === "INR" ? "₹" : `${currencyCode} `;
    return `${sym}${(Number(v) || 0).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`;
  };

  const offerMessage = $derived.by(() => {
    const count = appliedDiscounts.length;
    if (count > 1)
      return `Multiple Offers Applied! You save ${fmtMoney(discountAmount)}!`;
    if (count === 1)
      return `${appliedDiscounts[0].label} Applied! You save ${fmtMoney(appliedDiscounts[0].amount)}!`;
    if (hasDiscount) {
      const t = (discountTitle || "").trim();
      return t
        ? `${t} Applied! You save ${fmtMoney(discountAmount)}!`
        : `You save ${fmtMoney(discountAmount)}!`;
    }
    return "";
  });

  const savedSoFar = $derived(Math.max(0, originalPrice - discountedPrice));

  let savingsSentinel = $state(null);
  let savingsStuck = $state(false);

  $effect(() => {
    const sentinel = savingsSentinel;
    if (!sentinel) return;

    const root = sentinel.closest(".screen-content");
    if (!root) return;

    const observer = new IntersectionObserver(
      (entries) => {
        savingsStuck = !entries[0]?.isIntersecting;
      },
      { root, threshold: 0 },
    );
    observer.observe(sentinel);

    return () => observer.disconnect();
  });

  const isCartReady = $derived(otpState.isCartReady);

  // Save discount summary whenever values change during popup lifecycle
  $effect(() => {
    try {
      saveDiscountSummaryToSession(discountAmount, discountTitle);
    } catch (e) {
      console.warn("Failed saving discount summary", e);
    }
  });

  onMount(() => {
    let isMounted = true;
    const initialize = async () => {
      let buyNowFailed = false;
      try {
        if (!isMounted) return;
        // ⚡ Optimized Buy Now: render the popup instantly while the cart chain
        // runs in the background. On a PDP we paint the summary from scraped
        // data; in quick view we show skeletons instead (scraped data there is
        // unreliable across themes). Gated behind the setting (default off).
        if (isOptimizedBuyNowEnabled() && IS_BUY_NOW_BUTTON()) {
          try {
            let optimisticCart = null;
            if (!isQuickViewOpen()) optimisticCart = getOptimisticCartFromDOM();
            if (optimisticCart) {
              otpStoreActions.setOptimisticCart(optimisticCart);
            } else {
              // Quick view (or scrape failed): render screen + skeletons, load in bg.
              otpStoreActions.setOptimisticPending();
            }
          } catch (_e) {}
        }
        callPartialDummyVariantId();
        await cartRevertService();
        if (IS_BUY_NOW_BUTTON() && isMounted) {
          try {
            await shopifyAddToCartForBuyNow();
          } catch (err) {
            buyNowFailed = true;
            console.error("[BuyNow] add-to-cart failed:", err);
            if (isMounted) {
              const code =
                err?.code === "OUT_OF_STOCK" || err?.code === "CART_ADD_FAILED"
                  ? err.code
                  : "CART_ADD_FAILED";
              otpStoreActions.setBuyNowError({
                code,
                message:
                  err?.message ||
                  "We couldn't add this product to your cart.",
              });
            }
            return;
          }
        }
        if (isMounted) {
          await otpStoreActions.fetchProductDetails();
        }
      } catch (error) {
        console.error("Error initializing DesktopOrderSummary:", error);
        if (isMounted && !buyNowFailed) {
          otpStoreActions.setBuyNowError({
            code: "CART_ADD_FAILED",
            message:
              error?.message || "We couldn't load your cart. Please try again.",
          });
        }
      }
    };

    initialize();

    return () => {
      isMounted = false;
    };
  });

  function handleToggleExpand() {
    isExpanded = !isExpanded;
    isSliderOpen = !isSliderOpen;
    if (onExpand) {
      onExpand(!isExpanded);
    }
  }

  function handleCloseSlider() {
    isSliderOpen = false;
    isExpanded = false;
    if (onExpand) {
      onExpand(false);
    }
  }

  // Create orderSummary for OrderSummaryDetails component
  let orderSummaryForDetails = $derived({
    items: productData,
    total: discountedPrice,
    originalTotal: originalPrice,
    discountOnMrp: discountOnMrp,
    discountAmount: discountAmount,
    hasDiscount: hasDiscount,
    currency: currencyCode,
    itemCount: totalQuantity,
    discountCode: discountTitle,
    discountName: discountTitle,
    discountType:
      firstCartDiscount?.value_type || firstCartDiscount?.type || "",
    discountValue: firstCartDiscount?.value || "",
    appliedDiscounts: appliedDiscounts,
    taxAmount: taxAmount,
    showTax: showTax,
    shipping: shippingAmount,
    shippingKnown: shippingKnown,
  });

  let hasCartData = $derived(
    productData.length > 0 || cartState.item_count > 0,
  );
  let isSummaryOptimistic = $derived(otpState.isSummaryOptimistic);
  // Show real content once the cart is ready OR we have optimistic (PDP) data.
  // In the optimistic-pending case (quick view) isSummaryOptimistic is true but
  // there's no cart data yet, so we still show the skeleton. When the flag is
  // off, isSummaryOptimistic is never set, so this stays !isCartReady (original).
  let showSkeleton = $derived(
    !isCartReady && (!isSummaryOptimistic || !hasCartData),
  );
  let loading = $derived(!isCartReady && (!isSummaryOptimistic || !hasCartData));

  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(
    createTranslator(
      $settingsStore || otpState?.settings || null,
    ),
  );

  const itemLabel = $derived(
    totalQuantity === 1 ? T("item_singular") : T("item_plural"),
  );
  // Split on {{amount}} so the figure keeps its own styling inside the sentence
  const savedSoFarParts = $derived(T("saved_so_far").split("{{amount}}"));
</script>

{#if showSkeleton}
  <div
    class="order-summary-unit"
    style="display: {showDisplay ? 'block' : 'none'};"
  >
    <OrderSummarySkeleton />
  </div>
{:else if hasCartData}
  <div class="order-summary-shell">
  <div
    class="order-summary-unit"
    style="display: {showDisplay ? 'block' : 'none'};"
  >
    <Card
      variant="flat"
      padding="md"
      interactive={true}
      attach={savedSoFar > 0 ? "bottom" : "none"}
      testId="order-summary-widget-mobile"
      press={handleToggleExpand}
    >
      <div class="order-summary-row" class:has-gift-badge={hasFreeGift}>
        <div class="order-summary-heading">
          <span class="order-summary-title">{T("order_summary_title")}</span>
          <span class="order-summary-count">({totalQuantity} {itemLabel})</span>
        </div>

        <div class="order-summary-pricing">
          {#if originalPrice > totalWithTax}
            <span class="order-summary-compare">{fmtMoney(originalPrice)}</span>
          {/if}
          <span class="order-summary-total">{fmtMoney(totalWithTax)}</span>
          <svg
            class="order-summary-chevron"
            class:is-expanded={isExpanded}
            width="16"
            height="16"
            viewBox="0 0 16 16"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            aria-hidden="true"
          >
            <path
              d="m8 8.781 3.3-3.3.943.943L8 10.667 3.758 6.424l.943-.943z"
              fill="currentColor"
            />
          </svg>
        </div>
      </div>

      {#if offerMessage}
        <p class="order-summary-offer" role="status" aria-label={offerMessage}>
          <img class="order-summary-offer-icon" src={OFFER_ICON} alt="" />
          {offerMessage}
        </p>
      {/if}
    </Card>
  </div>
  {#if hasFreeGift && showDisplay}
    <div class="ck-gift-badge" aria-label={T("free_gift_added")}>
      <span class="ck-gift-badge__label">{T("free_gift_added")}</span>
      <span class="ck-gift-badge__triangle"></span>
      <img class="ck-gift-badge__icon" src={GIFT_ICON_URL} alt="" />
    </div>
  {/if}
  </div>

  {#if savedSoFar > 0 && showDisplay}
    <div
      class="saved-so-far-sentinel"
      aria-hidden="true"
      bind:this={savingsSentinel}
    ></div>
    <div
      class="saved-so-far-banner"
      class:is-stuck={savingsStuck}
      role="status"
    >
      {savedSoFarParts[0]}<span class="saved-so-far-amount"
        >{fmtMoney(savedSoFar)}</span
      >{savedSoFarParts[1] ?? ""}
      <img class="saved-so-far-emoji" src={CELEBRATION_EMOJI} alt="" />
    </div>
  {/if}
{/if}

{#if hasCartData}
  <Sheet
    open={isSliderOpen}
    headerBorder={false}
    headerBanner={true}
    headerBackground={sheetBannerColor}
    headerTextColor={sheetBannerTextColor}
    closeLabel="Close order summary"
    dismiss={handleCloseSlider}
  >
    {#snippet header()}
      <div class="order-summary-sheet-heading">
        <span class="order-summary-sheet-title">{T("order_summary_title")}</span>
        <span class="order-summary-sheet-count">
          ({totalQuantity} {itemLabel})
        </span>
      </div>
    {/snippet}

    <OrderSummaryDetails orderSummary={orderSummaryForDetails} {loading} />
  </Sheet>
{/if}

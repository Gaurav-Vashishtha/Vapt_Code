<script>
  import { postToParent } from "../../utils/parentMessaging";
  /**
   * OrderSummaryDetails - Displays detailed order summary with items and billing
   * @component
   */
  import { onMount, onDestroy } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { formatCurrency, decodeHtmlEntities } from "../../utils/helpers.js";

  import SkeletonLoader from "../shared/SkeletonLoader.svelte";
  import Card from "../ui/Card.svelte";
  import { removeSessionValue } from "../../services/sessionService.js";
  import { createTranslator } from "../../utils/uiCustomization.js";
  import { saveDiscountSummaryToSession } from "../../utils/partialPaymentUtils.js";
  import { removeCoupon } from "../../services/applyCouponService.js";
  import { removeCouponCode } from "../../services/couponCart.js";
  import "../../styles/components/sections/OrderSummaryDetails.css";
  import { changeCartLineQuantity } from "../../services/cartLineService.js";
  import { actions } from "../../stores/buttonManager.js";
  import { toast } from "../../utils/toast.js";
  import { GIFT_ICON_URL } from "../../services/freeGiftService.js";
  import { cubicInOut, cubicOut } from "svelte/easing";
  import { flip } from "svelte/animate";

  function giftLeave(node, isGift) {
    if (!isGift) return { duration: 0 };
    const style = getComputedStyle(node);
    const height = node.offsetHeight;
    const padTop = parseFloat(style.paddingTop);
    const padBottom = parseFloat(style.paddingBottom);
    const gap = parseFloat(getComputedStyle(node.parentElement).rowGap) || 0;
    const rise = 500;
    const collapse = 200;
    const total = rise + collapse;
    return {
      duration: total,
      css: (t) => {
        const elapsed = (1 - t) * total;
        const a = cubicInOut(Math.min(elapsed / rise, 1));
        const c = cubicInOut(Math.max((elapsed - rise) / collapse, 0));
        return (
          `transform: translateY(${a * 50}px); opacity: ${1 - a};` +
          (c > 0
            ? `overflow: hidden; height: ${(1 - c) * height}px; padding-top: ${(1 - c) * padTop}px; padding-bottom: ${(1 - c) * padBottom}px; margin-bottom: ${-c * gap}px;`
            : "")
        );
      },
    };
  }


  // Props using $props() for Svelte 5 runes mode
  let {
    orderSummary = {
      items: [],
      total: 0,
      originalTotal: 0,
      discountAmount: 0,
      hasDiscount: false,
      currency: "INR",
      itemCount: 0,
      discountCode: "",
      discountName: "",
      discountType: "",
      discountValue: "",
      taxAmount: 0,
      shipping: 0,
      shippingKnown: false,
    },
    loading = false,
  } = $props();

  // Ensure we have items to display
  let hasItems = $derived(orderSummary?.items && orderSummary.items.length > 0);
  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(createTranslator($settingsStore));

  let updatingKey = $state(null);
  let exitItem = $state(null);

  async function setQuantity(item, quantity) {
    if (updatingKey || !item.key) return;
    if (quantity < 1 && orderSummary.items.length === 1) {
      exitItem = item;
      return;
    }
    updatingKey = item.key;
    try {
      await changeCartLineQuantity(item.key, Math.max(quantity, 0));
    } catch (e) {
      toast.error(e?.message || "Could not update quantity.");
    } finally {
      updatingKey = null;
    }
  }

  function portal(node) {
    document.body.appendChild(node);
    return { destroy: () => node.remove() };
  }

  async function removeAndExit() {
    const item = exitItem;
    exitItem = null;
    try {
      await changeCartLineQuantity(item.key, 0);
    } catch (_e) {}
    actions.closeModal();
    try {
      postToParent("codk-close-modal");
    } catch (_e) {}
  }

  // Get item image
  function getItemImage(item) {
    // Check imageSrc first (from productData mapping)
    if (item.imageSrc && item.imageSrc !== "NA") {
      return item.imageSrc;
    }
    // Handle featured_image as object with url property or as string
    if (item.featured_image) {
      if (typeof item.featured_image === "string") {
        return item.featured_image;
      } else if (item.featured_image?.url) {
        return item.featured_image.url;
      }
    }
    return item.image || "";
  }

  // Get item variant display: "Size M • Color Brown" or "Variant: Large"
  function getItemVariant(item) {
    const raw = item.variant_title || item.variantTitle || "";
    if (!raw) return "";
    const t = decodeHtmlEntities(String(raw).trim());
    if (!t) return "";
    if (t.indexOf("•") !== -1 || /^(size|color|style)\s/i.test(t)) return t;
    return `Variant: ${t}`;
  }

  function getItemTitle(item) {
    return decodeHtmlEntities(item.title || item.name || "Product");
  }

  // Get item price (handles both price and finalPrice)
  function getItemPrice(item) {
    return (item.finalPrice || item.price || 0) * (item.quantity || 1);
  }

  // Get item original price
  function getItemOriginalPrice(item) {
    return item.originalPrice || item.original_price || getItemPrice(item);
  }

  // Calculate discount percentage for an item
  function getItemDiscountPercentage(item) {
    const originalPrice = getItemOriginalPrice(item);
    const finalPrice = getItemPrice(item);
    if (originalPrice > 0 && originalPrice > finalPrice) {
      return Math.round(((originalPrice - finalPrice) / originalPrice) * 100);
    }
    return 0;
  }

  // Compute discount values from props
  let showTax = $derived(orderSummary.showTax === true);
  let taxAmount = $derived(orderSummary.taxAmount || 0);
  // Shipping is only a real figure once Shopify has priced a rate for the
  // selected address; until then the row keeps its "next step" placeholder.
  let shippingKnown = $derived(orderSummary.shippingKnown === true);
  let shippingAmount = $derived(
    shippingKnown ? Number(orderSummary.shipping) || 0 : 0,
  );
  let discountAmount = $derived(orderSummary.discountAmount || 0);
  let discountTitle = $derived(
    orderSummary.discountCode || orderSummary.discountName || "",
  );

  // Savings already reflected in the item prices (MRP → selling price).
  let discountOnMrp = $derived(Number(orderSummary?.discountOnMrp) || 0);

  // Ensure billing summary math always adds up:
  // Subtotal - Discount on MRP - Discount = Total
  let displayedDiscountAmount = $derived.by(() => {
    const orig = Number(orderSummary?.originalTotal) || 0;
    const total = Number(orderSummary?.total) || 0;
    const diff = Math.max(0, orig - discountOnMrp - total);
    return Math.round(diff * 100) / 100;
  });

  // Save discount summary whenever values change
  $effect(() => {
    try {
      saveDiscountSummaryToSession(discountAmount, discountTitle);
    } catch (_e) {}
  });

  // Individual applied discounts (each with its own amount + removability).
  let appliedDiscounts = $derived(orderSummary.appliedDiscounts || []);

  // Track if component is mounted
  let isMounted = $state(true);
  let removeCouponLoading = $state(false);
  let removingKey = $state(null);

  // Initialize carts on mount
  onMount(() => {
    isMounted = true;

    const initializeCarts = async () => {
      try {
        if (isMounted) {
          saveDiscountSummaryToSession(discountAmount, discountTitle);
        }
      } catch (_e) {}
    };

    initializeCarts();
  });

  // Cleanup on unmount
  onDestroy(() => {
    isMounted = false;

    try {
      removeSessionValue("codk_discount_summary");
    } catch (_e) {}
  });
</script>

<div class="order-summary-details">
  <Card variant="flat" padding="sm" attach="bottom">
    <div class="order-details-stack">
    <div class="order-items-section">
      {#if loading}
        {#each Array.from({ length: 2 }) as _, idx (idx)}
          <div class="order-item-row">
            <div class="item-image-container">
              <SkeletonLoader width="48px" height="48px" />
            </div>
            <div class="item-info">
              <SkeletonLoader lines={1} width="70%" />
              <SkeletonLoader lines={1} width="40%" />
            </div>
            <div class="item-pricing">
              <SkeletonLoader lines={1} width="56px" />
            </div>
          </div>
        {/each}
      {:else if hasItems}
        {#each orderSummary.items as item (item.rowKey || item.key || item.title)}
          <div class="order-item-row" class:order-item-row--gift={item.isFreeGift} out:giftLeave={item.isFreeGift} animate:flip={{ duration: 300, easing: cubicOut }}>
            <div class="item-image-container">
              {#if getItemImage(item)}
                <img
                  src={getItemImage(item)}
                  alt={getItemTitle(item)}
                  loading="lazy"
                  class="item-image"
                />
              {:else}
                <div class="item-image-placeholder">
                  <svg
                    width="24"
                    height="24"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.5"
                  >
                    <rect x="3" y="3" width="18" height="18" rx="2" />
                    <path d="M9 9h6v6H9z" />
                  </svg>
                </div>
              {/if}
            </div>

            <div class="item-info">
              <div class="item-title" title={getItemTitle(item)}>
                {getItemTitle(item)}
              </div>
              {#if getItemVariant(item)}
                <div class="item-variant">{getItemVariant(item)}</div>
              {/if}
              {#if item.isFreeGift}
                <div class="item-quantity">{T("qty", { count: item.quantity || 1 })}</div>
                <div class="ck-freebie-tag">
                  <img class="ck-freebie-tag__icon" src={GIFT_ICON_URL} alt="" />
                  <span>{T("free_gift_tag")}</span>
                </div>
              {:else if item.key}
                <div class="item-qty" class:is-busy={updatingKey === item.key}>
                  <button
                    type="button"
                    class="item-qty-btn"
                    aria-label="Decrease quantity"
                    disabled={updatingKey !== null}
                    onclick={() => setQuantity(item, (item.quantity || 1) - 1)}
                  >-</button>
                  <span class="item-qty-value">{item.quantity || 1}</span>
                  <button
                    type="button"
                    class="item-qty-btn"
                    aria-label="Increase quantity"
                    disabled={updatingKey !== null}
                    onclick={() => setQuantity(item, (item.quantity || 1) + 1)}
                  >+</button>
                </div>
              {:else}
                <div class="item-quantity">{T("qty", { count: item.quantity || 1 })}</div>
              {/if}
            </div>

            <div class="item-pricing">
              {#if item.isFreeGift}
                <span class="item-final-price item-final-price--free">{T("free_gift_price")}</span>
                {#if item.lineOriginalPrice > 0}
                  <span class="item-original-price">
                    {formatCurrency(item.lineOriginalPrice, orderSummary.currency)}
                  </span>
                {/if}
              {:else}
              <span class="item-final-price">
                {formatCurrency(getItemPrice(item), orderSummary.currency)}
              </span>
              {#if getItemOriginalPrice(item) > getItemPrice(item)}
                <span class="item-original-price">
                  {formatCurrency(
                    getItemOriginalPrice(item),
                    orderSummary.currency,
                  )}
                </span>
              {/if}
              {/if}
            </div>
          </div>
        {/each}
      {:else}
        <div class="empty-state">
          <p>{T("no_items_in_cart")}</p>
        </div>
      {/if}
    </div>

    <div class="billing-summary">
      <h3 class="billing-title">{T("billing_summary_title")}</h3>

      {#if loading}
        <div class="billing-details">
          <SkeletonLoader lines={1} width="70%" />
          <SkeletonLoader lines={1} width="60%" />
          <SkeletonLoader lines={1} width="80%" />
        </div>
      {:else}
        <div class="billing-details">
          <div class="billing-row">
            <span class="billing-label">{T("subtotal")}</span>
            <span class="billing-value">
              {formatCurrency(orderSummary.originalTotal, orderSummary.currency)}
            </span>
          </div>

          {#if discountOnMrp > 0}
            <div class="billing-row discount-row">
              <span class="billing-label">{T("discount_on_mrp")}</span>
              <span class="billing-value discount-value">
                -{formatCurrency(discountOnMrp, orderSummary.currency)}
              </span>
            </div>
          {/if}

          {#if appliedDiscounts.length > 0}
            {#each appliedDiscounts as d (d.label)}
              <div class="billing-row discount-row">
                <span class="billing-label">{T("discount_with_name", { name: d.isAutomatic ? `Auto Discount ${d.label}` : d.label })}</span>
                <span class="billing-value discount-value">
                  -{formatCurrency(d.amount, orderSummary.currency)}
                </span>
              </div>
            {/each}
          {:else if orderSummary.hasDiscount && displayedDiscountAmount > 0}
            <div class="billing-row discount-row">
              <span class="billing-label">
                {#if orderSummary.discountName || orderSummary.discountCode}
                  {T("discount_with_name", {
                    name:
                      orderSummary.discountName || orderSummary.discountCode,
                  })}
                {:else}
                  {T("discount")}
                {/if}
              </span>
              <span class="billing-value discount-value">
                -{formatCurrency(
                  displayedDiscountAmount,
                  orderSummary.currency,
                )}
              </span>
            </div>
          {/if}

          <div class="billing-row">
            <span class="billing-label">{T("shipping")}</span>
            <span class="billing-value">
              {#if shippingKnown}
                {shippingAmount > 0
                  ? formatCurrency(shippingAmount, orderSummary.currency)
                  : "Free"}
              {:else}
                {T("shipping_value")}
              {/if}
            </span>
          </div>

          {#if showTax}
            <div class="billing-row">
              <span class="billing-label">{T("tax")}</span>
              <span class="billing-value">
                {formatCurrency(taxAmount, orderSummary.currency)}
              </span>
            </div>
          {/if}

          <div class="billing-total">
            <span class="total-label">{T("total_amount")}</span>
            <span class="total-value">
              {formatCurrency(
                orderSummary.total + (showTax ? taxAmount : 0) + shippingAmount,
                orderSummary.currency,
              )}
            </span>
          </div>
        </div>
      {/if}
    </div>
    </div>
  </Card>
</div>

{#if exitItem}
  {@const confirmParts = T("remove_item_confirm", { name: "\u0001" }).split("\u0001")}
  <div class="exit-confirm-overlay" role="presentation" use:portal>
    <div class="exit-confirm-card" role="alertdialog" aria-modal="true">
      <p class="exit-confirm-text">
        {confirmParts[0]}<span class="exit-confirm-name">{getItemTitle(exitItem)}</span>{confirmParts[1] ?? ""}
      </p>
      <div class="exit-confirm-actions">
        <button type="button" class="exit-confirm-remove" onclick={removeAndExit}>
          {T("remove_item_exit")}
        </button>
        <button type="button" class="exit-confirm-continue" onclick={() => (exitItem = null)}>
          {T("continue_checkout")}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .item-qty {
    display: inline-flex;
    align-items: center;
    justify-content: space-between;
    width: 72px;
    height: 26px;
    margin-top: var(--space-1);
    padding: 0 var(--space-1);
    box-sizing: border-box;
    border: 1px solid color-mix(in srgb, var(--color-blue) 20%, transparent);
    border-radius: var(--radius-sm);
    background: var(--surface-card);
  }
  .item-qty.is-busy {
    opacity: 0.6;
  }
  .item-qty-btn {
    width: 20px;
    height: 100%;
    padding: 0;
    border: none;
    background: transparent;
    color: var(--color-blue);
    font-family: inherit;
    font-size: var(--font-size-sm);
    font-weight: var(--font-weight-bold);
    line-height: 1;
    cursor: pointer;
  }
  .item-qty-btn:disabled {
    cursor: default;
  }
  .item-qty-value {
    font-size: 13px;
    font-weight: var(--font-weight-semibold);
    color: var(--color-text-primary);
  }

  .exit-confirm-overlay {
    position: fixed;
    inset: 0;
    z-index: 2147483647;
    background: var(--color-overlay);
  }
  .exit-confirm-card {
    position: absolute;
    top: 25%;
    left: 0;
    right: 0;
    width: 90%;
    max-width: 360px;
    margin: 0 auto;
    padding: 18px;
    box-sizing: border-box;
    border-radius: var(--radius-base);
    background: #f4f6fc;
    text-align: center;
  }
  .exit-confirm-text {
    margin: 0 0 var(--space-4);
    font-size: var(--font-size-base);
    line-height: 24px;
    color: var(--color-text-primary);
  }
  .exit-confirm-name {
    font-weight: var(--font-weight-semibold);
  }
  .exit-confirm-actions {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .exit-confirm-remove,
  .exit-confirm-continue {
    width: 100%;
    padding: 15px 0;
    border-radius: 6px;
    font-family: inherit;
    font-size: var(--font-size-base);
    font-weight: var(--font-weight-semibold);
    cursor: pointer;
  }
  .exit-confirm-remove {
    border: none;
    background: var(--color-blue);
    color: #fff;
  }
  .exit-confirm-continue {
    border: 0.8px solid var(--color-blue);
    background: #fff;
    color: var(--color-blue);
  }
</style>

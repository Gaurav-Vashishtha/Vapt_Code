<script>
  import otpStore from "../../stores/otpStore.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { getSessionValue, isOptimizedBuyNowEnabled } from "../../services/sessionService.js";
  import { removeCoupon } from "../../services/applyCouponService.js";
  import { applyCouponCode } from "../../services/couponCart.js";
  import CouponsList from "./CouponsList.svelte";
  import CouponInputRow from "../shared/CouponInputRow.svelte";
  import Spinner from "../shared/Spinner.svelte";
  import Card from "../ui/Card.svelte";
  import { toast } from "../../utils/toast.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(createTranslator($settingsStore));

  let { showDisplay = false } = $props();

  let otpState = $derived($otpStore);
  let currentCartData = $derived(otpState.currentCartData || {});
  const cartState = $derived(currentCartData || {});
  let settings = $derived(otpState.settings || {});
  // Optimized Buy Now only: while the cart chain is still loading, show a
  // skeleton for the discounts card instead of a premature coupon input/list.
  // When the flag is off, isOptimizedBuyNowEnabled() is false, so this is never
  // true and the card renders exactly as before.
  let showDiscountSkeleton = $derived(
    isOptimizedBuyNowEnabled() && !otpState.isCartReady,
  );
  let hasCoupons = $derived(
    Array.isArray(settings.activeDiscounts) && settings.activeDiscounts.length > 0,
  );

  const discountAmount = $derived((cartState.total_discount || 0) / 100);
  const hasDiscount = $derived((cartState.total_discount || 0) > 0);
  const firstCartDiscount = $derived(
    cartState.cart_level_discount_applications?.[0],
  );

  const sessionDiscount = $derived.by(() => {
    try {
      const summary = getSessionValue("codk_discount_summary", null);
      return summary?.discountName || summary?.discountTitle || "";
    } catch {
      return "";
    }
  });

  const discountTitle = $derived(
    firstCartDiscount?.title ||
      firstCartDiscount?.description ||
      cartState.discount_codes?.[0]?.code ||
      sessionDiscount ||
      "",
  );

  const hasCodeDiscount = $derived(
    Array.isArray(cartState.discount_codes) &&
      cartState.discount_codes.length > 0,
  );

  let couponRow;
  let couponInput = $state("");
  let couponLoading = $state(false);
  let couponMessage = $state("");
  let couponMessageSuccess = $state(false);
  let removeCouponLoading = $state(false);

  function formatSavings(amount) {
    const n = Number(amount);
    if (isNaN(n) || n < 0) return "₹0";
    return n % 1 === 0 ? `₹${n}` : `₹${n.toFixed(2)}`;
  }

  function couponNotify(msg, ok) {
    const text = String(msg || "").trim();
    if (!text) {
      couponMessage = "";
      couponMessageSuccess = false;
      return;
    }
    (ok ? toast.success(text) : toast.error(text)).then((shown) => {
      if (shown) return;
      couponMessage = text;
      couponMessageSuccess = ok;
      setTimeout(() => (couponMessage = ""), ok ? 3000 : 5000);
    });
  }

  async function handleApplyCoupon() {
    if (couponLoading || !couponInput.trim()) return;
    couponMessage = "";
    couponMessageSuccess = false;
    couponLoading = true;
    try {
      const result = await applyCouponCode(couponInput);
      if (result.success) {
        couponInput = "";
        couponMessage = "";
      } else {
        couponNotify(
          (typeof result === "object" && result && "message" in result
            ? result.message
            : "") || "Could not apply coupon.",
          false,
        );
      }
    } catch (e) {
      couponNotify(e?.message || "Could not apply coupon. Please try again.", false);
    } finally {
      couponLoading = false;
    }
  }

  async function handleRemoveCoupon() {
    if (removeCouponLoading) return;
    removeCouponLoading = true;
    couponMessage = "";
    try {
      const result = await removeCoupon();
      if (!result.success) {
        couponNotify(
          (typeof result === "object" && result && "message" in result
            ? result.message
            : "") || "Could not remove coupon.",
          false,
        );
      }
    } catch (e) {
      couponNotify(e?.message || "Could not remove coupon.", false);
    } finally {
      removeCouponLoading = false;
    }
  }

  function onCouponInputChange() {
    couponMessage = "";
  }
</script>

{#if showDisplay}
  <Card variant="elevated" padding="md" class="tp-coupon-card">
    {#if showDiscountSkeleton}
      <div class="tp-coupon-skeleton" aria-hidden="true">
        <div class="tp-coupon-skeleton-line tp-coupon-skeleton-line--lg"></div>
        <div class="tp-coupon-skeleton-line tp-coupon-skeleton-line--sm"></div>
      </div>
    {:else if hasCoupons || hasDiscount}
      <!-- Render the coupon list when there are configured coupons OR any cart
           discount, so external codes and automatic discounts surface too. -->
      <CouponsList />
    {:else if hasDiscount && hasCodeDiscount}
      <div class="tp-coupon-applied">
        <div class="tp-coupon-applied-row">
          <span class="tp-coupon-applied-info">
            <span class="tp-coupon-applied-code">{discountTitle || "Applied"}</span>
            <span class="tp-coupon-applied-amount">{formatSavings(discountAmount)} OFF</span>
          </span>
          <button
            type="button"
            class="tp-coupon-remove-btn"
            disabled={removeCouponLoading}
            onclick={handleRemoveCoupon}
          >
            {#if removeCouponLoading}<Spinner size={14} />{:else}Remove{/if}
          </button>
        </div>
      </div>
    {:else}
      <div class="tp-coupon-empty ck-shimmer">
        <CouponInputRow
          bind:this={couponRow}
          bind:value={couponInput}
          placeholder={T("coupon_placeholder")}
          busy={couponLoading}
          change={onCouponInputChange}
          apply={handleApplyCoupon}
        />
        <button
          type="button"
          class="tp-coupon-empty-note"
          onclick={() => couponRow?.focus()}
        >
          {T("coupon_have_code")}
        </button>
      </div>
    {/if}

    {#if couponMessage}
      <p
        class="tp-coupon-message"
        class:tp-coupon-message-success={couponMessageSuccess}
        class:tp-coupon-message-error={!couponMessageSuccess}
      >
        {couponMessage}
      </p>
    {/if}
  </Card>
{/if}

<style>
  .tp-coupon-skeleton {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 4px 2px;
  }
  .tp-coupon-skeleton-line {
    height: 14px;
    border-radius: 6px;
    background: linear-gradient(90deg, #eef1f6 25%, #e2e6ee 50%, #eef1f6 75%);
    background-size: 200% 100%;
    animation: tp-coupon-skeleton-loading 1.5s ease-in-out infinite;
  }
  .tp-coupon-skeleton-line--lg {
    width: 60%;
  }
  .tp-coupon-skeleton-line--sm {
    width: 40%;
    height: 12px;
  }
  @keyframes tp-coupon-skeleton-loading {
    0% {
      background-position: 200% 0;
    }
    100% {
      background-position: -200% 0;
    }
  }

  .tp-coupon-empty {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
  }

  .tp-coupon-empty.ck-shimmer {
    margin: -12px;
    padding: 12px;
    border-radius: var(--radius-md);
  }

  .tp-coupon-empty-note {
    background: none;
    border: none;
    padding: 0;
    text-align: left;
    cursor: pointer;
    font-family: var(--font-family-base);
    font-size: var(--font-size-xs);
    font-weight: 500;
    color: var(--color-blue);
  }

  .tp-coupon-applied {
    padding: 2px 0;
  }

  .tp-coupon-applied-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .tp-coupon-applied-info {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
  }

  .tp-coupon-applied-code {
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--color-text-primary);
  }

  .tp-coupon-applied-amount {
    font-size: var(--font-size-caption);
    color: #fff;
    font-weight: 600;
    background: var(--color-savings-badge);
    padding: 2px 8px;
    border-radius: var(--radius-sm);
  }

  .tp-coupon-remove-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 54px;
    font-size: var(--font-size-sm);
    font-weight: 600;
    padding: 5px 6px;
    border: none;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--color-savings-strong);
    cursor: pointer;
  }

  .tp-coupon-remove-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .tp-coupon-message {
    font-size: var(--font-size-caption);
    margin-top: 6px;
    padding: 0 2px;
  }

  .tp-coupon-message-success {
    color: var(--color-savings-strong);
  }

  .tp-coupon-message-error {
    color: var(--color-error);
  }
</style>

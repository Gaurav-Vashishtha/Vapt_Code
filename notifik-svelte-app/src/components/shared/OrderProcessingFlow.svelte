<script>
  import { onDestroy } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { fade } from "svelte/transition";
  import { codOrderFlowStore } from "../../stores/codOrderFlowStore.js";
  import { actions } from "../../stores/buttonManager.js";
  import { formatCurrency, getShopDomain } from "../../utils/helpers.js";
  import CodKingLoadingScreen from "./CodKingLoadingScreen.svelte";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  const REDIRECT_COD_TO_ORDER_STATUS = "true";

  $: isProcessing = $codOrderFlowStore.isProcessing;
  $: orderResult = $codOrderFlowStore.orderResult;

  function formatAddressLine(addr) {
    if (!addr) return "";
    const parts = [
      addr.address1,
      addr.address2,
      addr.city,
      addr.province,
      addr.zip,
      addr.country,
    ].filter(Boolean);
    return parts.join(", ");
  }

  let flowState = "processing"; // 'processing' | 'confirmed' | 'thankyou'
  let confirmedTimeoutId = null;

  $: if (!isProcessing && orderResult && flowState === "processing") {
    flowState = "confirmed";
    if (confirmedTimeoutId) clearTimeout(confirmedTimeoutId);
    confirmedTimeoutId = setTimeout(() => {
      const paymentMethod = String(orderResult?.paymentMethod || "");
      const isCod =
        paymentMethod.toLowerCase().includes("cash") ||
        paymentMethod.toLowerCase().includes("cod");

      if (REDIRECT_COD_TO_ORDER_STATUS && isCod && orderResult?.orderStatusUrl) {
        handleTrackOrder();
        return;
      }

      flowState = "thankyou";
      confirmedTimeoutId = null;
    }, 700);
  }

  $: if (isProcessing) {
    flowState = "processing";
    if (confirmedTimeoutId) {
      clearTimeout(confirmedTimeoutId);
      confirmedTimeoutId = null;
    }
  }

  function handleContinueShopping() {
    codOrderFlowStore.clear();
    actions.setShowCodOrderFlow(false);
    actions.closeModal();
  }

  function handleTrackOrder() {
    if (!orderResult?.orderStatusUrl) return;
    const target =
      typeof window !== "undefined" && window.top ? window.top : window;
    target.location.href = orderResult.orderStatusUrl;
  }

  function handleViewOrders() {
    const shop = getShopDomain();
    if (!shop) return;
    const target =
      typeof window !== "undefined" && window.top ? window.top : window;
    target.location.href = `https://${shop}/account/orders`;
  }

  onDestroy(() => {
    if (confirmedTimeoutId) clearTimeout(confirmedTimeoutId);
  });
</script>

<!-- Full-screen like verified/processing page: fills entire content area -->
<div
  class="w-full min-h-full flex flex-col p-3 box-border {flowState ===
  'thankyou'
    ? 'items-center justify-start overflow-y-auto'
    : 'items-center justify-center'}"
  role="status"
  aria-live="polite"
>
  <!-- STATES 1 & 2: Processing / Confirmed — branded COD King loader -->
  {#if flowState === "processing" || flowState === "confirmed"}
    <div class="w-full flex-1 flex flex-col min-h-0">
      <CodKingLoadingScreen
        text={flowState === "confirmed"
          ? T("order_confirmed_redirect")
          : T("order_processing")}
      />
    </div>
  {/if}

  <!-- STATE 3: Thank You — premium full page (4 sections) -->
  {#if flowState === "thankyou"}
    <div
      class="thankyou-page w-full max-w-[420px] flex flex-col min-h-0 max-h-[90dvh] overflow-hidden"
      transition:fade={{ duration: 180 }}
      role="article"
    >
      <!-- Close button (top-right) -->
      <div class="flex justify-end shrink-0 px-1 -mt-1 mb-1">
        <button
          type="button"
          class="thankyou-close p-2 rounded-full text-gray-500 hover:bg-gray-100 hover:text-gray-700 border-0 cursor-pointer transition-colors"
          on:click={handleContinueShopping}
          aria-label="Close"
        >
          <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Scrollable content -->
      <div class="flex-1 overflow-y-auto flex flex-col gap-4 pb-4 min-h-0">
        <!-- Section 1: Success Header -->
        <div class="flex flex-col items-center text-center gap-2">
          <div
            class="animate-success-in w-16 h-16 rounded-full bg-gradient-to-b from-green-50 to-emerald-100 border border-green-200/80 flex items-center justify-center text-green-600 shrink-0"
          >
            <svg class="w-8 h-8" viewBox="0 0 24 24" aria-hidden="true">
              <path
                class="order-flow-checkmark-path"
                d="M20 6L9 17l-5-5"
                fill="none"
                stroke="currentColor"
                stroke-width="2.5"
                stroke-linecap="round"
                stroke-linejoin="round"
                pathLength="1"
              />
            </svg>
          </div>
          <h1
            class="m-0 text-xl font-bold text-gray-900 tracking-tight leading-tight"
          >
            {T("oc_thank_you")}
          </h1>
          <p class="m-0 text-sm font-medium text-gray-500 leading-snug">
            {T("oc_placed")}
          </p>
          <p class="m-0 text-xs font-medium text-gray-400 leading-snug">
            {T("oc_preparing")}
          </p>
        </div>

        <!-- Section 2: Order Summary Card -->
        <div
          class="rounded-2xl border border-black/5 bg-white shadow-sm p-4 flex flex-col gap-3"
        >
          <h2 class="m-0 text-sm font-semibold text-gray-900">{T("order_summary_title")}</h2>
          <div class="flex flex-col gap-2 text-sm">
            {#if orderResult?.orderNumber}
              <div class="flex justify-between items-center">
                <span class="text-gray-500">{T("oc_order_number")}</span>
                <span class="font-semibold text-gray-900"
                  >#{orderResult.orderNumber}</span
                >
              </div>
            {/if}
            {#if orderResult?.total != null}
              <div class="flex justify-between items-center">
                <span class="text-gray-500">{T("total_amount")}</span>
                <span class="font-semibold text-gray-900">
                  {formatCurrency(
                    orderResult.total,
                    orderResult.currencyCode || "INR",
                  )}
                </span>
              </div>
            {/if}
            <div class="flex justify-between items-center">
              <span class="text-gray-500">{T("oc_payment_method")}</span>
              <span class="font-medium text-gray-900"
                >{orderResult?.paymentMethod || "Cash on Delivery"}</span
              >
            </div>
            {#if orderResult?.deliveryEstimate}
              <div class="flex justify-between items-center">
                <span class="text-gray-500">{T("oc_estimated_delivery")}</span>
                <span class="font-medium text-gray-900"
                  >{orderResult.deliveryEstimate}</span
                >
              </div>
            {/if}
          </div>
        </div>

        <!-- Section 3: Delivery Address Card -->
        {#if orderResult?.deliveryAddress}
          <div
            class="rounded-2xl border border-black/5 bg-white shadow-sm p-4 flex flex-col gap-2"
          >
            <h2
              class="m-0 text-sm font-semibold text-gray-900 flex items-center gap-2"
            >
              <svg
                class="w-4 h-4 text-gray-500 shrink-0"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
              {T("delivery_summary_title")}
            </h2>
            <p class="m-0 text-sm font-medium text-gray-900">
              {orderResult.deliveryAddress.name}
            </p>
            <p class="m-0 text-sm text-gray-600 leading-snug">
              {formatAddressLine(orderResult.deliveryAddress)}
            </p>
            {#if orderResult.deliveryAddress.phone}
              <p class="m-0 text-sm text-gray-600 flex items-center gap-2">
                <svg
                  class="w-4 h-4 text-gray-500 shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"
                  />
                </svg>
                {orderResult.deliveryAddress.phone}
              </p>
            {/if}
            {#if orderResult.deliveryAddress.email}
              <p class="m-0 text-sm text-gray-600 flex items-center gap-2">
                <svg
                  class="w-4 h-4 text-gray-500 shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                  />
                </svg>
                {orderResult.deliveryAddress.email}
              </p>
            {/if}
          </div>
        {/if}

        <p
          class="m-0 text-sm font-medium text-gray-500 text-center leading-snug"
        >
          {T("oc_updates_note")}
        </p>
      </div>

      <!-- Section 4: Actions (sticky on small screens so Continue Shopping is always visible) -->
      <div class="thankyou-actions shrink-0 pt-3 pb-2 flex flex-col gap-3 w-full bg-gradient-to-t from-neutral-50 to-transparent">
        {#if orderResult?.orderStatusUrl}
          <button
            type="button"
            class="w-full h-12 px-6 rounded-xl text-[15px] font-semibold bg-gray-900 text-white border-0 cursor-pointer transition-colors duration-200 hover:bg-gray-800 active:opacity-90"
            on:click={handleTrackOrder}
          >
            {T("oc_track_order")}
          </button>
        {:else if orderResult?.orderNumber}
          <button
            type="button"
            class="w-full h-12 px-6 rounded-xl text-[15px] font-semibold bg-gray-900 text-white border-0 cursor-pointer transition-colors duration-200 hover:bg-gray-800 active:opacity-90"
            on:click={handleViewOrders}
          >
            {T("oc_view_orders")}
          </button>
        {/if}
        <button
          type="button"
          class="w-full h-12 px-6 rounded-xl text-[15px] font-semibold bg-white text-gray-900 border border-gray-300 cursor-pointer transition-colors duration-200 hover:bg-gray-50 active:opacity-90"
          on:click={handleContinueShopping}
        >
          {T("oc_continue_shopping")}
        </button>
      </div>
    </div>
  {/if}
</div>

<!-- Only animation Tailwind doesn't provide: checkmark draw -->
<style>
  .order-flow-checkmark-path {
    stroke-dasharray: 1;
    stroke-dashoffset: 1;
    animation: order-flow-check-draw 0.28s cubic-bezier(0.34, 1.2, 0.64, 1)
      0.06s forwards;
  }
  @keyframes order-flow-check-draw {
    to {
      stroke-dashoffset: 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .order-flow-checkmark-path {
      animation: none;
      stroke-dashoffset: 0;
    }
  }
</style>

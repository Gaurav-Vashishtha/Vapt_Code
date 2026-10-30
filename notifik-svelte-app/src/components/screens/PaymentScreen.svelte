<script>
  import { tick } from "svelte";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import { closeModalAndNotifyParent } from "../../utils/helpers.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import { getSessionValue, getSettings, isOptimizedBuyNowEnabled } from "../../services/sessionService.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Layout Components
  import DeliveryDetailsSection from "../sections/DeliveryDetailsSection.svelte";
  import PaymentOptionsSection from "../sections/PaymentOptionsSection.svelte";
  import CODKButton from "../shared/CODKButton.svelte";
  import CheckoutLoader from "../shared/CheckoutLoader.svelte";
  import "../../styles/components/screens/PaymentScreen.css";
  import "../../styles/components/screens/PaymentScreen.mobile.css";
  import "../../styles/components/screens/PaymentScreen.desktop.css";
  import BrandFooter from "../shared/BrandFooter.svelte";
  import LoginInfoSection from "../shared/LoginInfoSection.svelte";

  // PaymentScreen is a simple display component
  // PaymentOptionsSection handles all initialization and API calls
  let paymentOptionsComponent = $state(null);

  // ⚡ Always derive settings from setting session (normalized camelCase), fallback to appStore
  let settings = $derived(getSettings() || $appStore.settings);
  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(createTranslator(settings));

  let isCartReady = $derived($otpStore.isCartReady || false);
  let isSummaryOptimistic = $derived($otpStore.isSummaryOptimistic || false);
  let optimizedBuyNow = $derived(($otpStore.settings, isOptimizedBuyNowEnabled()));
  // Optimized: always render the payment screen so the sections show skeletons
  // (order summary + discounts + payment methods) instead of a full-screen
  // loader — for quick-view buy now AND checkout-only click. The CTA stays
  // disabled until the cart is ready. Off: original — wait for isCartReady.
  let canRenderPayment = $derived(isCartReady || optimizedBuyNow);
  // Optimized only: give the CTA a label while it waits for the cart, instead of
  // a bare spinner. Off: empty string → original spinner-only behavior.
  let ctaLoadingLabel = $derived(
    optimizedBuyNow && !isCartReady ? T("cta_preparing") : "",
  );

  // Smooth-scroll the upsell block (when shown) or the "Pay via" card into view once the payment screen is ready.
  let paymentScreenWrapperRef = $state(
    /** @type {HTMLElement | null} */ (null),
  );
  let didAutoScroll = $state(false);
  $effect(() => {
    if (didAutoScroll || !canRenderPayment || !paymentScreenWrapperRef) return;
    const wrapper = paymentScreenWrapperRef;
    didAutoScroll = true;
    tick().then(() => {
      setTimeout(() => {
        const el =
          document.querySelector(".cu-section") ||
          wrapper.querySelector(".payment-options-section");
        if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
      }, 220);
    });
  });

  // Local state to track handleSubmit loading (prevents double clicks)
  let isSubmitting = $state(false);

  let primaryButton = $derived(
    $appStore.primaryButton || {
      label: T("cta_proceed"),
      loading: false,
      disabled: true,
      action: "submit",
    },
  );
  let phoneNumber = $derived($appStore.phoneNumber || "");

  // Address section shows when "Prefilled Address" is enabled OR "COD Form" is enabled
  let showDeliveryDetails = $derived(
    !!(
      settings?.isPrefilledAddressEnabled ||
      settings?.is_prefilled_address_enabled ||
      settings?.cod_form_enabled === true ||
      settings?.cod_form_enabled === "true"
    ),
  );

  let selectedAddress = $derived(
    $appStore.addresses?.find(
      (addr) => addr.id === $appStore.selectedAddressId,
    ) || null,
  );

  let customerEmail = $derived($appStore.customerEmail || "");

  async function handleSubmit() {
    if (isSubmitting) return;
    try {
      isSubmitting = true;
      if (paymentOptionsComponent?.handleSubmit) {
        await paymentOptionsComponent.handleSubmit();
      }
    } catch (_error) {
    } finally {
      isSubmitting = false;
    }
  }

  async function handlePrimaryButtonClick() {
    // The CTA is disabled until the authoritative cart is ready (clear/add/cart.js
    // complete) in all cases, so by the time this fires the cart is loaded.
    if (primaryButton.loading || primaryButton.disabled || isSubmitting) return;

    const action = primaryButton.action;
    if (action === "close_modal") {
      closeModalAndNotifyParent(actions.closeModal, false);
      return;
    }
    if (
      action === "complete_order" &&
      paymentOptionsComponent?.handleCompleteOrder
    ) {
      await paymentOptionsComponent.handleCompleteOrder();
    } else if (
      action === "pay_now" &&
      paymentOptionsComponent?.handleRazorpayPayment
    ) {
      await paymentOptionsComponent.handleRazorpayPayment();
    } else {
      await handleSubmit();
    }
  }

  async function handleMethodProceed() {
    try {
      await tick();
      await handlePrimaryButtonClick();
    } finally {
      otpStoreActions.setIsProceedingPayment(false);
    }
  }

  const normalizePhone = (val) => {
    const s = (val ?? "").toString().trim();
    if (!s) return "";
    return s.startsWith("+") ? s : `+${s}`;
  };
  let verifiedDataForPhone = $derived(
    getSessionValue("verifiedNumberData", null),
  );
  let verifiedPhoneNumber = $derived(
    verifiedDataForPhone?.otpVerifiedPhoneNumber || "",
  );
  let showCodOrderFlow = $derived($appStore.showCodOrderFlow === true);
</script>

<!-- Payment Screen Content -->
<div class="payment-screen-wrapper" bind:this={paymentScreenWrapperRef}>
  <!-- Delivery Details Section (only show if prefilled address is enabled) -->
  {#if !canRenderPayment}
    <CheckoutLoader />
  {:else}
    {#if showDeliveryDetails}
      <DeliveryDetailsSection {selectedAddress} {phoneNumber} {customerEmail} />
    {/if}

    <!-- Payment Options Section -->
    <PaymentOptionsSection
      bind:this={paymentOptionsComponent}
      on:proceed={handleMethodProceed}
    />

    <div class="login-info-container">
      <LoginInfoSection />
    </div>
  {/if}
</div>

{#if canRenderPayment}
  <div class="payment-brand-footer">
    <BrandFooter />
  </div>
{/if}

<style>
  .sticky-button-container {
    background: transparent;
    border: none;
    border-radius: 0;
    box-shadow: none !important;
  }
</style>

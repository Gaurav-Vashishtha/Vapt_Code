<script>
  import { postToParent } from "../../utils/parentMessaging";
  import { onMount, untrack } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { get } from "svelte/store";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import { getCurrentStep } from "../../utils/stepUtils.js";
  import PhoneInput from "../screens/PhoneInputScreen.svelte";
  import OtpVerificationContent from "../screens/OtpVerificationContent.svelte";

  import AddressSelectionContent from "../screens/AddressSelectionContent.svelte";
  import AddressFormContent from "../screens/AddressFormContent.svelte";
  import PaymentScreen from "../screens/PaymentScreen.svelte";
  import PaymentProcessingContent from "../screens/PaymentProcessingContent.svelte";
  import BottomSlider from "../shared/BottomSlider.svelte";
  import Sheet from "../ui/Sheet.svelte";
  import Card from "../ui/Card.svelte";
  import ScreenLayout from "./ScreenLayout.svelte";
  import ScreenHeader from "./ScreenHeader.svelte";
  import ScreenContent from "./ScreenContent.svelte";
  import { formatTitle, checkImageAspectRatio } from "../../utils/helpers.js";
  // Use existing Modal CSS - don't create new layout CSS
  import "../../styles/components/Modal.css";
  import "../../styles/components/Modal.mobile.css";
  import "../../styles/components/Modal.desktop.css";
  import OrderSummaryCard from "../sections/OrderSummaryCard.svelte";
  import OffersRewardsSection from "../sections/OffersRewardsSection.svelte";
  import UpsellSection from "../sections/UpsellSection.svelte";
  import FreeGiftSection from "../sections/FreeGiftSection.svelte";
  import PromoBanner from "../shared/PromoBanner.svelte";
  import CloseConfirmSlider from "../shared/CloseConfirmSlider.svelte";

  import CartLoadingScreen from "../shared/CartLoadingScreen.svelte";
  import otpStore from "../../stores/otpStore.js";
  import { isOptimizedBuyNowEnabled } from "../../services/sessionService.js";
  import { codOrderFlowStore } from "../../stores/codOrderFlowStore.js";
  import OrderProcessingFlow from "../shared/OrderProcessingFlow.svelte";
  import CelebrationDialog from "../shared/CelebrationDialog.svelte";
  import { updateCartDetailsForPreCreation } from "../../services/api.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(createTranslator($settingsStore));

  let { onClose = null } = $props();

  // Get state from appStore (primary source of truth)
  let currentScreen = $derived($appStore.currentScreen);
  let isOpen = $derived($appStore.isOpen); // Keep for template reactivity
  let settings = $derived($appStore.settings);
  let isCartReady = $derived($otpStore.isCartReady || false);
  let optimizedBuyNow = $derived(($otpStore.settings, isOptimizedBuyNowEnabled()));
  let buyNowError = $derived($otpStore.buyNowError);
  let isProceedingPayment = $derived($otpStore.isProceedingPayment === true);
  let cartLoadFailed = $derived($otpStore.cartLoadFailed === true);
  let hasOwnLoader = $derived(
    currentScreen === "processing" || $codOrderFlowStore.show === true,
  );

  // Screen the address flow (saved addresses / add form) was entered from
  let addressFlowOrigin = $state("phone");
  $effect(() => {
    if (currentScreen !== "address" && currentScreen !== "address-form") {
      addressFlowOrigin = currentScreen === "payment" ? "payment" : "phone";
    }
  });

  // Store info for ScreenHeader
  let storeLogoUrl = $state(null);
  let storeName = $state("");
  let storeTitle = $state("");
  /** @type {"wide" | "square" | ""} */
  let storeLogoType = $state("");

  const isTruthySetting = (value, defaultValue = true) => {
    if (value === true || value === 1 || value === "true" || value === "1")
      return true;
    if (value === false || value === 0 || value === "false" || value === "0")
      return false;
    return defaultValue;
  };

  // ---------------------------------------------------------------------------
  // Promo Banner Settings
  // ---------------------------------------------------------------------------
  const promoBannerShow = $derived(
    isTruthySetting(
      settings?.promoBannerShow ?? settings?.promo_banner_show,
      true, // Default to true if not set
    ),
  );

  const promoBannerText = $derived(
    settings?.promoBannerText ||
      settings?.promo_banner_text ||
      "Please complete this step before continuing.",
  );

  const promoBannerColor = $derived(
    settings?.promoBannerColor || settings?.promo_banner_color || "", // Empty = use default CSS color
  );

  const promoTextColor = $derived(
    settings?.promoTextColor || settings?.promo_text_color || "", // Empty = use default CSS color
  );

  const showOfferAndReward = $derived(
    isTruthySetting(
      settings?.showOfferAndReward ?? settings?.show_offer_and_reward,
      true,
    ),
  );

  const showUpsell = $derived(
    currentScreen === "payment" && !$codOrderFlowStore.show,
  );

  // Load store info
  async function loadStoreInfo() {
    if (!settings) return;

    const preV2Title = settings.preV2Title;
    const brandLogoUrl = settings.brandLogoUrl;

    // Format store name
    const shopDomain =
      typeof window !== "undefined"
        ? window.parent?.Shopify?.shop || window.Shopify?.shop
        : "";
    const rawName =
      preV2Title || shopDomain?.replace(".myshopify.com", "") || "Store";
    // Keep a full title for display (no "first letter" placeholder)
    storeTitle =
      (preV2Title || rawName || "Store").toString().trim() || "Store";
    // Keep a formatted/truncated name for alt/text fallbacks
    storeName = formatTitle(storeTitle, 30);

    if (brandLogoUrl) {
      try {
        const type = await checkImageAspectRatio(brandLogoUrl);
        storeLogoType = type === "Wide image" ? "wide" : "square";
        storeLogoUrl = brandLogoUrl;
      } catch (error) {
        console.warn("[MobileLayout] Failed to load store logo:", error);
        storeLogoUrl = null;
        storeLogoType = "";
      }
    } else {
      storeLogoUrl = null;
      storeLogoType = "";
    }
  }

  // Load store info when settings are available
  $effect(() => {
    if (settings) {
      loadStoreInfo();
    }
  });

  // Handle screen changes - sync with getCurrentStep when modal opens
  // Use store subscription to track ONLY isOpen changes, avoiding reactive loops
  let previousIsOpen = false;
  let unsubscribeIsOpen;

  // Use onMount to set up subscription that only tracks isOpen changes
  onMount(() => {
    let lastIsOpenValue = get(appStore).isOpen;

    unsubscribeIsOpen = appStore.subscribe((state) => {
      const currentIsOpen = state.isOpen;

      // CRITICAL: Only proceed if isOpen actually changed
      if (currentIsOpen === lastIsOpenValue) {
        return; // Store updated but isOpen didn't change - ignore
      }

      lastIsOpenValue = currentIsOpen;

      // Use untrack to read other values without creating reactive dependencies
      const currentSettings = state.settings;
      if (!currentSettings) {
        previousIsOpen = currentIsOpen;
        return;
      }

      // Only track modal open/close transitions
      if (currentIsOpen && !previousIsOpen) {
        if (state.currentScreen === "processing") {
          // Use untrack to prevent this update from triggering the effect
          untrack(() => {
            appStore.update((state) => ({
              ...state,
              currentScreen: "phone",
              previousScreen: null,
            }));
          });
        }

        // ALWAYS determine screen via getCurrentStep when modal opens
        // getCurrentStep() handles all step logic and screen mapping internally
        // Use untrack to prevent reactive dependencies
        getCurrentStep().catch((error) => {
          console.error("[MobileLayout] Error setting initial screen:", error);
        });
      }

      previousIsOpen = currentIsOpen;
    });

    return () => {
      if (unsubscribeIsOpen) {
        unsubscribeIsOpen();
      }
    };
  });

  let showCloseConfirm = $state(false);

  function handleClose() {
    if (onClose) {
      onClose();
    } else {
      actions.closeModal();
      try {
        if (typeof window.parent !== "undefined" && window.parent.postMessage) {
          postToParent("codk-close-modal");
        }
      } catch (error) {
        console.error(
          "[MobileLayout] ❌ Error sending message to parent:",
          error,
        );
      }
    }
  }

  function handleCloseClick() {
    showCloseConfirm = true;
  }

  // IFRAME HEIGHT DETECTION & COMMUNICATION (matching Modal.svelte)
  let modalCardElement = $state(null);
  let resizeObserver = $state(null);
  let heightUpdateTimeout = $state(null);
  let lastSentHeight = 0;
  const HEIGHT_TOLERANCE = 5;

  const sendHeightToParent = () => {
    if (!modalCardElement || !isOpen) return;

    try {
      const rawHeight = modalCardElement.scrollHeight;
      const height = Math.floor(rawHeight / 2) * 2;
      const isMobile = window.innerWidth <= 640;

      if (Math.abs(height - lastSentHeight) < HEIGHT_TOLERANCE) return;
      lastSentHeight = height;

      if (
        !isMobile &&
        typeof window.parent !== "undefined" &&
        window.parent.postMessage
      ) {
        postToParent({
            type: "codk-iframe-height",
            height: height,
            isMobile: false,
          });
      }
    } catch (error) {
      console.warn("[MobileLayout] ⚠️ Error sending height to parent:", error);
    }
  };

  // Set up ResizeObserver to detect content height changes
  // Use $effect to run after reactive updates
  let previousResizeIsOpen = false;
  let previousResizeElement = null;

  $effect(() => {
    const currentIsOpen = untrack(() => get(appStore).isOpen);
    const currentElement = modalCardElement;

    // CRITICAL: Only proceed if isOpen OR modalCardElement actually changed
    const isOpenChanged = currentIsOpen !== previousResizeIsOpen;
    const elementChanged = currentElement !== previousResizeElement;

    if (!isOpenChanged && !elementChanged) {
      return;
    }

    previousResizeIsOpen = currentIsOpen;
    previousResizeElement = currentElement;

    // Cleanup previous observer if it exists
    if (resizeObserver) {
      resizeObserver.disconnect();
      resizeObserver = null;
    }
    if (heightUpdateTimeout) {
      clearTimeout(heightUpdateTimeout);
      heightUpdateTimeout = null;
    }

    if (currentIsOpen && currentElement) {
      resizeObserver = new ResizeObserver(() => {
        if (heightUpdateTimeout) {
          clearTimeout(heightUpdateTimeout);
        }
        heightUpdateTimeout = setTimeout(() => {
          requestAnimationFrame(sendHeightToParent);
        }, 150);
      });

      resizeObserver.observe(currentElement);

      setTimeout(() => {
        sendHeightToParent();
      }, 200);
    }

    // Always return cleanup function
    return () => {
      if (resizeObserver) {
        resizeObserver.disconnect();
        resizeObserver = null;
      }
      if (heightUpdateTimeout) {
        clearTimeout(heightUpdateTimeout);
        heightUpdateTimeout = null;
      }
    };
  });

  // Handle messages from parent (Liquid file)
  if (typeof window !== "undefined") {
    window.addEventListener("message", (event) => {
      if (event.data === "codk-close-modal") {
        handleClose();
      }
    });
  }
</script>

{#if isOpen}
  <!-- Use existing Modal CSS classes - don't break existing structure -->
  <div class="modal-overlay">
    <div class="modal-card animate-modal-in" bind:this={modalCardElement}>
      <div class="modal-content">
        <ScreenLayout>
          {#if currentScreen !== "processing" && !$codOrderFlowStore.show}
            <ScreenHeader
              {storeLogoUrl}
              {storeName}
              {storeTitle}
              {storeLogoType}
              backAction={handleCloseClick}
            />
            {#if promoBannerShow}
              <div class="header-promo-banner">
                <PromoBanner
                  text={promoBannerText}
                  backgroundColor={promoBannerColor}
                  textColor={promoTextColor}
                  variant="default"
                />
              </div>
            {/if}
          {/if}

          <ScreenContent
            fullBleed={currentScreen === "processing" ||
              $codOrderFlowStore.show}
          >
            <!-- OrderSummaryCard must stay mounted to initialize cart -->
            <OrderSummaryCard
              showDisplay={currentScreen !== "processing" &&
                !$codOrderFlowStore.show}
            />
            <OffersRewardsSection
              showDisplay={showOfferAndReward &&
                currentScreen !== "processing" &&
                !$codOrderFlowStore.show}
            />
            <FreeGiftSection />
            <UpsellSection showDisplay={showUpsell} />

            {#if $codOrderFlowStore.show}
              <!-- Full-screen COD order processing (like verified/processing page) -->
              <div class="flex flex-1 flex-col min-h-0 w-full">
                <OrderProcessingFlow />
              </div>
            {:else}
              {#key currentScreen}
                {#if currentScreen === "phone" || !currentScreen}
                  <PhoneInput />
                {:else if currentScreen === "otp"}
                  <!-- OTP verification is a full screen (like phone/payment),
                       sharing the header + order summary + coupons shell. -->
                  <OtpVerificationContent />
                {:else if currentScreen === "address"}
                  <!-- Show originating screen in background and address selection in BottomSlider -->
                  {#if addressFlowOrigin === "payment"}
                    <PaymentScreen />
                  {:else}
                    <PhoneInput />
                  {/if}
                  <Sheet
                    open={true}
                    title={T("saved_addresses_title")}
                    closeLabel="Close addresses"
                    headerBorder={false}
                    headerBanner={true}
                    headerBackground={promoBannerColor}
                    dismissOnBackdrop={false}
                    dismiss={() => {
                      actions.setScreen(addressFlowOrigin);
                    }}
                  >
                    <Card variant="flat" padding="none" attach="bottom">
                      <AddressSelectionContent />
                    </Card>
                  </Sheet>
                {:else if currentScreen === "address-form"}
                  <Sheet
                    open={true}
                    title={$otpStore.isEditAddress ? "Edit address" : "Add address"}
                    closeLabel="Close address form"
                    headerBorder={false}
                    headerBanner={true}
                    headerBackground={promoBannerColor}
                    showBackButton={true}
                    showCloseButton={true}
                    goBack={() => actions.setScreen(addressFlowOrigin)}
                    dismissOnBackdrop={false}
                    dismiss={() => actions.setScreen(addressFlowOrigin)}
                  >
                    <Card variant="flat" padding="none" attach="bottom">
                      <AddressFormContent />
                    </Card>
                  </Sheet>
                {:else if currentScreen === "payment"}
                  <PaymentScreen />
                {:else if currentScreen === "processing"}
                  <!-- Show payment screen in background and processing in BottomSlider -->
                  <PaymentProcessingContent />
                {:else}
                  <div class="error-state">
                    <p>Unknown screen: {currentScreen || "undefined"}</p>
                    <!-- svelte-ignore event_directive_deprecated -->
                    <button
                      onclick={() => {
                        actions.setScreen("phone");
                      }}
                    >
                      {T("go_to_phone_screen")}
                    </button>
                  </div>
                {/if}
              {/key}
            {/if}
          </ScreenContent>
        </ScreenLayout>
      </div>

      {#if buyNowError}
        <div class="cart-loading-overlay" aria-hidden="false">
          <div
            style="
              width: 100%;
              height: 100%;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              text-align: center;
              padding: 40px 24px;
              gap: 14px;
              background: #fff;
            "
          >
            <div style="font-size: 32px; line-height: 1;">⚠️</div>
            <div style="font-size: 18px; font-weight: 600; color: #1f1f1f;">
              {buyNowError.code === "OUT_OF_STOCK"
                ? "This product is out of stock"
                : "We couldn't add this product to your cart"}
            </div>
            <div style="font-size: 14px; color: #5c5f62; max-width: 360px; line-height: 1.4;">
              {buyNowError.message || "Please pick another product or come back later."}
            </div>
            <button
              type="button"
              on:click={handleClose}
              style="
                margin-top: 8px;
                padding: 10px 22px;
                background: #000;
                color: #fff;
                border: none;
                border-radius: 6px;
                cursor: pointer;
                font-size: 14px;
                font-weight: 600;
              "
            >
              {T("close")}
            </button>
          </div>
        </div>
      {:else if !hasOwnLoader && (cartLoadFailed || isProceedingPayment || (optimizedBuyNow ? false : !isCartReady))}
        <!-- Optimized: never show the full-screen loader — the screens render
             skeletons (order summary + discounts + payment) instead. Off:
             original full-screen loader while the cart is being fetched. -->
        <div class="cart-loading-overlay" aria-hidden="false">
          <CartLoadingScreen />
        </div>
      {/if}

      <Sheet
        open={showCloseConfirm}
        title={T("exit_confirm_title")}
        closeLabel="Close"
        headerBorder={false}
        bodyPadded={false}
        dismiss={() => {
          showCloseConfirm = false;
        }}
      >
        <CloseConfirmSlider
          on:close={() => {
            showCloseConfirm = false;
          }}
          on:confirm={async () => {
            showCloseConfirm = false;
            const cartItems = get(otpStore)?.currentCartData?.items;
            if (cartItems?.length > 0) {
              try {
                await updateCartDetailsForPreCreation(cartItems);
              } catch (err) {
                console.warn("[MobileLayout] update_cart_details failed:", err);
              }
            }
            handleClose();
          }}
        />
      </Sheet>

      <CelebrationDialog />
    </div>
  </div>
{/if}

<style>
  .cart-loading-overlay {
    position: absolute;
    inset: 0;
    z-index: 2147483648;
    pointer-events: auto;
    display: flex;
    background: var(--surface-page); /* Fully opaque overlay */
    border-radius: inherit; /* Match modal-card corners */
    overflow: hidden;
  }
</style>

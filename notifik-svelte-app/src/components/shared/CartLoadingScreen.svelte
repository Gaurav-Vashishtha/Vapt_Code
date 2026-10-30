<script>
  /**
   * CartLoadingScreen - Full/progressive loading screen for cart initialization.
   * Shows store logo (if available) with a subtle premium animation.
   * Fetches logo URL and type from app store internally - no need to pass as props.
   */
  import { appStore } from "../../stores/buttonManager.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { checkImageAspectRatio } from "../../utils/helpers.js";
  import CodKingLoadingScreen from "./CodKingLoadingScreen.svelte";
  import { createTranslator } from "../../utils/uiCustomization.js";
  import otpStore from "../../stores/otpStore.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(
    createTranslator($settingsStore || $appStore?.settings),
  );

  let { text = "" } = $props();

  let loaderText = $derived(
    text ||
      ($otpStore?.cartLoadFailed
        ? T("cart_loader_error")
        : $otpStore?.isProceedingPayment
          ? T("cart_loader_proceeding")
          : T("cart_loader_progress")),
  );

  let storeLogoUrl = $state(null);
  /** @type {"wide" | "square" | ""} */
  let storeLogoType = $state("");

  let codkingLoadingEnabled = $derived(
    $appStore?.settings?.codkingLoading === true ||
      $appStore?.settings?.codkingLoading === "true" ||
      $appStore?.settings?.codking_loading === true ||
      $appStore?.settings?.codking_loading === "true",
  );

  $effect(() => {
    const settings = $appStore?.settings;
    const brandLogoUrl =
      settings?.brandLogoUrl || settings?.brand_logo_url || null;
    if (!brandLogoUrl) {
      storeLogoUrl = null;
      storeLogoType = "";
      return;
    }
    storeLogoUrl = brandLogoUrl;
    storeLogoType = "";
    checkImageAspectRatio(brandLogoUrl)
      .then((type) => {
        storeLogoType = type === "Wide image" ? "wide" : "square";
      })
      .catch(() => {
        storeLogoType = "square";
      });
  });
</script>

{#if true}
  <CodKingLoadingScreen text={loaderText} />
{:else}
<div class="codk-loading-screen" role="status" aria-live="polite">
  <div class="codk-loading-content">
    {#if storeLogoUrl}
      <div
        class="codk-logo-wrap"
        class:codk-logo-wrap--wide={storeLogoType === "wide"}
        class:codk-logo-wrap--square={storeLogoType === "square" ||
          !storeLogoType}
        aria-hidden="true"
      >
        <div class="codk-logo-ring"></div>
        <img
          class="codk-logo"
          class:codk-logo--wide={storeLogoType === "wide"}
          class:codk-logo--square={storeLogoType === "square" || !storeLogoType}
          src={storeLogoUrl}
          alt="Store logo"
          loading="eager"
        />
      </div>
    {:else}
      <div class="codk-fallback-mark" aria-hidden="true">{T("cart_loader_fallback")}</div>
    {/if}

    <div class="codk-loading-text">
      <div class="codk-loading-title">{T("cart_loader_title")}</div>
      <div class="codk-loading-subtitle">{T("cart_loader_subtitle")}</div>
    </div>

    <div class="codk-dots" aria-hidden="true">
      <span class="dot"></span>
      <span class="dot"></span>
      <span class="dot"></span>
    </div>
  </div>
</div>
{/if}

<style>
  .codk-loading-screen {
    width: 100%;
    height: 100%;
    min-height: 100%;
    flex: 1 1 auto;
    align-self: stretch;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px 16px;
    /* Opaque background so underlying UI never shows through */
    background: var(--surface-page);
  }

  .codk-loading-content {
    width: min(520px, 100%);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
    animation: codk-fade-in 260ms ease-out both;
  }

  .codk-logo-wrap {
    width: 92px;
    height: 92px;
    position: relative;
    display: grid;
    place-items: center;
    animation: codk-float 1400ms ease-in-out infinite;
  }

  /* Horizontal/wide logos: larger container so logo is readable */
  .codk-logo-wrap--wide {
    width: min(260px, 90vw);
    height: 72px;
    min-height: 72px;
  }

  .codk-logo {
    width: 78px;
    height: 78px;
    object-fit: contain;
    border-radius: 14px;
    background: transparent;
    box-shadow: 0 8px 22px rgba(0, 0, 0, 0);
    padding: 10px;
  }

  /* Horizontal/wide logos: allow logo to use full width, fixed height */
  .codk-logo--wide {
    width: 100%;
    max-width: 240px;
    height: 56px;
    padding: 8px 16px;
  }

  .codk-logo-ring {
    position: absolute;
    inset: -8px;
    border-radius: 22px;
    background: radial-gradient(
      circle at 50% 50%,
      var(--loader-ring),
      transparent 62%
    );
    filter: blur(0.2px);
    animation: codk-ring 1200ms ease-in-out infinite;
  }

  .codk-logo-wrap--wide .codk-logo-ring {
    border-radius: 20px;
  }

  .codk-fallback-mark {
    width: 92px;
    height: 92px;
    border-radius: 16px;
    display: grid;
    place-items: center;
    color: #2f2f2f;
    font-family: var(--font-family-base);
    font-weight: 700;
    font-size: 13px;
    letter-spacing: 0.2px;
    background: linear-gradient(180deg, #ffffff, #f8fafc);
    border: 1px solid var(--hairline);
    box-shadow: 0 10px 28px rgba(17, 24, 39, 0.1);
    animation: codk-float 1400ms ease-in-out infinite;
  }

  .codk-loading-text {
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .codk-loading-title {
    color: #2f2f2f;
    font-family: var(--font-family-base);
    font-size: 14px;
    line-height: 20px;
    font-weight: 700;
  }

  .codk-loading-subtitle {
    color: #6b7280;
    font-family: var(--font-family-base);
    font-size: 12px;
    line-height: 18px;
    font-weight: 500;
  }

  .codk-dots {
    display: flex;
    gap: 6px;
    align-items: center;
    justify-content: center;
    margin-top: 2px;
  }

  .dot {
    width: 7px;
    height: 7px;
    border-radius: 999px;
    background: var(--loader-dot);
    animation: codk-dot 900ms ease-in-out infinite;
  }

  .dot:nth-child(2) {
    animation-delay: 120ms;
  }

  .dot:nth-child(3) {
    animation-delay: 240ms;
  }

  @keyframes codk-fade-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes codk-float {
    0%,
    100% {
      transform: translateY(0);
    }
    50% {
      transform: translateY(-3px);
    }
  }

  @keyframes codk-ring {
    0%,
    100% {
      transform: scale(0.98);
      opacity: 0.55;
    }
    50% {
      transform: scale(1.03);
      opacity: 0.85;
    }
  }

  @keyframes codk-dot {
    0%,
    100% {
      transform: translateY(0);
      opacity: 0.35;
    }
    50% {
      transform: translateY(-3px);
      opacity: 0.9;
    }
  }
</style>

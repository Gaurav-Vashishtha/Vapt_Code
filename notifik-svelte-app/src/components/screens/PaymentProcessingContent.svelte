<script>
  import { get } from "svelte/store";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { onMount, onDestroy } from "svelte";
  import { appStore } from "../../stores/buttonManager.js";
  import otpStore from "../../stores/otpStore.js";
  import { redirectOtpStoreToCheckout } from "../../services/redirectOtpStoreToCheckoutService.js";
  import CodKingLoadingScreen from "../shared/CodKingLoadingScreen.svelte";
  import { createTranslator } from "../../utils/uiCustomization.js";

  const storeState = get(appStore);
  const settings = storeState?.settings;
  const storeLogoUrl =
    settings?.brandLogoUrl || settings?.brand_logo_url || null;
  // Merchant copy resolver (ui_customization → redirectText setting → default).
  // Reactive so the copy follows a settings change instead of freezing at mount.
  $: resolvedSettings = $settingsStore || settings;
  $: T = createTranslator(resolvedSettings);
  $: verifiedText = T("redirect_subtitle");
  $: redirectLoaderText = T("redirect_title");
  const codkingLoadingEnabled =
    settings?.codkingLoading === true ||
    settings?.codkingLoading === "true" ||
    settings?.codking_loading === true ||
    settings?.codking_loading === "true";

  let unsubscribe;
  let isRedirecting = false;

  const handleRedirect = async (state) => {
    if (isRedirecting) return;
    const isBuyNow = state.isBuyNowButton;
    const isCartReady = state.isCartReady;

    if (!isBuyNow || (isBuyNow && isCartReady)) {
      isRedirecting = true;

      await redirectOtpStoreToCheckout();
    }
  };

  onMount(() => {
    handleRedirect(get(otpStore));
    unsubscribe = otpStore.subscribe((state) => {
      if (!isRedirecting) {
        handleRedirect(state);
      }
    });
  });

  onDestroy(() => {
    if (unsubscribe) {
      unsubscribe();
    }
  });
</script>

{#if true}
  <CodKingLoadingScreen text={redirectLoaderText} />
{:else}
<div class="codk-processing-screen" role="status" aria-live="polite">
  <div class="codk-processing-card">
    <div class="codk-processing-mark" aria-hidden="true">
      <svg viewBox="0 0 24 24" width="28" height="28" class="codk-tick-svg">
        <path
          class="codk-tick-path"
          d="M20 6L9 17l-5-5"
          fill="none"
          stroke="currentColor"
          stroke-width="2.6"
          stroke-linecap="round"
          stroke-linejoin="round"
          pathLength="1"
        />
      </svg>
    </div>

    <div class="codk-processing-text">
      <div class="codk-processing-title">{T("redirect_title")}</div>
      <div class="codk-processing-subtitle">{verifiedText}</div>
    </div>

    <div class="codk-processing-progress" aria-hidden="true">
      <div class="codk-processing-progress-bar"></div>
    </div>
  </div>
</div>
{/if}

<style>
  .codk-processing-screen {
    width: 100%;
    height: 100%;
    min-height: 100%;
    flex: 1 1 auto;
    align-self: stretch;
    display: flex;
    align-items: center;
    justify-content: center;
    /* padding: 24px 16px; */
    padding: 0px;
    background: var(--surface-page);
  }

  .codk-processing-card {
    width: min(520px, 100%);
    background: rgba(255, 255, 255, 0.9);
    border: 1px solid var(--hairline);
    border-radius: 16px;
    box-shadow:
      0 18px 50px rgba(15, 23, 42, 0.12),
      0 1px 0 rgba(17, 24, 39, 0.03);
    padding: 18px 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    margin: 10px;
    gap: 12px;
    backdrop-filter: blur(6px);
    animation: codk-processing-in 220ms ease-out both;
  }

  .codk-processing-mark {
    width: 70px;
    height: 70px;
    border-radius: 999px;
    display: grid;
    place-items: center;
    color: #0b7a2a;
    background: radial-gradient(
        circle at 30% 20%,
        rgba(34, 197, 94, 0.22),
        transparent 55%
      ),
      linear-gradient(180deg, #f0fff4, #ffffff);
    border: 1px solid rgba(34, 197, 94, 0.22);
    box-shadow:
      0 16px 30px rgba(34, 197, 94, 0.12),
      inset 0 1px 0 rgba(255, 255, 255, 0.7);
    animation: codk-mark-scale-in 0.45s cubic-bezier(0.34, 1.56, 0.64, 1) both;
  }

  .codk-tick-path {
    stroke-dasharray: 1;
    stroke-dashoffset: 1;
    animation: codk-tick-draw 0.5s cubic-bezier(0.34, 1.2, 0.64, 1) 0.15s forwards;
  }

  .codk-processing-text {
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .codk-processing-title {
    color: #2f2f2f;
    font-family: var(--font-family-base);
    font-size: 14px;
    line-height: 20px;
    font-weight: 700;
  }

  .codk-processing-subtitle {
    color: #6b7280;
    font-family: var(--font-family-base);
    font-size: 12px;
    line-height: 18px;
    font-weight: 500;
  }

  .codk-processing-progress {
    width: min(320px, 100%);
    height: 10px;
    border-radius: 999px;
    background: rgba(17, 24, 39, 0.06);
    overflow: hidden;
  }

  .codk-processing-progress-bar {
    height: 100%;
    width: 45%;
    border-radius: 999px;
    background: linear-gradient(
      90deg,
      rgba(34, 197, 94, 0.18),
      rgba(34, 197, 94, 0.55),
      rgba(59, 130, 246, 0.45)
    );
    animation: codk-processing-bar 1.1s ease-in-out infinite;
  }

  @keyframes codk-processing-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes codk-mark-scale-in {
    from {
      opacity: 0;
      transform: scale(0.6);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @keyframes codk-tick-draw {
    to {
      stroke-dashoffset: 0;
    }
  }

  @keyframes codk-processing-bar {
    0% {
      transform: translateX(-30%);
      opacity: 0.65;
    }
    50% {
      opacity: 1;
    }
    100% {
      transform: translateX(155%);
      opacity: 0.75;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .codk-processing-card {
      animation: none !important;
    }
    .codk-processing-mark {
      animation: none !important;
    }
    .codk-tick-path {
      animation: none !important;
      stroke-dashoffset: 0;
    }
    .codk-processing-progress-bar {
      animation: none !important;
      width: 65%;
    }
  }
</style>

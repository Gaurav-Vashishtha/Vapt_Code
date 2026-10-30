<script>
  /**
   * CheckoutLoader - Premium loader for checkout modal (Stripe/Shopify-style).
   * Shown after Buy Now / before checkout UI. Reinforces brand, reduces perceived wait.
   */
  import { appStore } from "../../stores/buttonManager.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { formatTitle } from "../../utils/helpers.js";
  import { createTranslator } from "../../utils/uiCustomization.js";

  let storeName = $state("");
  // Merchant copy resolver (ui_customization → legacy setting → default)
  let T = $derived(
    createTranslator($settingsStore || $appStore?.settings),
  );

  $effect(() => {
    const settings = $appStore?.settings;
    if (!settings) {
      storeName = "Store";
      return;
    }
    const preV2Title = settings.preV2Title || settings.pre_v2_title;
    const shopDomain =
      typeof window !== "undefined"
        ? window.parent?.Shopify?.shop || window?.Shopify?.shop
        : "";
    const raw =
      preV2Title ||
      (shopDomain ? String(shopDomain).replace(".myshopify.com", "") : "") ||
      "Store";
    storeName = formatTitle(String(raw).trim() || "Store", 28);
  });
</script>

<div
  class="checkout-loader"
  role="status"
  aria-live="polite"
  aria-label={T("loader_title")}
>
  <div class="checkout-loader-card">
    <!-- Brand badge: soft gradient pill, subtle glass -->
    <div class="checkout-loader-badge">
      <span class="checkout-loader-badge-text">{storeName}</span>
    </div>

    <h2 class="checkout-loader-title">{T("loader_title")}</h2>
    <p class="checkout-loader-subtitle">{T("loader_subtitle")}</p>

    <!-- Sequential animated dots (Tailwind animate-dot-step + delay) -->
    <div class="flex items-center justify-center gap-2 mt-1" aria-hidden="true">
      <span class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-dot-step"></span>
      <span class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-dot-step [animation-delay:160ms]"></span>
      <span class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-dot-step [animation-delay:320ms]"></span>
    </div>
  </div>

  <!-- Optional: faint skeleton placeholders for perceived speed -->
  <div class="checkout-loader-skeletons">
    <div class="checkout-skeleton checkout-skeleton--order"></div>
    <div class="checkout-skeleton checkout-skeleton--address"></div>
    <div class="checkout-skeleton checkout-skeleton--payment"></div>
  </div>
</div>

<style>
  .checkout-loader {
    width: 100%;
    min-height: 100%;
    flex: 1 1 auto;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 24px 16px;
    gap: 24px;
    background: var(--surface-page);
    animation: checkout-loader-fade-in 400ms ease-out both;
  }

  .checkout-loader-card {
    width: min(400px, 100%);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 24px 20px;
    background: #ffffff;
    border-radius: 16px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06), 0 4px 12px rgba(0, 0, 0, 0.04);
    border: 1px solid var(--hairline);
  }

  /* Brand badge: rounded pill, soft gradient, subtle blur */
  .checkout-loader-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 6px 16px;
    border-radius: 999px;
    background: linear-gradient(
      135deg,
      rgba(241, 245, 249, 0.95) 0%,
      rgba(226, 232, 240, 0.9) 50%,
      rgba(248, 250, 252, 0.95) 100%
    );
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    border: 1px solid rgba(255, 255, 255, 0.8);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
    animation: checkout-loader-badge-pulse 2.2s ease-in-out infinite;
  }

  .checkout-loader-badge-text {
    font-family: var(--font-family-base);
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.02em;
    color: #334155;
  }

  .checkout-loader-title {
    margin: 0;
    font-family: var(--font-family-base);
    font-size: 15px;
    font-weight: 500;
    line-height: 1.35;
    color: #0f172a;
    text-align: center;
  }

  .checkout-loader-subtitle {
    margin: 0;
    font-family: var(--font-family-base);
    font-size: 12px;
    font-weight: 400;
    line-height: 1.4;
    color: #64748b;
    text-align: center;
  }


  /* Optional skeleton strip */
  .checkout-loader-skeletons {
    width: min(400px, 100%);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .checkout-skeleton {
    height: 48px;
    border-radius: 12px;
    background: linear-gradient(
      90deg,
      rgba(226, 232, 240, 0.5) 0%,
      rgba(241, 245, 249, 0.6) 50%,
      rgba(226, 232, 240, 0.5) 100%
    );
    background-size: 200% 100%;
    animation: checkout-skeleton-shine 1.8s ease-in-out infinite;
  }

  .checkout-skeleton--order {
    height: 56px;
  }
  .checkout-skeleton--address {
    height: 52px;
  }
  .checkout-skeleton--payment {
    height: 64px;
  }

  @keyframes checkout-loader-fade-in {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  @keyframes checkout-loader-badge-pulse {
    0%,
    100% {
      opacity: 1;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
    }
    50% {
      opacity: 0.92;
      box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
    }
  }

  @keyframes checkout-skeleton-shine {
    0% {
      background-position: 200% 0;
    }
    100% {
      background-position: -200% 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .checkout-loader,
    .checkout-loader-badge,
    .checkout-skeleton {
      animation: none;
    }
  }
</style>

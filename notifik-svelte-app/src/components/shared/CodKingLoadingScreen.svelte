<script>
  import { appStore } from "../../stores/buttonManager.js";
  import { settingsStore } from "../../stores/settingsStore.js";

  let { text = "" } = $props();

  const CODK_LOGO =
    "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CKlogoicon-1200px_1.png?v=1762758841";

  // A merchant-supplied logo can 404; fall back to the COD King mark if it does.
  let brandLogoFailed = $state(false);

  let settings = $derived(
    $settingsStore || $appStore?.settings || null,
  );

  let showBranding = $derived.by(() => {
    const value = settings?.preShowBranding ?? settings?.pre_show_branding;
    return value !== false && value !== "false" && value !== null && value !== undefined;
  });

  let brandLogoUrl = $derived.by(() => {
    if (brandLogoFailed || !showBranding) return CODK_LOGO;
    return (settings?.brandLogoUrl || settings?.brand_logo_url || CODK_LOGO)
      .toString()
      .trim();
  });

  let logoSrc = settings?.brandLogoUrl || CODK_LOGO
  let isCodkLogo = $derived(logoSrc === CODK_LOGO);
</script>

<div class="ck-load" role="status" aria-live="polite">
  {#if text}
    <p class="ck-load__text">{text}</p>
  {/if}

  <div class="ck-load__spinner" aria-hidden="true">
    <span class="ck-load__ring">
      <span class="ck-load__circle"></span>
      <span class="ck-load__dot"></span>
    </span>
    {#if logoSrc}
      <span class="ck-load__logo">
        <img
          src={logoSrc}
          alt={isCodkLogo ? "COD King" : ""}
          class:ck-load__logo--monogram={isCodkLogo}
          class:ck-load__logo--brand={!isCodkLogo}
          loading="eager"
          onerror={() => (brandLogoFailed = true)}
        />
      </span>
    {/if}
  </div>
</div>

<style>
  .ck-load {
    width: 100%;
    height: 100%;
    min-height: 100%;
    flex: 1 1 auto;
    align-self: stretch;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 20px;
    padding: 32px;
    background: var(--surface-page);
    animation: ck-load-fade-in 260ms ease-out both;
  }

  .ck-load__text {
    margin: 0;
    color: #4e596f;
    font-size: 16px;
    line-height: 22px;
    font-weight: 500;
    text-align: center;
  }

  .ck-load__spinner {
    position: relative;
    width: 74px;
    height: 74px;
    margin: 2px 0;
  }

  .ck-load__ring {
    position: absolute;
    inset: 0;
    animation: ck-load-spin 0.7s linear infinite;
  }

  .ck-load__circle {
    position: absolute;
    inset: 0;
    border-radius: 50%;
    border: 8px solid var(--loader-ring);
  }

  .ck-load__dot {
    position: absolute;
    top: 32px;
    left: 0;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--loader-dot);
    opacity: 0.9;
  }

  .ck-load__logo {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .ck-load__logo img {
    width: 36px;
    height: 36px;
    object-fit: contain;
    display: block;
  }

  .ck-load__logo img.ck-load__logo--monogram {
    filter: grayscale(1) saturate(0) brightness(0.65) contrast(1.2);
  }

  .ck-load__logo img.ck-load__logo--brand {
    width: 40px;
    height: 32px;
  }

  @keyframes ck-load-fade-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes ck-load-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .ck-load {
      animation: none;
    }
    .ck-load__ring {
      animation: none;
    }
  }
</style>

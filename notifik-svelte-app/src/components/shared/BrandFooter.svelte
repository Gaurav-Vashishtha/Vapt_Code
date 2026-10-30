<script>
  import { getSettings } from "../../services/sessionService.js";
  import { appStore } from "../../stores/buttonManager.js";
  import {
    createTranslator,
    shouldShowTrustBadges,
    isFooterBrandingHidden,
    getLegalLinks,
  } from "../../utils/uiCustomization.js";
  import TrustBadges from "./TrustBadges.svelte";
  /**
   * BrandFooter - trust badges + single-line legal + brand footer.
   * With the brand mark: T&C | Privacy Policy left, "{logo} COD King" right.
   * Without it: T&C left, Privacy Policy right. The legal links always render.
   * @component
   */
  export let termsUrl =
    "https://codking.notion.site/Terms-and-Conditions-COD-King-1a96e71a63f980358f6fe23c3c96485c";
  export let privacyUrl =
    "https://codking.notion.site/Privacy-Policy-COD-King-1ab6e71a63f980fb882df2e6a7173576";
  export let logoUrl =
    "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CKlogoicon-1200px_1.png?v=1762758841";
  export let brandName = "COD King";

  $: settings = getSettings() || $appStore.settings;
  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator(settings);
  $: showTrustBadges = shouldShowTrustBadges(settings);
  $: showBrandMark =
    (settings?.preShowBranding === true ||
      settings?.preShowBranding === "true" ||
      settings?.pre_show_branding === true ||
      settings?.pre_show_branding === "true") &&
    !isFooterBrandingHidden(settings);
  $: links = getLegalLinks(settings, { termsUrl, privacyUrl });
</script>

{#if showTrustBadges}
  <TrustBadges />
{/if}

<div class="brand-footer" class:brand-footer--no-brand={!showBrandMark}>
  <div class="brand-footer__links">
    <a href={links.termsUrl} target="_blank" rel="noreferrer">
      {showBrandMark ? T("legal_terms") : T("legal_terms_full")}
    </a>
    {#if showBrandMark}
      <span class="brand-footer__sep" aria-hidden="true">|</span>
    {/if}
    <a href={links.privacyUrl} target="_blank" rel="noreferrer">{T("legal_privacy")}</a>
  </div>
  {#if showBrandMark}
    <a target="_blank" href="https://codking.tech/landing/" class="brand-footer__powered">
      <img class="brand-footer__logo" src={logoUrl} alt={brandName} />
      <span class="brand-footer__brand">{brandName}</span>
    </a>
  {/if}
</div>

<style>
  .brand-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    width: 100%;
    padding: 8px 0 4px;
    font-family: var(--font-family-base);
    font-weight: 500;
    font-size: var(--font-size-xs);
    line-height: 16px;
    color: #3f3c3c;
  }

  .brand-footer__links {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }

  .brand-footer--no-brand .brand-footer__links {
    width: 100%;
    justify-content: space-between;
  }

  .brand-footer__links a {
    color: #4e596f;
    text-decoration: none;
  }

  .brand-footer__links a:hover {
    color: var(--color-text-primary);
  }

  .brand-footer__sep {
    color: #4e596f;
    opacity: 0.45;
  }

  .brand-footer__powered {
    display: flex;
    align-items: center;
    gap: 5px;
    flex-shrink: 0;
    color: #4e596f;
  }

  .brand-footer__logo {
    width: 15px;
    height: 15px;
    object-fit: contain;
    filter: grayscale(1) saturate(0) brightness(0.65) contrast(1.2);
  }

  .brand-footer__brand {
    font-weight: var(--font-weight-semibold);
    color: #4e596f;
  }
</style>

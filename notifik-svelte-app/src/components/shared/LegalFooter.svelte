<script>
  /**
   * LegalFooter - Reusable legal footer component with T&C, Privacy Policy, and Security section
   * @component
   */
  import "../../styles/components/shared/LegalFooter.css";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { appStore } from "../../stores/buttonManager.js";
  import {
    createTranslator,
    getLegalLinks,
    isFooterBrandingHidden,
  } from "../../utils/uiCustomization.js";

  let {
    termsUrl = "https://codking.notion.site/Terms-and-Conditions-COD-King-1a96e71a63f980358f6fe23c3c96485c",
    privacyUrl = "https://codking.notion.site/Privacy-Policy-COD-King-1ab6e71a63f980fb882df2e6a7173576",
    // Rendered in monochrome via CSS (to match React + Shopify branding guidelines)
    logoUrl = "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CKlogoicon-1200px_1.png?v=1762758841"
  } = $props();

  // Check from session first, fallback to appStore
  let settings = $derived($settingsStore || $appStore.settings);
  let T = $derived(createTranslator(settings));
  let showBrandMark = $derived(
    (settings?.preShowBranding === true ||
      settings?.preShowBranding === "true" ||
      settings?.pre_show_branding === true ||
      settings?.pre_show_branding === "true") &&
      !isFooterBrandingHidden(settings)
  );
  let links = $derived(getLegalLinks(settings, { termsUrl, privacyUrl }));
</script>

<div class="legal-footer">
  <div
    class="legal-footer__content"
    class:legal-footer__content--no-brand={!showBrandMark}
  >
    {#if showBrandMark}
      <span class="legal-footer__text">{T("legal_prefix")}</span>
    {/if}
    <a
      href={links.termsUrl}
      target="_blank"
      class="legal-footer__link legal-footer__link--terms"
      rel="noopener noreferrer"
    >
      <span class="legal-footer__text">
        {showBrandMark ? T("legal_terms") : T("legal_terms_full")}
      </span>
    </a>
    {#if showBrandMark}
      <div class="legal-footer__separator-wrapper">
        <div class="legal-footer__separator"></div>
      </div>
    {/if}
    <a
      href={links.privacyUrl}
      target="_blank"
      class="legal-footer__link legal-footer__link--privacy"
      rel="noopener noreferrer"
    >
      <span class="legal-footer__text">{T("legal_privacy")}</span>
    </a>
    {#if showBrandMark}
      <div class="legal-footer__secured">
        <div class="legal-footer__logo-container">
          <img
            src={logoUrl}
            alt="COD King"
            class="legal-footer__logo-image legal-footer__logo-image--mono"
          />
          <span class="legal-footer__logo-text">COD King</span>
        </div>
      </div>
    {/if}
  </div>
</div>

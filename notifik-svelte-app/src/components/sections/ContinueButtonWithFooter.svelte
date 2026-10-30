<script>
  import "../../styles/components/sections/ContinueButtonWithFooter.css";
  import "../../styles/components/sections/ContinueButtonWithFooter.desktop.css";
  import LegalFooter from "../shared/LegalFooter.svelte";

  export let buttonText = "Continue";
  export let buttonDisabled = false;
  export let buttonLoading = false;
  export let onButtonClick = null;

  export let checkboxChecked = false;
  export let checkboxLabel = "Send me order updates & offers";
  export let onCheckboxChange = null;

  export let termsUrl =
    "https://codking.notion.site/Terms-and-Conditions-COD-King-1a96e71a63f980358f6fe23c3c96485c";
  export let privacyUrl =
    "https://codking.notion.site/Privacy-Policy-COD-King-1ab6e71a63f980fb882df2e6a7173576";

  export let logoUrl =
    "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CKlogoicon-1200px_1.png?v=1762758841";

  function handleButtonClick() {
    if (!buttonDisabled && !buttonLoading && onButtonClick) {
      onButtonClick();
    }
  }

  function handleCheckboxChange(e) {
    checkboxChecked = e.target.checked;
    if (onCheckboxChange) {
      onCheckboxChange(checkboxChecked);
    }
  }
</script>

<div class="continue-button-footer-container">
  <div class="cta-section">
    <div class="button-wrapper">
      <button
        class="continue-button hover:opacity-90 active:opacity-80"
        class:loading={buttonLoading}
        disabled={buttonDisabled || buttonLoading}
        on:click={handleButtonClick}
      >
        {#if buttonLoading}
          <span class="spinner"></span>
        {/if}
        <span class="button-text">{buttonText}</span>
      </button>
    </div>

    <!-- <div class="checkbox-wrapper">
      <input
        type="checkbox"
        class="checkbox-input"
        checked={checkboxChecked}
        on:change={handleCheckboxChange}
      />
      <span class="checkbox-label">{checkboxLabel}</span>
    </div> -->
  </div>

  <LegalFooter {termsUrl} {privacyUrl} {logoUrl} />
</div>

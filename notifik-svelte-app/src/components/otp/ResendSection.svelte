<script>
  import { createEventDispatcher } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import "../../styles/components/otp/ResendSection.css";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  export let canResend = false;
  export let disabled = false;
  export let showWhatsapp = true;

  const dispatch = createEventDispatcher();

  function handleSmsResend() {
    if (!disabled && canResend) {
      dispatch("smsResend");
    }
  }

  function handleWhatsappResend() {
    if (!disabled && canResend) {
      dispatch("whatsappResend");
    }
  }
</script>

<div class="resend-section">
  <div class="resend-options">
    <span class="resend-label">{T("otp_resend_via")}</span>
    <button
      class="resend-chip resend-border sms-chip"
      style="border-radius: 6px !important;"
      disabled={!canResend || disabled}
      on:click={handleSmsResend}
    >
      <span class="resend-chip-text">{T("otp_channel_sms")}</span>
    </button>
    {#if showWhatsapp}
      <span class="resend-or">OR</span>
      <button
        class="resend-chip resend-border whatsapp-chip"
        disabled={!canResend || disabled}
        style="border-radius: 6px !important;"
        on:click={handleWhatsappResend}
        aria-label="Resend OTP via WhatsApp"
      >
        <img
          class="resend-wa-icon"
          src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/whatsapp.svg?v=1785132359"
          alt="WhatsApp"
        />
      </button>
    {/if}
  </div>
</div>

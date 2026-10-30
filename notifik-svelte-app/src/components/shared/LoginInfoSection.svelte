<script>
  import { getSessionValue } from "../../services/sessionService.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import { performLogout } from "../../stores/otpStore.js";
  import LogoutConfirmSlider from "./LogoutConfirmSlider.svelte";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  $: verifiedData = getSessionValue("verifiedNumberData", null);
  $: isOtpVerified = !!(verifiedData && verifiedData.isOTPVerified);
  $: verifiedPhoneNumber = verifiedData?.otpVerifiedPhoneNumber || "";
  $: phoneNumber = $appStore.phoneNumber || "";

  const normalizePhone = (val) => {
    const s = (val ?? "").toString().trim();
    if (!s) return "";
    return s.startsWith("+") ? s : `+${s}`;
  };

  const formatPhone = (val) => {
    const compact = (val ?? "").replace(/\s/g, "");
    const in91 = /^\+91(\d{10})$/.exec(compact);
    if (in91) return `+91 ${in91[1].slice(0, 5)} ${in91[1].slice(5)}`;
    return val;
  };

  $: displayPhone = normalizePhone(verifiedPhoneNumber || phoneNumber);
  $: formattedPhone = formatPhone(displayPhone);

  let showLogoutConfirm = false;
  let isLoggingOut = false;

  async function confirmLogout() {
    if (isLoggingOut) return;
    isLoggingOut = true;
    try {
      await performLogout("LoginInfoSection");
    } finally {
      isLoggingOut = false;
      showLogoutConfirm = false;
    }
  }
</script>

{#if displayPhone}
  <div class="codk-login-row animate-fade-in">
    <span class="codk-login-phone">{formattedPhone}</span>

    {#if isOtpVerified}
      <button
        type="button"
        class="codk-not-you"
        on:click={() => (showLogoutConfirm = true)}
      >
        {T("login_not_you")}
      </button>
    {/if}
  </div>

  <LogoutConfirmSlider
    open={showLogoutConfirm}
    loading={isLoggingOut}
    phone={displayPhone}
    on:close={() => (showLogoutConfirm = false)}
    on:confirm={confirmLogout}
  />
{/if}

<style>
  .codk-login-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    font-family: var(--font-family-base);

  }

  .codk-login-phone {
    font-size: 12px;
    font-weight: 500;
    color: #5c5f62;
    letter-spacing: 0.01em;
    font-family: var(--font-family-base);
  }

  .codk-not-you {
    display: inline-flex;
    align-items: center;
    padding: 0px 3px;
    border: 1px solid color-mix(in srgb, var(--color-blue) 22%, transparent);
    border-radius: 6px;
    background-color: #f9fafd !important;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }

  .codk-not-you:active {
    background: #eef2f7;
  }
</style>

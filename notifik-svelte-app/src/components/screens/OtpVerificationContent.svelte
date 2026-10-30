<script>
  import { onMount, onDestroy } from "svelte";
  import { get } from "svelte/store";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import { sendCode } from "../../services/api.js";
  import { verifyOtpRequest } from "../../services/otpService.js";
  import {
    setShippingAddresses,
    setCustomerEmail,
    getSessionValue,
  } from "../../services/sessionService.js";
  import { getCountryKeyByCode } from "../../data/countries.js";
  import {
    getMachineId,
    simplifyCartItems,
    getShopDomain,
  } from "../../utils/helpers.js";
  import "../../styles/components/screens/OtpVerificationScreen.css";
  import "../../styles/components/screens/OtpVerificationScreen.mobile.css";
  import OTPInputFields from "../otp/OTPInputFields.svelte";
  import ResendSection from "../otp/ResendSection.svelte";
  import BrandFooter from "../shared/BrandFooter.svelte";
  import { getCurrentStep } from "../../utils/stepUtils.js";
  import { toast } from "../../utils/toast.js";

  let otpValues = ["", "", "", ""];
  let activeIndex = 0;
  let error = "";
  let timerInterval = null;
  let retryCount = 0;
  const MAX_RETRIES = 3;
  $: phoneNumber = $appStore.phoneNumber || "";
  $: timerSeconds = $appStore.timerSeconds || 0;
  $: canResend = $appStore.canResend || false;
  $: isVerifying = $appStore.isVerifying || false;
  $: settings = $appStore.settings || null;
  $: otpMode = $appStore.otpMode || "SMS";
  $: whatsappEnabled = settings?.preWhatsappButton || false;

  $: isOtpComplete =
    otpValues.join("").length === 4 &&
    otpValues.every((digit) => /^\d$/.test(digit));

  let autoVerifyTimeout = null;
  $: displayPhone = phoneNumber || "";

  let inlineError = "";
  $: if (error) {
    const current = error;
    inlineError = "";
    toast.error(current).then((ok) => {
      if (!ok && error === current) inlineError = current;
    });
  } else {
    inlineError = "";
  }

  onMount(() => {
    initialiseTimer();
    setTimeout(() => {
      const firstInput = document.getElementById("otp-input-0");
      if (firstInput && firstInput instanceof HTMLInputElement) {
        firstInput.focus();
      }
    }, 100);
    return () => {
      if (timerInterval) clearInterval(timerInterval);
    };
  });

  onDestroy(() => {
    if (timerInterval) clearInterval(timerInterval);
  });

  function initialiseTimer() {
    const state = get(appStore);
    if (state.timerSeconds > 0) {
      startTimer(state.timerSeconds);
    } else {
      actions.setTimer(60, false);
      startTimer(60);
    }
  }

  function startTimer(initialSeconds) {
    if (timerInterval) clearInterval(timerInterval);
    let seconds = initialSeconds;
    actions.setTimer(seconds, false);
    actions.setCanResend(false);

    timerInterval = setInterval(() => {
      seconds -= 1;
      actions.setTimer(seconds, false);

      if (seconds <= 0) {
        clearInterval(timerInterval);
        actions.setCanResend(true);
        actions.setTimer(0, true);
      }
    }, 1000);
  }

  function handleOtpChange(event) {
    otpValues = event.detail.values;
    activeIndex = event.detail.index;
    if (error) {
      error = "";
      actions.setError(null);
    }
    actions.setOtpCode([...otpValues]);

    if (autoVerifyTimeout) {
      clearTimeout(autoVerifyTimeout);
      autoVerifyTimeout = null;
    }

    const currentOtp = otpValues.join("");
    if (
      currentOtp.length === 4 &&
      otpValues.every((digit) => /^\d$/.test(digit)) &&
      !isVerifying
    ) {
      autoVerifyTimeout = setTimeout(() => {
        if (!isVerifying && otpValues.join("").length === 4) {
          handleVerify();
        }
        autoVerifyTimeout = null;
      }, 200);
    }
  }

  function handleFocusChange(event) {
    activeIndex = event.detail.index;
  }

  async function handleSmsResend() {
    await handleResend("SMS");
  }

  async function handleWhatsappResend() {
    await handleResend("WHATSAPP");
  }

  async function handleResend(mode = "SMS") {
    if (!canResend || isVerifying) return;

    try {
      error = "";
      actions.setCanResend(false);
      const state = get(appStore);

      const phoneForPayload = state.phoneNumber.startsWith("+")
        ? state.phoneNumber.substring(1)
        : state.phoneNumber;

      const cartFilteredData = simplifyCartItems(state.cart?.items || []);
      const payload = {
        country_code: getCountryKeyByCode(state.countryCode) || "IN",
        phone: phoneForPayload,
        ip_address: state.ip_address || "",
        device_id: state.deviceId || getMachineId(),
        shop: state.settings?.shopDomain || window.parent?.Shopify?.shop,
        mode: mode,
        cart_details: cartFilteredData,
      };

      const response = await sendCode(payload);
      if (!response || response.status?.toLowerCase() === "error") {
        throw new Error(
          response?.Notes || "Failed to send OTP. Please try again.",
        );
      }

      actions.setOtpMode(mode);
      actions.setTimer(60, false);
      startTimer(60);
    } catch (err) {
      error = err.message || "Failed to resend OTP. Please try again.";
      actions.setCanResend(true);
    }
  }

  async function handleVerify() {
    if (isVerifying || !isOtpComplete) return;

    const otpCode = otpValues.join("");
    if (!otpCode || !otpCode.match(/^\d{4}$/)) {
      error =
        settings?.wrongOtpText ||
        settings?.preInvalidOtpMsg ||
        "Please enter the 4-digit code.";
      return;
    }

    const state = get(appStore);
    if (!state.phoneNumber) {
      error = "Phone number is missing. Please go back and try again.";
      return;
    }

    try {
      error = "";
      actions.setVerifying(true);
      actions.setOtpCode([...otpValues]);
      actions.setError(null);
      const deviceId = state.deviceId || getMachineId();
      actions.setDeviceId(deviceId);
      const phoneForApi = state.phoneNumber.startsWith("+")
        ? state.phoneNumber.substring(1)
        : state.phoneNumber;
      const phoneNumber = phoneForApi;
      const countryCode = getCountryKeyByCode(state.countryCode) || "IN";
      const countryCallingCode = state.countryCallingCode || "+91";
      const widgetState = {
        setIsLoading: (val) => {
          actions.setVerifying(val);
        },
        setStep: () => {},
        setError: (err) => {
          error = err;
          actions.setError(err);
        },
        setShowServerErrorText: () => {},
      };
      await verifyOtpRequest({
        countryCode,
        countryCallingCode,
        phoneNumber,
        ipAddress: state.ip_address || "",
        deviceId,
        shop: state.settings?.shopDomain || getShopDomain(),
        otp: otpCode,
        mode: state.otpMode || "SMS",
        widgetState,
      });
      const response = getSessionValue("preOrderOtpResponse");
      if (response) {
        actions.setPreOrderOtpResponse(response);
        const responseAddresses =
          response.shipping_addresses ||
          response.shippingAddresses ||
          response.shippingAddress;

        if (Array.isArray(responseAddresses) && responseAddresses.length) {
          setShippingAddresses(responseAddresses);
          actions.setAddresses(responseAddresses);
          otpStoreActions.setShippingAddressCount(responseAddresses.length);
        }
        const emailFromResponse =
          response.email ||
          response.customer?.email ||
          response.customerEmail ||
          response.customer_email ||
          null;

        if (emailFromResponse) {
          setCustomerEmail(emailFromResponse);
          actions.setCustomerEmail(emailFromResponse);
        }
      }

      await getCurrentStep();
    } catch (err) {

      error =
        err.message ||
        settings?.wrongOtpText ||
        settings?.preInvalidOtpMsg ||
        "Invalid OTP. Please try again.";
      actions.setError(error);

      if (retryCount < MAX_RETRIES) {
        retryCount++;
        setTimeout(() => {
          otpValues = ["", "", "", ""];
          activeIndex = 0;
          actions.setOtpCode([]);
        }, 1000);
      }
    } finally {
      actions.setVerifying(false);
    }
  }

  function handleRetry() {
    retryCount = 0;
    error = "";
    otpValues = ["", "", "", ""];
    activeIndex = 0;
    if (autoVerifyTimeout) {
      clearTimeout(autoVerifyTimeout);
      autoVerifyTimeout = null;
    }
    actions.setOtpCode([]);
  }

  async function handleEditPhone() {
    actions.setPhoneNumber("");
    actions.setOtpCode([]);
    actions.setError(null);
    actions.setScreen("phone");
  }

  function handleClose() {
    handleEditPhone();
  }
</script>

<div class="otp-screen">
  <div class="otp-heading-shell">
    <span class="otp-heading">
      {settings?.verifyMobileText ||
        settings?.preVerifyMobile ||
        "Verify phone number"}
    </span>
  </div>

  <div class="otp-subheading">
    <span class="otp-sub-label">
      {settings?.enterCodeText || "Enter OTP sent to"}
    </span>
    <span class="otp-sub-phone">
      <span class="otp-phone-num">{displayPhone || phoneNumber}</span>
      <button
        type="button"
        class="otp-edit-btn"
        on:click={handleEditPhone}
        aria-label="Edit phone number"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="18"
          height="18"
          viewBox="0 0 16 16"
          fill="none"
          aria-hidden="true"
        >
          <path
            d="M5.0549 10.4731H7.05926C7.12148 10.4735 7.18315 10.4616 7.24075 10.438C7.29834 10.4145 7.35073 10.3799 7.3949 10.3361L10.6662 7.06102L12.0087 5.74722C12.053 5.70328 12.0882 5.65101 12.1122 5.59343C12.1362 5.53584 12.1486 5.47407 12.1486 5.41168C12.1486 5.34929 12.1362 5.28752 12.1122 5.22993C12.0882 5.17234 12.053 5.12007 12.0087 5.07614L10.0044 3.04873C9.96041 3.00443 9.90812 2.96927 9.85052 2.94528C9.79291 2.92129 9.73112 2.90894 9.66872 2.90894C9.60631 2.90894 9.54452 2.92129 9.48692 2.94528C9.42931 2.96927 9.37703 3.00443 9.33308 3.04873L7.99999 4.38616L4.71926 7.66121C4.67545 7.70537 4.64079 7.75774 4.61726 7.81532C4.59374 7.8729 4.58181 7.93455 4.58217 7.99675V10.0005C4.58217 10.1259 4.63198 10.2461 4.72063 10.3347C4.80929 10.4233 4.92953 10.4731 5.0549 10.4731ZM9.66872 4.05062L11.0065 5.38805L10.3353 6.05913L8.99745 4.7217L9.66872 4.05062ZM5.52763 8.19051L8.3309 5.38805L9.66872 6.72548L6.86545 9.52794H5.52763V8.19051ZM12.6185 11.4183H4.10945C3.98407 11.4183 3.86383 11.4681 3.77518 11.5567C3.68652 11.6453 3.63672 11.7656 3.63672 11.8909C3.63672 12.0162 3.68652 12.1364 3.77518 12.2251C3.86383 12.3137 3.98407 12.3635 4.10945 12.3635H12.6185C12.7439 12.3635 12.8642 12.3137 12.9528 12.2251C13.0415 12.1364 13.0913 12.0162 13.0913 11.8909C13.0913 11.7656 13.0415 11.6453 12.9528 11.5567C12.8642 11.4681 12.7439 11.4183 12.6185 11.4183Z"
            fill="currentColor"
          />
        </svg>
      </button>
    </span>
  </div>

  {#if inlineError}
    <div class="otp-error" aria-live="polite">{inlineError}</div>
  {/if}

  <div class="otp-boxes">
    <OTPInputFields
      bind:otpValues
      bind:activeIndex
      disabled={isVerifying}
      error={!!error}
      on:otpChange={handleOtpChange}
      on:focusChange={handleFocusChange}
      on:submit={handleVerify}
    />
  </div>

  {#if isVerifying}
    <div class="otp-verifying-row animate-fade-in" aria-live="polite">
      <span class="otp-verifying-spinner" aria-hidden="true"></span>
      <span class="otp-verifying-text">
        {settings?.verifyingText || "Verifying…"}
      </span>
    </div>
  {/if}

  <div class="otp-resend">
    {#if canResend}
      <ResendSection
        {canResend}
        disabled={isVerifying}
        showWhatsapp={whatsappEnabled}
        on:smsResend={handleSmsResend}
        on:whatsappResend={handleWhatsappResend}
      />
    {:else}
      <div class="otp-resend-timer">
        <span>{settings?.retryInText || "Resend OTP in"}</span>
        <span class="otp-timer-inline">
          <svg
            width="11"
            height="11"
            viewBox="0 0 11 11"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            aria-hidden="true"
          >
            <path
              d="M7.15 4.95H6.05V2.75C6.05 2.60413 5.99206 2.46424 5.88891 2.36109C5.78577 2.25795 5.64587 2.2 5.5 2.2C5.35413 2.2 5.21424 2.25795 5.11109 2.36109C5.00795 2.46424 4.95 2.60413 4.95 2.75V5.5C4.95 5.64587 5.00795 5.78576 5.11109 5.88891C5.21424 5.99205 5.35413 6.05 5.5 6.05H7.15C7.29587 6.05 7.43576 5.99205 7.53891 5.88891C7.64205 5.78576 7.7 5.64587 7.7 5.5C7.7 5.35413 7.64205 5.21423 7.53891 5.11109C7.43576 5.00794 7.29587 4.95 7.15 4.95ZM5.5 0C4.4122 0 3.34884 0.322569 2.44437 0.926917C1.5399 1.53126 0.834947 2.39025 0.418665 3.39524C0.00238306 4.40023 -0.106535 5.5061 0.105683 6.57299C0.317902 7.63989 0.841726 8.6199 1.61091 9.38908C2.3801 10.1583 3.36011 10.6821 4.42701 10.8943C5.4939 11.1065 6.59977 10.9976 7.60476 10.5813C8.60975 10.1651 9.46874 9.4601 10.0731 8.55563C10.6774 7.65116 11 6.5878 11 5.5C10.9984 4.04181 10.4184 2.6438 9.3873 1.6127C8.3562 0.581605 6.95819 0.00162172 5.5 0ZM5.5 9.9C4.62976 9.9 3.77907 9.64194 3.05549 9.15846C2.33192 8.67498 1.76796 7.9878 1.43493 7.18381C1.10191 6.37981 1.01477 5.49512 1.18455 4.6416C1.35432 3.78809 1.77338 3.00408 2.38873 2.38873C3.00408 1.77338 3.78809 1.35432 4.6416 1.18454C5.49512 1.01477 6.37981 1.1019 7.18381 1.43493C7.9878 1.76796 8.67499 2.33191 9.15847 3.05549C9.64194 3.77907 9.9 4.62976 9.9 5.5C9.89867 6.66654 9.43467 7.78492 8.6098 8.60979C7.78493 9.43466 6.66654 9.89866 5.5 9.9Z"
              fill="currentColor"
            />
          </svg>
          <span class="otp-timer-secs">{timerSeconds}s</span>
        </span>
      </div>
    {/if}
  </div>
</div>

<div class="otp-brand-footer">
  <BrandFooter />
</div>

<script>
  import { appStore, actions } from "../../stores/buttonManager.js";
  import { settingsStore } from "../../stores/settingsStore.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import { onMount, tick } from "svelte";
  import { get } from "svelte/store";
  import { fly } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import "../../styles/components/screens/PhoneInputScreen.css";
  import "../../styles/components/screens/PhoneInputScreen.desktop.css";
  import {
    getFilteredCountries,
    getCountryKeyByCode,
    getCountryByKey,
  } from "../../data/countries.js";
  import { sendCode, getAddressCount } from "../../services/api.js";
  import { getCart } from "../../services/otpService.js";
  import {
    getMachineId,
    formatCurrency,
    checkImageAspectRatio,
    formatTitle,
    closeModalAndNotifyParent,
    simplifyCartItems,
    mapCartToOrderSummary,
    isIndianPhoneNumber,
  } from "../../utils/helpers.js";
  import {
    setOTPSkipped,
    setCustomerEmail,
    getCustomerEmail,
    getSettings,
    clearSessionValue,
  } from "../../services/sessionService.js";
  import { getCurrentStep } from "../../utils/stepUtils.js";
  import { toast } from "../../utils/toast.js";
  import LoadingSpinner from "../shared/LoadingSpinner.svelte";
  import ErrorDisplay from "../shared/ErrorDisplay.svelte";
  import SkeletonLoader from "../shared/SkeletonLoader.svelte";
  import PromoBanner from "../shared/PromoBanner.svelte";
  import CartLoadingScreen from "../shared/CartLoadingScreen.svelte";
  import PhoneInputForm from "../forms/PhoneInputForm.svelte";
  import OrderSummaryCard from "../sections/OrderSummaryCard.svelte";
  import CODKButton from "../shared/CODKButton.svelte";
  import BrandFooter from "../shared/BrandFooter.svelte";
  import "../../styles/components/sections/StickyFooterSection.css";
  import "../../styles/components/sections/StickyFooterSection.desktop.css";
  import { isOptimizedBuyNowEnabled } from "../../services/sessionService.js";
  import { createTranslator, isWhatsappPrimary } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  let phoneNumber = "";
  let selectedCountryCode = "";
  let showDropdown = false;
  let searchQuery = "";
  let error = "";
  let isValidNumber = false;
  let isSending = false;
  let isWhatsappSending = false;
  let retryCount = 0;
  const MAX_RETRIES = 3;
  let storeLogoUrl = null;
  let storeLogoType = "fallback";
  let storeName = "";
  let countryCodeList = [];
  let filteredCountries = [];

  $: otpState = $otpStore;
  $: orderSummary = mapCartToOrderSummary(
    otpState?.currentCartData,
    "INR", // Fallback currency
  );
  $: cartLoading = !$otpStore.isCartReady;
  let isSkipping = false;
  const RECENT_NUMBERS_KEY = "codk_recent_phone_numbers";
  let recentNumbers = [];
  let showNumberSuggestions = false;
  let lastPhoneKey = "";
  let settings = null;
  let currentScreen = "phone";
  const unsubscribe = appStore.subscribe((state) => {
    settings = state.settings;
    currentScreen = state.currentScreen;
  });
  $: {
    if (settings) {
      const countryListStr = settings.countryCodeList;
      if (countryListStr && typeof countryListStr === "string") {
        const parsedList = countryListStr
          .split(",")
          .map((c) => c.trim().toUpperCase())
          .filter((c) => c.length > 0);

        countryCodeList = parsedList;
      } else {
        countryCodeList = [];
      }
    } else {
      countryCodeList = [];
    }
  }
  $: selectedCountry = getCountryByKey(
    getCountryKeyByCode(selectedCountryCode),
  ) ||
    (filteredCountries[0] ? { ...filteredCountries[0] } : null) || {
      code: "91",
      flag: "🇮🇳",
      name: "India",
    };

  function normalizeNationalNumber(rawNumber = "") {
    let digits = String(rawNumber).replace(/\D/g, "").replace(/^0+/, "");
    // India only: drop a typed 91 country code so it isn't prepended twice.
    if (isIndiaSelected(selectedCountryCode) && digits.startsWith("91") && digits.length > 10) {
      digits = digits.slice(2);
    }
    return digits;
  }

  function isPhoneNumberValid(rawNumber) {
    const national = normalizeNationalNumber(rawNumber);
    return national.length >= 6 && national.length <= 15;
  }

  // Validate after stripping non-digits and leading 0s.
  $: {
    isValidNumber = isPhoneNumberValid(phoneNumber);
  }

  // Filter countries based on countryCodeList and search query
  $: {
    // Get countries from countryCodeList only (not from allowedCountries/geo filtering)
    const baseCountries = getFilteredCountries(countryCodeList);

    if (searchQuery.trim() === "") {
      filteredCountries = baseCountries;
    } else {
      const query = searchQuery.toLowerCase().trim();
      filteredCountries = baseCountries.filter(
        (country) =>
          country.name.toLowerCase().includes(query) ||
          country.code.includes(query) ||
          country.flag.toLowerCase().includes(query) ||
          country.key.toLowerCase().includes(query),
      );
    }
  }

  // Default selected country to 1st index of countryCodeList (not India)
  $: {
    if (filteredCountries.length > 0) {
      const isCurrentInList = filteredCountries.some(
        (c) => c.code === selectedCountryCode,
      );
      if (!selectedCountryCode || !isCurrentInList) {
        selectedCountryCode = filteredCountries[0].code;
      }
    }
  }

  $: skipEnabled = Boolean(settings?.showSkipBtn ?? false);
  let checkboxChecked = false;

  // Show Send Code (SMS/Continue) button only when setting is explicitly true
  $: preV2ShowSendCodeEnabled =
    settings?.preV2ShowSendCode === true ||
    settings?.pre_v2_show_send_code === true;

  // Compute WhatsApp button visibility
  $: whatsappEnabled = (() => {
    if (!settings) return false;
    const value = settings.preWhatsappButton || settings.pre_whatsapp_button;
    if (value === true || value === 1) return true;
    if (value === false || value === 0 || value === null || value === undefined)
      return false;
    const strValue = String(value).toLowerCase().trim();
    return strValue === "true" || strValue === "1" || strValue === "yes";
  })();

  // Compute preWhatsappButton setting (same logic as whatsappEnabled)
  $: preWhatsappButtonEnabled = whatsappEnabled;

  // Both OTP channels enabled → black "Send Code" button + a "Send OTP via
  // WhatsApp" affordance beneath it.
  $: bothOtpButtons = preV2ShowSendCodeEnabled && preWhatsappButtonEnabled;

  // Merchant opted to lead with WhatsApp: it takes the primary button and
  // Send Code drops below it.
  $: whatsappFirst = bothOtpButtons && isWhatsappPrimary(settings);

  // The only selectable country is India.
  $: indiaOnlyList =
    filteredCountries.length === 1 &&
    isIndiaSelected(filteredCountries[0]?.code);

  // India-only list + SMS-only: no button — the OTP auto-sends once the number
  // is valid.
  $: autoSendMode =
    indiaOnlyList && preV2ShowSendCodeEnabled && !preWhatsappButtonEnabled;

  // India-only country list with WhatsApp off: SMS is the only channel, so the
  // customer has nothing to choose. The OTP send never needs to block them —
  // push straight to the OTP screen and let the request finish in the
  // background. Also what makes picking a saved number send immediately.
  $: indiaSmsOnlyFastFlow = indiaOnlyList && !preWhatsappButtonEnabled;

  // Show the primary SMS "Send Code" button unless we're auto-sending.
  $: showSmsButton = preV2ShowSendCodeEnabled && !autoSendMode;

  // Only WhatsApp is enabled → the single primary button becomes WhatsApp.
  $: whatsappOnlyMode = preWhatsappButtonEnabled && !preV2ShowSendCodeEnabled;

  // StickyFooterSection inline code - derived values
  $: isSmsLoading = $otpStore.isSmsLoading || false;
  $: isWhatsappLoading = $otpStore.isWhatsappLoading || false;
  $: isSkipLoading = $otpStore.isSkipLoading || false;
  $: isLoading = $otpStore.otpData?.isLoading || false;
  $: isCartReady = $otpStore.isCartReady || false;
  $: optimizedBuyNow = ($otpStore.settings, isOptimizedBuyNowEnabled());
  $: buyNowError = $otpStore.buyNowError;
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
  $: footerSettings = $settingsStore;
  // Optimized: sending OTP doesn't need the cart, and handleSendCode() validates
  // the number itself — so the send button never waits on the cart chain.
  // Off: original behavior — disabled until the cart is ready.
  $: actionButtonDisabled = isLoading || (!optimizedBuyNow && !isCartReady);
  // Skip places a non-COD order (redirects to checkout) and needs the real cart.
  $: skipButtonDisabled = isLoading || !isCartReady;

  const WA_ICON =
    "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/whatsapp.svg?v=1785132359";

  // SVG icons
  const smsIcon = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>`;
  const whatsappIcon = `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z"/></svg>`;

  // Footer handlers
  function handleFooterSmsClick() {
    if (handleSmsClick) handleSmsClick();
  }

  function handleFooterWhatsappClick() {
    if (handleWhatsappClick) handleWhatsappClick();
  }

  function handleFooterSkipClick() {
    if (!skipButtonDisabled && !isSkipLoading && handleSkip) handleSkip();
  }

  // Debug WhatsApp button setting
  $: {
    if (settings) {
    }
  }

  onMount(async () => {
    loadRecentNumbers();

    // Land the cursor in the phone field so the user can type right away — only
    // on non-touch devices. On touch, auto-focusing pops the keyboard and can
    // jump/zoom the viewport, so we let the user tap first.
    const canAutofocus =
      typeof window !== "undefined" &&
      !window.matchMedia?.("(pointer: coarse)").matches;
    if (canAutofocus && (currentScreen === "phone" || !currentScreen)) {
      setTimeout(() => {
        const phoneInput = document.querySelector(".phone-input-field");
        if (phoneInput instanceof HTMLInputElement) phoneInput.focus();
      }, 250);
    }

    // Load settings if not already loaded
    if (!settings) {
      const loadedSettings = getSettings();
      if (loadedSettings) {
        actions.setSettings(loadedSettings);
      }
    }

    // Load store info
    await loadStoreInfo();

    // ⚡ CRITICAL: Cart fetching is now handled by OrderSummaryCard component
    // We just wait for isCartReady flag here
    // No need to call handleBuyNowCartIfNeeded or loadCart anymore

    // Note: Country list initialization is now handled reactively above
    // when settings become available
  });

  async function loadStoreInfo() {
    if (!settings) return;

    const preV2Title = settings.preV2Title;
    const brandLogoUrl = settings.brandLogoUrl;

    // Format store name
    const shopDomain = window.parent?.Shopify?.shop || window.Shopify?.shop;
    const rawName =
      preV2Title || shopDomain?.replace(".myshopify.com", "") || "Store";
    storeName = formatTitle(rawName, 30);

    // Load logo if available
    if (brandLogoUrl) {
      try {
        const imageType = await checkImageAspectRatio(brandLogoUrl);
        storeLogoType = imageType === "Wide image" ? "wide" : "square";
        storeLogoUrl = brandLogoUrl;
      } catch (_error) {
        storeLogoType = "fallback";
        storeLogoUrl = null;
      }
    } else {
      storeLogoType = "fallback";
      storeLogoUrl = null;
    }
  }

  function getStorageContext() {
    if (typeof window === "undefined") return null;
    try {
      if (
        window.parent &&
        window.parent !== window &&
        window.parent.localStorage
      ) {
        return window.parent.localStorage;
      }
    } catch (_error) {}
    try {
      if (typeof localStorage !== "undefined") return localStorage;
    } catch (_e) {}
    return null;
  }

  function loadRecentNumbers() {
    try {
      const storage = getStorageContext();
      if (!storage) return;
      const stored = storage.getItem(RECENT_NUMBERS_KEY);
      if (stored) {
        const parsed = JSON.parse(stored);
        if (Array.isArray(parsed)) {
          recentNumbers = parsed.slice(0, 5);
        }
      }
    } catch (_error) {}
  }

  function saveRecentNumber(rawNumber, countryCode) {
    try {
      const storage = getStorageContext();
      if (!storage) return;
      const cleaned = (rawNumber || "").replace(/\D/g, "");
      if (!cleaned) return;
      const normalizedCode = `${countryCode}`.replace(/^\+/, "") || "91";
      const existing =
        recentNumbers?.filter(
          (entry) =>
            entry.phoneNumber !== cleaned ||
            entry.countryCode !== normalizedCode,
        ) || [];
      const updated = [
        {
          phoneNumber: cleaned,
          countryCode: normalizedCode,
          savedAt: Date.now(),
        },
        ...existing,
      ].slice(0, 5);
      storage.setItem(RECENT_NUMBERS_KEY, JSON.stringify(updated));
      recentNumbers = updated;
    } catch (_error) {}
  }

  async function applyRecentNumber(entry) {
    if (!entry) return;
    selectedCountryCode = entry.countryCode || filteredCountries[0]?.code || "";
    phoneNumber = entry.phoneNumber || "";
    maybeResetOtpStateForNewNumber(
      `${selectedCountryCode}${phoneNumber.replace(/\D/g, "")}`,
    );
    actions.setPhoneNumber(phoneNumber, selectedCountryCode);
    actions.setCountryCallingCode(`+${selectedCountryCode}`);
    showNumberSuggestions = false;

    // isValidNumber is recomputed in a reactive block, so it is still the
    // previous number's value until the pending update flushes.
    await tick();
    actions.setValidNumber(isValidNumber);

    if (
      indiaSmsOnlyFastFlow &&
      isIndiaSelected(selectedCountryCode) &&
      isValidNumber
    ) {
      pendingRecentSend = normalizeNationalNumber(phoneNumber);
      flushPendingRecentSend();
      return; // the OTP screen takes over — nothing left to focus
    }

    focusPhoneInput();
  }

  function handlePhoneInputFocus() {
    if (recentNumbers.length > 0) {
      showNumberSuggestions = true;
    }
  }

  function handlePhoneInputBlur() {
    setTimeout(() => {
      showNumberSuggestions = false;
    }, 150);
  }

  function clearRecentNumbers() {
    try {
      const storage = getStorageContext();
      if (storage) {
        storage.removeItem(RECENT_NUMBERS_KEY);
      }
    } catch (_error) {}
    recentNumbers = [];
    showNumberSuggestions = false;
  }

  // ⚡ CRITICAL: Cart fetching removed - now handled by OrderSummaryCard component
  // We reactively read orderSummary from store and wait for isCartReady flag

  function selectCountry(country) {
    selectedCountryCode = country.code;
    showDropdown = false;
    searchQuery = "";
    maybeResetOtpStateForNewNumber(
      `${selectedCountryCode}${phoneNumber.replace(/\D/g, "")}`,
    );
    actions.setPhoneNumber(phoneNumber, country.code);
    actions.setCountryCallingCode(`+${country.code}`);
    actions.setValidNumber(isValidNumber);
  }

  function resetOtpState() {
    // Reset UI + store flags so user clearly starts fresh for new number
    error = "";
    retryCount = 0;
    isSending = false;
    isWhatsappSending = false;
    actions.setError(null);
    actions.setOtpCode(["", "", "", ""]);
    actions.setTimer(60, false);
    actions.setCanResend(false);
    actions.setVerifying(false);
    // Also reset otpStore loading flags (used for button spinners)
    otpStoreActions.setIsSmsLoading(false);
    otpStoreActions.setisWhatsAppLoading(false);
  }

  function maybeResetOtpStateForNewNumber(nextPhoneKey) {
    // Only reset if we already had a number and the user changed it
    if (lastPhoneKey && nextPhoneKey && nextPhoneKey !== lastPhoneKey) {
      resetOtpState();
      // Number changed → drop the previous number's verified session so we don't
      // reuse its OTP-verified flag or saved addresses for the new number.
      clearSessionValue("verifiedNumberData");
      clearSessionValue("shipping_addresses");
      clearSessionValue("preOrderOtpResponse");
    }
    lastPhoneKey = nextPhoneKey;
  }

  function handlePhoneChange(event) {
    const detail = event?.detail;
    if (detail == null) return;
    const { phoneNumber: newPhoneNumber, selectedCountryCode: newCountryCode } =
      detail;
    const nextKey = `${newCountryCode}${(newPhoneNumber || "").replace(/\D/g, "")}`;
    maybeResetOtpStateForNewNumber(nextKey);
    phoneNumber = newPhoneNumber;
    selectedCountryCode = newCountryCode;
    actions.setPhoneNumber(phoneNumber, selectedCountryCode);
    actions.setValidNumber(isValidNumber);
  }

  function handleCountryChange(country) {
    if (!country) return;
    const nextKey = `${country.code}${phoneNumber.replace(/\D/g, "")}`;
    maybeResetOtpStateForNewNumber(nextKey);
    selectedCountryCode = country.code;
    selectedCountry = country;
    showDropdown = false;
    searchQuery = "";
    actions.setPhoneNumber(phoneNumber, country.code);
    actions.setCountryCallingCode(`+${country.code}`);
    actions.setValidNumber(isValidNumber);
  }

  function handleDropdownToggle(event) {
    const detail = event?.detail;
    if (detail != null && typeof detail.showDropdown === "boolean") {
      showDropdown = detail.showDropdown;
    }
  }

  const handleSmsClick = () => {
    handleSendCode("SMS");
  };

  function handleWhatsappClick() {
    handleSendCode("WHATSAPP");
  }

  const AUTO_SEND_DEBOUNCE_MS = 200;
  let autoSendTimer = null;
  let lastAutoSentNumber = "";
  let pendingRecentSend = "";

  // The send needs the cart, same as the debounced auto-send. If the customer
  // picked a number before it arrived, hold the send until it does.
  $: if (pendingRecentSend && isCartReady) flushPendingRecentSend();

  function flushPendingRecentSend() {
    const national = pendingRecentSend;
    if (!national) return;
    if (normalizeNationalNumber(phoneNumber) !== national) {
      pendingRecentSend = "";
      return;
    }
    if (!isCartReady || isSending || isWhatsappSending) return;
    pendingRecentSend = "";
    // Claim the number so the debounced auto-send doesn't fire a second OTP.
    lastAutoSentNumber = national;
    handleSendCode("SMS");
  }

  function isIndiaSelected(code) {
    return String(code || "").replace(/^\+/, "") === "91";
  }

  $: scheduleAutoSendOtp(
    selectedCountryCode,
    phoneNumber,
    isCartReady,
    autoSendMode
  );

  function scheduleAutoSendOtp(countryCode, rawPhone, cartReady, canAutoSend) {
    if (typeof window === "undefined") return;

    if (autoSendTimer) {
      clearTimeout(autoSendTimer);
      autoSendTimer = null;
    }

    const national = normalizeNationalNumber(rawPhone);

    if (!canAutoSend) {
      return;
    }

    if (
      !isIndiaSelected(countryCode) ||
      national.length !== 10 ||
      !isPhoneNumberValid(national) ||
      !cartReady ||
      isSending ||
      isWhatsappSending ||
      lastAutoSentNumber === national
    ) {
      return;
    }

    autoSendTimer = setTimeout(() => {
      autoSendTimer = null;
      const current = normalizeNationalNumber(phoneNumber);
      if (
        isIndiaSelected(selectedCountryCode) &&
        current === national &&
        isPhoneNumberValid(current) &&
        !isSending &&
        !isWhatsappSending &&
        lastAutoSentNumber !== national
      ) {
        lastAutoSentNumber = national;
        handleSendCode("SMS");
      }
    }, AUTO_SEND_DEBOUNCE_MS);
  }

  function handleCheckboxChange(event) {
    // Handle checkbox change - event can be { checked } object or event.detail
    const checked = event?.checked ?? event?.detail?.checked ?? false;
    checkboxChecked = checked;
  }

  const OTP_BLOCKED_MESSAGE =
    "Sorry, we're unable to send an OTP right now. Please try again later.";

  function isPhoneBlocked(phoneDigits) {
    const s = getSettings() || $settingsStore || {};
    const raw = s.preBlockPhone ?? s.pre_block_phone ?? "";
    const phone = String(phoneDigits || "");
    if (!phone || !raw) return false;
    return String(raw)
      .split(",")
      .map((entry) => entry.trim())
      .filter(Boolean)
      .some((entry) => phone.includes(entry));
  }

  function isBlockedOtpResponse(res) {
    return (
      res?.code === "pre_order_otp_phone_blocked" ||
      /cannot be used for verification/i.test(String(res?.Notes || ""))
    );
  }

  async function handleSendCode(mode = "SMS", isRetry = false) {
    // Clear previous errors (unless it's a retry)
    if (!isRetry) {
      error = "";
      retryCount = 0;
    }
    actions.setError(null);

    const nationalNumber = normalizeNationalNumber(phoneNumber);
    const fullNumber = `${selectedCountryCode}${nationalNumber}`;
    const isValidPhoneNumber = isPhoneNumberValid(nationalNumber);
    if (!isValidPhoneNumber || !isValidNumber) {
      error = "Please enter a valid phone number.";
      actions.setError(error);
      return;
    }

    if (isPhoneBlocked(fullNumber.replace(/^\+/, ""))) {
      error = OTP_BLOCKED_MESSAGE;
      actions.setError(error);
      return;
    }

    // Set loading state (using otpStore)
    if (mode === "SMS") {
      isSending = true;
      otpStoreActions.setIsSmsLoading(true);
    } else {
      isWhatsappSending = true;
      otpStoreActions.setisWhatsAppLoading(true);
    }

    try {
      const currentState = get(appStore);
      const settings = getSettings();

      // Get full phone number with country code (national number only, no double prefix)
      const dialCodeWithPlus = selectedCountryCode.startsWith("+")
        ? selectedCountryCode
        : `+${selectedCountryCode}`;
      const fullPhoneNumber = `${dialCodeWithPlus}${nationalNumber}`;
      const countryKey =
        getCountryKeyByCode(selectedCountryCode) ||
        filteredCountries[0]?.key ||
        "US";

      // ⚡ MATCHING REACT: Call getAddressCount() fire-and-forget ONLY if isPrefilledAddressEnabled is true
      if (settings?.isPrefilledAddressEnabled) {
        const shopDomain = settings.shopDomain || window.parent?.Shopify?.shop;
        const phoneForAddressCount = fullPhoneNumber.startsWith("+")
          ? fullPhoneNumber.substring(1)
          : fullPhoneNumber;

        // Fire-and-forget (not awaited, matching React's .then() pattern)
        getAddressCount(phoneForAddressCount, shopDomain)
          .then((res) => {
            if (res.success && res.data) {
              // Store email (session + localStorage via setCustomerEmail)
              if (res.data.email) {
                setCustomerEmail(res.data.email);
                actions.setCustomerEmail(res.data.email);
              }
              // Store shipping address count (matching React: get().setShippingAddressCount(...))
              const addressCount =
                res.data.shippingAddressCount ||
                res.data.shipping_address_count ||
                0;
              otpStoreActions.setShippingAddressCount(addressCount);
            }
          })
          .catch(() => {});
      }

      // ⚡ MATCHING REACT: Get cart items (matching React: getCartItemsOrRefetch())
      let cartDataItems = [];
      try {
        const cart = await getCart();
        cartDataItems = cart?.items || [];
      } catch (_error) {
        cartDataItems = [];
      }

      // ⚡ MATCHING REACT: Use IP from store (already set, no fetching needed)
      const ipAddress = currentState.ip_address || "";

      // Prepare phone number without "+" for API payload
      const phoneForPayload = fullPhoneNumber.startsWith("+")
        ? fullPhoneNumber.substring(1)
        : fullPhoneNumber;

      // Prepare payload (matching React's sendOtpRequest payload structure)
      // Use simplifyCartItems to match React exactly
      const cartFilteredData = simplifyCartItems(cartDataItems);
      const payload = {
        country_code: countryKey,
        phone: phoneForPayload,
        ip_address: ipAddress,
        device_id: getMachineId(),
        shop: settings?.shopDomain || window.parent?.Shopify?.shop,
        mode: mode,
        cart_details: cartFilteredData,
      };

      // ⚡ India fast-flow: don't block the user on the OTP send round-trip.
      // Navigate to the OTP screen immediately and fire the send in the
      // background; surface an error there if the send fails. Applies when
      // optimized_buy_now is on, or when SMS is the only channel there is
      // (India-only country list + WhatsApp off) so there was nothing to
      // decide anyway. Non-India → original awaited flow below.
      if (
        (isOptimizedBuyNowEnabled() || indiaSmsOnlyFastFlow) &&
        isIndianPhoneNumber(fullPhoneNumber, selectedCountryCode)
      ) {
        saveRecentNumber(nationalNumber, selectedCountryCode);
        actions.setPhoneNumber(fullPhoneNumber, selectedCountryCode);
        actions.setOtpMode(mode);
        await getCurrentStep(); // → OTP screen
        actions.setTimer(settings?.otpWaitTimeInCodKSettings || 60, false);

        sendCode(payload)
          .then((res) => {
            if (res && res.status === "Success") {
              actions.setPreOrderOtpResponse(res);
            } else {
              const msg = isBlockedOtpResponse(res)
                ? OTP_BLOCKED_MESSAGE
                : res?.Notes ||
                  res?.message ||
                  "Failed to send OTP. Please try again.";
              error = msg;
              actions.setError(msg);
              otpStoreActions.setError(msg);
              otpStoreActions.setShowServerErrorText(true);
            }
          })
          .catch((err) => {
            const msg = err?.message || "Failed to send OTP. Please try again.";
            error = msg;
            actions.setError(msg);
            otpStoreActions.setError(msg);
            otpStoreActions.setShowServerErrorText(true);
          });
        return; // India fast path done — finally still resets loading flags
      }

      // ⚡ MATCHING REACT: Call sendCode (pre_order_otp API)
      const response = await sendCode(payload);

      // Check response (matching React: result.status === 200 && result.data.status === "Success")
      if (response && response.status === "Success") {
        // Success: Update store and navigate to OTP screen (store national number to avoid double country code on reuse)
        saveRecentNumber(nationalNumber, selectedCountryCode);
        actions.setPhoneNumber(fullPhoneNumber, selectedCountryCode);
        actions.setOtpMode(mode);
        actions.setPreOrderOtpResponse(response);

        // Navigate to OTP screen
        await getCurrentStep();
        actions.setTimer(settings?.otpWaitTimeInCodKSettings || 60, false);
      } else if (response && response.status === "Error") {
        // Backend returned an error - use the Notes field as error message
        const errorMessage = isBlockedOtpResponse(response)
          ? OTP_BLOCKED_MESSAGE
          : response.Notes || "Failed to send OTP. Please try again.";
        throw new Error(errorMessage);
      } else {
        throw new Error(
          response?.Notes || response?.message || "Failed to send OTP.",
        );
      }
    } catch (err) {
      // Determine error message
      let errorMessage = "Failed to send OTP. Please try again.";
      if (err.message) {
        if (err.message.includes("network") || err.message.includes("fetch")) {
          errorMessage =
            "Network error. Please check your connection and try again.";
        } else if (err.message.includes("timeout")) {
          errorMessage = "Request timed out. Please try again.";
        } else {
          errorMessage = err.message;
        }
      }

      error = errorMessage;
      actions.setError(error);

      // Auto-retry on network errors or rate limit errors (up to MAX_RETRIES)
      const isNetworkError =
        err.message?.includes("network") || err.message?.includes("fetch");
      const isRateLimitError =
        err.message?.includes("Too many requests") ||
        err.message?.includes("429");

      if (retryCount < MAX_RETRIES && (isNetworkError || isRateLimitError)) {
        retryCount++;
        const delay = isRateLimitError ? 5000 * retryCount : 2000 * retryCount;

        setTimeout(() => {
          handleSendCode(mode, true);
        }, delay);
      }
    } finally {
      isSending = false;
      isWhatsappSending = false;
      otpStoreActions.setIsSmsLoading(false);
      otpStoreActions.setisWhatsAppLoading(false);
    }
  }

  // Retry handler for error display
  function handleRetry() {
    retryCount = 0;
    error = "";
    if (isValidNumber) {
      handleSendCode("SMS", false);
    }
  }

  function handleSkip() {
    if (isSkipping) return;
    try {
      isSkipping = true;
      setOTPSkipped(true);
      actions.setOTPSkipped(true);

      // Redirect to checkout - do NOT call closeModalAndNotifyParent here.
      // That triggers parent to access iframe.contentWindow which can be null during
      // navigation, causing "Cannot read properties of null (reading 'document')".
      // The redirect will navigate away, so closing is unnecessary.
      otpStoreActions.handleSkip();
    } catch (_error) {
    } finally {
      isSkipping = false;
    }
  }

  function focusPhoneInput() {
    if (typeof document === "undefined") return;
    /** @type {HTMLInputElement | null} */
    const phoneInput = document.querySelector(".phone-input-field");
    if (phoneInput) {
      phoneInput.focus();
      phoneInput.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }

  function handlePhoneInputKeydown(event) {
    const e = event.detail;
    if (
      e.key === "Enter" &&
      isValidNumber &&
      !isSending &&
      !isWhatsappSending
    ) {
      handleSendCode("SMS");
    }
  }

  // Cleanup on unmount
  onMount(() => {
    return () => {
      unsubscribe();
      if (autoSendTimer) clearTimeout(autoSendTimer);
    };
  });
</script>

<!-- Phone Input Screen Content -->
{#if buyNowError}
  <div class="codk-buynow-error">
    <div class="codk-buynow-error__icon">⚠️</div>
    <div class="codk-buynow-error__title">
      {buyNowError.code === "OUT_OF_STOCK"
        ? "This product is out of stock"
        : "We couldn't add this product to your cart"}
    </div>
    <div class="codk-buynow-error__message">
      {buyNowError.message || "Please pick another product or come back later."}
    </div>
    <button type="button" class="codk-buynow-error__close" on:click={actions.closeModal}>
      {T("close")}
    </button>
  </div>
{:else if !optimizedBuyNow && !isCartReady}
  <!-- Off: original full-screen cart loader while the cart is being fetched. -->
  <CartLoadingScreen />
{:else}
  <!-- Optimized: the Mobile/OTP step never waits for the cart — sending OTP is
       cart-independent. The cart chain (clear/add/cart.js) keeps running in the
       background; only settings gate the form (handled by the skeleton below). -->
  {#if !settings}
    <div class="header-skeleton">
      <SkeletonLoader lines={1} width="40%" />
      <SkeletonLoader lines={1} width="30%" />
    </div>
  {/if}

  <!-- Phone Input Form -->
  <div class="form-container">
    <div class="phone-heading">
      <p class="phone-heading-title">
      {T("phone_title")}
      </p>
      <p class="phone-heading-subtitle">
      {T("phone_subtitle")}
      </p>
    </div>

    <PhoneInputForm
      bind:phoneNumber
      bind:selectedCountryCode
      bind:selectedCountry
      bind:showDropdown
      bind:searchQuery
      {error}
      {isValidNumber}
      {filteredCountries}
      phoneMaxLength={15}
      placeholder={settings?.phonePlaceholder || "Enter Phone no"}
      on:phoneChange={handlePhoneChange}
      on:countryChange={(e) => handleCountryChange(e.detail?.country)}
      on:dropdownToggle={handleDropdownToggle}
      on:keydown={handlePhoneInputKeydown}
      on:focus={handlePhoneInputFocus}
      on:blur={handlePhoneInputBlur}
    />
    <ErrorDisplay error={inlineError} onRetry={handleRetry} compact={true} />
    {#if recentNumbers.length > 0}
      <div
        class="recent-numbers"
        in:fly={{ y: -10, duration: 220, easing: cubicOut }}
        out:fly={{ y: -10, duration: 180, easing: cubicOut }}
      >
        <div class="recent-title">{T("phone_continue_with")}</div>
        <div class="recent-list">
          <span class="recent-icon" aria-hidden="true">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="14"
              viewBox="0 0 13 12"
              fill="none"
            >
              <path
                d="M6.38574 0.25C9.63379 0.25 12.2588 2.8291 12.2588 6C12.2588 9.1709 9.63379 11.75 6.38574 11.75C3.13787 11.7498 0.513672 9.17078 0.513672 6C0.513672 2.82922 3.13787 0.250201 6.38574 0.25Z"
                fill="white"
                stroke="#928F8F"
                stroke-width="0.5"
              />
              <path
                d="M6.504 7.72495L7.39815 7.27793C7.51195 7.22103 7.64078 7.23281 7.73901 7.29677C8.05161 7.50671 8.40534 7.67396 8.79374 7.78701C8.96464 7.83676 9.0614 8.00959 9.00876 8.17109L8.67379 9.19881C8.62115 9.36031 8.43826 9.45174 8.26736 9.402C5.34967 8.55276 3.71338 5.62994 4.61205 2.87272C4.66469 2.71122 4.84758 2.61978 5.01848 2.66953L6.1029 2.98517C6.2738 3.03491 6.37056 3.20774 6.31792 3.36924C6.19925 3.73335 6.14559 4.10673 6.15337 4.46907C6.15716 4.58269 6.09091 4.69201 5.98117 4.74687L5.08703 5.19389C5.26673 6.15602 5.76247 7.04617 6.504 7.72495Z"
                fill="#999999"
              />
            </svg>
          </span>{#each recentNumbers as recent, i}<button
              type="button"
              class="recent-item"
              on:click={() => applyRecentNumber(recent)}
            ><span class="recent-value">+{recent.countryCode} {recent.phoneNumber}</span></button>{#if i < recentNumbers.length - 1}<span class="recent-sep">,</span>{/if}{/each}
        </div>
      </div>
    {/if}
  </div>

  <!-- Footer Section - Inside ScreenContent (not sticky) -->
  {#if settings}{/if}
  <div class="sticky-footer-section">
    <div class="sticky-footer-background-cover"></div>

    <div class="buttons-section">
      {#if whatsappOnlyMode}
        <!-- Only WhatsApp is enabled: the primary button sends the WhatsApp OTP. -->
        <CODKButton
          variant="primary"
          loading={isWhatsappLoading}
          disabled={actionButtonDisabled}
          on:click={handleWhatsappClick}
          icon={isWhatsappLoading ? null : whatsappIcon}
          class="whatsapp-button"
          backgroundColor="#1e8a46"
          hoverBackground="#21984d"
          textColor="#ffffff"
        >
          {isWhatsappLoading
            ? "Sending..."
            : footerSettings?.preWhatsappButtonText || "Get WhatsApp OTP"}
        </CODKButton>
      {:else if whatsappFirst}
        <CODKButton
          variant="primary"
          loading={isWhatsappLoading}
          disabled={actionButtonDisabled || isSmsLoading}
          on:click={handleWhatsappClick}
          icon={isWhatsappLoading ? null : whatsappIcon}
          class="whatsapp-button"
          backgroundColor="#1e8a46"
          hoverBackground="#21984d"
          textColor="#ffffff"
        >
          {isWhatsappLoading
            ? "Sending..."
            : footerSettings?.preWhatsappButtonText || "Get WhatsApp OTP"}
        </CODKButton>
        <div class="send-alt">
          <span class="send-alt-text">{T("phone_send_otp_via")}</span>
          <button
            type="button"
            class="send-alt-wa send-alt-sms"
            disabled={actionButtonDisabled || isSmsLoading || isWhatsappLoading}
            on:click={handleSmsClick}
            aria-label="Send OTP via SMS"
          >
            {@html smsIcon}
          </button>
        </div>
      {:else if showSmsButton}
        <CODKButton
          variant="primary"
          loading={isSmsLoading}
          disabled={actionButtonDisabled}
          on:click={handleSmsClick}
          icon={isSmsLoading ? null : smsIcon}
          class="sms-button"
        >
          {isSmsLoading
            ? "Sending..."
            : footerSettings?.sendBtnText || "Get OTP"}
        </CODKButton>

        {#if bothOtpButtons}
          <div class="send-alt">
            <span class="send-alt-text">{T("phone_send_otp_via")}</span>
            <button
              type="button"
              class="send-alt-wa"
              disabled={actionButtonDisabled || isWhatsappLoading}
              on:click={handleWhatsappClick}
              aria-label="Send OTP via WhatsApp"
            >
              <img src={WA_ICON} alt="WhatsApp" />
            </button>
          </div>
        {/if}
      {/if}
    </div>

    <div class="checkbox-section">
      <!-- <div class="checkbox-wrapper">
        <input
          type="checkbox"
          class="checkbox-input"
          checked={checkboxChecked}
          onchange={handleCheckboxChange}
        />
        <div class="checkbox-label">Send me order updates & offers</div>
      </div> -->
      {#if skipEnabled}
        <div class="skip-wrapper">
          <button
            type="button"
            class="skip-button"
            disabled={skipButtonDisabled || isSkipLoading}
            onclick={handleFooterSkipClick}
          >
            <div class="skip-text">
              {isSkipLoading
                ? "Skipping..."
                : footerSettings?.skipBtnText || "Skip"}
            </div>
            <div class="skip-underline"></div>
          </button>
        </div>
      {/if}
    </div>
  </div>

  <div class="phone-brand-footer">
    <BrandFooter />
  </div>
{/if}

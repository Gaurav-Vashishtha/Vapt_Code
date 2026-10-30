<script>
  import { onMount, onDestroy } from "svelte";
  import { get } from "svelte/store";
  import { appStore, actions } from "../stores/buttonManager.js";
  import otpStore, { otpStoreActions } from "../stores/otpStore.js";
  import {
    formatCurrency,
    formatTitle,
    checkImageAspectRatio,
    getMachineId,
    closeModalAndNotifyParent,
    mapCartToOrderSummary,
    getShopifyRootPath,
    isIndianPhoneNumber,
  } from "../utils/helpers.js";
  import { getAddressCount } from "../services/api.js";
  import {
    getShippingAddresses,
    setShippingAddresses,
    getCustomerEmail,
    setCustomerEmail,
    getSelectedAddressId,
    setSelectedAddress,
    setAddressCompleted as setSessionAddressCompleted,
    getSessionValue,
    setSessionValue,
  } from "../services/sessionService.js";

  import ErrorDisplay from "./shared/ErrorDisplay.svelte";
  import ScreenLayout from "./layouts/ScreenLayout.svelte";
  import ScreenHeader from "./layouts/ScreenHeader.svelte";
  import ScreenContent from "./layouts/ScreenContent.svelte";
  import ProgressBar from "./navigation/ProgressBar.svelte";
  import Footer from "./footer/Footer.svelte";
  import Button from "./shared/CODKButton.svelte";
  import LoginInfoSection from "./shared/LoginInfoSection.svelte";
  import CartLoadingScreen from "./shared/CartLoadingScreen.svelte";
  import { handleBackNavigation as navigateBack } from "../utils/navigationUtils.js";
  import { getCurrentStep } from "../utils/stepUtils.js";
  import "../styles/components/AddressSelection.css";
  import "../styles/components/AddressSelection.desktop.css";
  import "../styles/components/AddressSelection.mobile.css";
  import { updateBuyerIdentity } from "../services/cartService.js";
  import { cartFetch } from "../utils/shopifyCartApi.js";
  import {
    getStorefrontCartId,
    buildBuyerIdentityPayload,
    isNoEmailPlaceholder,
    isPreEmailMandatory,
    getNoEmailPlaceholder,
  } from "../utilities/otpUtils.js";
  let storeLogoUrl = null;
  let storeLogoType = "fallback";
  let storeName = "";
  let isWideLogo = false;
  let lastLogoSource = null;

  let addresses = [];
  let selectedId = null;

  // Computed: Check if an address is selected (handles null IDs for new addresses)
  // When selectedId is null, check if there's an address with id === null
  // When selectedId is not null, check if there's an address with matching id
  $: hasSelectedAddress =
    selectedId !== undefined &&
    ((selectedId === null && addresses.some((addr) => addr.id === null)) ||
      (selectedId !== null &&
        addresses.some((addr) => addr.id === selectedId)));

  let continueError = "";

  // Email input field state (React equivalent: desktopDeliveryAddressComponent.js formData.email)
  let emailInput = "";
  let emailError = "";

  let isContinuing = false;
  let retryCount = 0;
  const MAX_RETRIES = 3;

  let settings = null;
  $: otpState = $otpStore;
  $: orderSummary = mapCartToOrderSummary(
    otpState?.currentCartData,
    "INR", // Fallback currency
  );
  let cartData = null;
  let phoneNumber = "";
  let customerEmail = "";
  let showAllAddresses = false;
  let openDropdownId = null; // Track which address dropdown is open

  // Check if OTP is verified to conditionally show logout button
  $: verifiedData = getSessionValue("verifiedNumberData", null);
  $: isOtpVerified = !!(verifiedData && verifiedData.isOTPVerified);

  let unsubscribe = null;

  let handleClickOutside = null;

  onMount(() => {
    unsubscribe = appStore.subscribe((state) => {
      settings = state.settings;
      cartData = state.cart || cartData;
      phoneNumber = state.phoneNumber || phoneNumber;
      customerEmail = state.customerEmail || customerEmail;

      if (state.addresses && state.addresses.length) {
        addresses = [...state.addresses];
        selectedId =
          state.selectedAddressId || selectedId || addresses[0]?.id || null;
      }
    });

    // Close dropdown when clicking outside
    handleClickOutside = (e) => {
      if (openDropdownId !== null) {
        const target = e.target;
        if (!target.closest(".more-button-wrapper")) {
          closeDropdown();
        }
      }
    };
    document.addEventListener("click", handleClickOutside);

    initializeStoreInfo();
    initializeAddresses();
  });

  onDestroy(() => {
    if (unsubscribe) unsubscribe();
    if (handleClickOutside) {
      document.removeEventListener("click", handleClickOutside);
    }
  });

  async function initializeStoreInfo() {
    if (!settings) return;

    const preV2Title = settings.preV2Title;
    const shopDomain = window.parent?.Shopify?.shop || window.Shopify?.shop;
    const rawName =
      preV2Title || shopDomain?.replace(".myshopify.com", "") || "Store";
    storeName = formatTitle(rawName, 30);

    const brandLogoUrl = settings.brandLogoUrl || settings.brand_logo_url;
    if (brandLogoUrl === lastLogoSource && storeLogoUrl) {
      return;
    }
    if (!brandLogoUrl) {
      storeLogoUrl = null;
      storeLogoType = "fallback";
      isWideLogo = false;
      return;
    }

    try {
      const imageType = await checkImageAspectRatio(brandLogoUrl);
      storeLogoType = imageType === "Wide image" ? "wide" : "square";
      storeLogoUrl = brandLogoUrl;
      isWideLogo = storeLogoType === "wide";
      lastLogoSource = brandLogoUrl;
    } catch (error) {

      storeLogoUrl = null;
      storeLogoType = "fallback";
      isWideLogo = false;
    }
  }

  async function initializeAddresses() {
    const state = get(appStore);
    let stateAddresses = state.addresses;
    const preOrderResponse = state.preOrderOtpResponse || {};

    // ⚡ CRITICAL: Don't auto-open address form if we're navigating back from address-form
    // This prevents the loop where back navigation goes to address screen, which immediately opens form again
    const isNavigatingBackFromForm =
      state.previousScreen === "address-form" &&
      state.currentScreen === "address";

    const otpAddresses =
      preOrderResponse?.shippingAddress ??
      preOrderResponse?.shippingAddresses ??
      preOrderResponse?.shipping_addresses;
    const otpList = Array.isArray(otpAddresses) ? otpAddresses : [];
    if (otpList.length > 0 && (!stateAddresses || !stateAddresses.length)) {
      actions.setAddresses(otpList);
      setShippingAddresses(otpList);
      stateAddresses = otpList;
    }

    if (!stateAddresses || !stateAddresses.length) {
      const cached = getShippingAddresses();
      if (cached && cached.length) {
        actions.setAddresses(cached);
        stateAddresses = cached;
      }
    }

    addresses = stateAddresses ? [...stateAddresses] : [];

    const storeSelectedId = get(appStore).selectedAddressId;
    if (storeSelectedId) {
      selectedId = storeSelectedId;
    } else {
      const sessionSelectedId = getSelectedAddressId();
      selectedId = sessionSelectedId || addresses[0]?.id || null;
      if (sessionSelectedId) {
        actions.selectAddress(sessionSelectedId);
      }
    }

    // ⚡ CRITICAL: Call getAddressCount API if email is missing (React equivalent: otpStore.js handlePhoneSubmit)
    // React app calls this when sending OTP code, but we also call it here as fallback if email is missing
    let addressCountFromApi = addresses.length;
    if (
      settings?.isPrefilledAddressEnabled &&
      !getCustomerEmail() &&
      phoneNumber
    ) {
      try {
        const shopDomain = window.parent?.Shopify?.shop || window.Shopify?.shop;
        const fullPhoneNumber = phoneNumber.startsWith("+")
          ? phoneNumber
          : `+${phoneNumber}`;

        const addressCountResponse = await getAddressCount(
          fullPhoneNumber,
          shopDomain,
        );

        if (addressCountResponse.success && addressCountResponse.data) {
          const responseData = addressCountResponse.data;

          // Update address count if different
          addressCountFromApi =
            responseData.shippingAddressCount ||
            responseData.shipping_address_count ||
            addresses.length;
          if (addressCountFromApi !== addresses.length) {
            otpStoreActions.setShippingAddressCount(addressCountFromApi);
          }

          // Extract and store email (session + localStorage via setCustomerEmail)
          if (
            responseData.email &&
            (!isPreEmailMandatory(settings) ||
              !isNoEmailPlaceholder(responseData.email))
          ) {
            const email = responseData.email;
            setCustomerEmail(email);
            actions.setCustomerEmail(email);
          }

          // Store customerId if available
          if (responseData.customerId || responseData.customer_id) {
            const customerId =
              responseData.customerId || responseData.customer_id;
            if (
              typeof window.parent !== "undefined" &&
              window.parent.sessionStorage
            ) {
              window.parent.sessionStorage.setItem("customer-id", customerId);
            }
          }
        } else {

        }
      } catch (err) {

      }
    }

    // Get email from multiple sources (matching old flow's getCustomerEmail logic)
    // Note: If getAddressCount API was called above, email may now be in sessionStorage
    let foundEmail = null;

    // 1. Check sessionStorage 'customer-email' (primary source - may have been set by getAddressCount API above)
    const sessionEmail = getCustomerEmail();
    if (sessionEmail) {
      foundEmail = sessionEmail;
    }

    // 2. Check sessionStorage 'cod_king_customer_email' (from address count API)
    if (
      !foundEmail &&
      typeof window.parent !== "undefined" &&
      window.parent.sessionStorage
    ) {
      try {
        const addressCountEmail = window.parent.sessionStorage.getItem(
          "cod_king_customer_email",
        );
        if (addressCountEmail) {
          foundEmail = addressCountEmail;
        }
      } catch (e) {

      }
    }

    // 3. Check preOrderOtpResponse from sessionStorage
    if (
      !foundEmail &&
      typeof window.parent !== "undefined" &&
      window.parent.sessionStorage
    ) {
      try {
        const otpResponseStr = window.parent.sessionStorage.getItem(
          "preOrderOtpResponse",
        );
        if (otpResponseStr) {
          const parsed = JSON.parse(otpResponseStr);
          if (parsed.email) {
            foundEmail = parsed.email;
          }
        }
      } catch (e) {

      }
    }

    // 4. Check preOrderOtpResponse from store
    if (!foundEmail) {
      const emailFromStore =
        preOrderResponse?.email ||
        preOrderResponse?.customer?.email ||
        preOrderResponse?.customerEmail ||
        preOrderResponse?.customer_email;
      if (emailFromStore) {
        foundEmail = emailFromStore;
      }
    }

    if (foundEmail && isPreEmailMandatory(settings) && isNoEmailPlaceholder(foundEmail)) {
      foundEmail = null;
    }

    if (foundEmail) {
      actions.setCustomerEmail(foundEmail);
      setCustomerEmail(foundEmail);
      customerEmail = foundEmail;
      emailInput = foundEmail; // Initialize email input field
    } else {

      // Initialize emailInput from sessionStorage if available
      const sessionEmail = getCustomerEmail();
      if (
        sessionEmail &&
        (!isPreEmailMandatory(settings) || !isNoEmailPlaceholder(sessionEmail))
      ) {
        emailInput = sessionEmail;
      }

    }

    // ⚡ CRITICAL: Only auto-open address form if:
    // 1. There are no addresses AND
    // 2. We're NOT navigating back from address-form (prevents loop)
    if (!addresses.length && !isNavigatingBackFromForm) {
      // Navigate directly to address form (explicit action - no addresses found)
      // Matching React app: MobileDeliveryAddressComponent.js line 420 → setStep(4)
      otpStoreActions.setIsEditAddress(false);
      otpStoreActions.setEditableAddress({});
      actions.setScreen("address-form");
    } else if (!addresses.length && isNavigatingBackFromForm) {
    }
  }

  // Wrapper function that uses the imported navigateBack
  function handleBackNavigation() {
    navigateBack();
  }

  function handleClose() {
    handleBackNavigation();
  }

  function getFullName(address = {}) {
    const first = address.first_name || "";
    const last = address.last_name || "";
    const combined = `${first} ${last}`.trim();
    return combined || "Customer";
  }

  function getAddressTag(address = {}) {
    if (address.address_type) {
      return formatTitle(address.address_type, 10);
    }
    if (address.company) {
      return formatTitle(address.company, 10);
    }
    if (address.default) {
      return "Home";
    }
    return null;
  }

  function selectAddress(addressId) {
    selectedId = addressId;
    actions.selectAddress(addressId);
    const selectedAddressObj = addresses.find((addr) => addr.id === addressId);
    if (selectedAddressObj) {
      setSelectedAddress(selectedAddressObj);
    }
  }

  async function startAddNew() {
    // Navigate directly to address form screen (explicit user action)
    // Matching React app: handleAddAddress() → setStep(4)
    // Set edit mode to false (adding new address)
    otpStoreActions.setIsEditAddress(false);
    otpStoreActions.setEditableAddress({});
    // Navigate directly to address form
    actions.setScreen("address-form");
  }

  function toggleDropdown(addressId, e) {
    e?.stopPropagation();
    if (e && typeof e.isTrusted === "boolean" && !e.isTrusted) return;
    openDropdownId = openDropdownId === addressId ? null : addressId;
  }

  function closeDropdown() {
    openDropdownId = null;
  }

  async function startEdit(address) {
    // Close dropdown first
    closeDropdown();
    // Navigate directly to address form screen (explicit user action)
    // Matching React app: handleEditAddress() → setStep(4)
    // Set edit mode to true with address data
    otpStoreActions.setIsEditAddress(true);
    otpStoreActions.setEditableAddress(address);
    // Navigate directly to address form
    actions.setScreen("address-form");
  }

  function normalizePhone(raw, includePlus = true) {
    if (!raw) return "";
    const trimmed = raw.toString().trim();
    if (trimmed.startsWith("+"))
      return includePlus ? trimmed : trimmed.slice(1);
    if (trimmed.startsWith("00")) {
      return includePlus ? `+${trimmed.slice(2)}` : trimmed.slice(2);
    }
    return includePlus ? `+${trimmed}` : trimmed;
  }

  function createAddressPayload(formValues, existingAddress = {}) {
    // For edit: keep existing fields (id, created_at, etc.) and update only changed fields
    // For add: create new address structure
    const isEdit = existingAddress && existingAddress.id;

    if (isEdit) {
      // Edit mode: spread existing address and update only changed fields
      return {
        ...existingAddress, // Keep all existing fields (id, created_at, etc.)
        first_name: formValues.firstName,
        last_name: formValues.lastName,
        phone: normalizePhone(formValues.phone),
        address1: formValues.address1,
        address2: formValues.address2 || "",
        city: formValues.city,
        province: formValues.state,
        zip: formValues.zip,
        company: formValues.company || "",
        address_type:
          formValues.addressType || existingAddress.address_type || "home",
        landmark: formValues.landmark ?? existingAddress.landmark ?? "",
        // Keep existing country fields if present, otherwise set defaults
        country: existingAddress.country || "India",
        country_code: existingAddress.country_code || "IN",
        country_code_v2:
          existingAddress.country_code_v2 ||
          existingAddress.country_code ||
          "IN",
        province_code: existingAddress.province_code || "",
        formatted:
          existingAddress.formatted ||
          `["${formValues.address1}", "${formValues.city}", "${formValues.state}", "${formValues.zip}"]`,
        formatted_area:
          existingAddress.formatted_area ||
          `${formValues.city}, ${formValues.state}`,
        updated_at: new Date().toISOString(),
      };
    } else {
      // Add mode: create new address structure
      const id = `addr-${Date.now()}`;
      return {
        id,
        first_name: formValues.firstName,
        last_name: formValues.lastName,
        phone: normalizePhone(formValues.phone),
        address1: formValues.address1,
        address2: formValues.address2 || "",
        city: formValues.city,
        province: formValues.state,
        zip: formValues.zip,
        country: "India",
        country_code: "IN",
        country_code_v2: "IN",
        province_code: "",
        company: formValues.company || "",
        address_type: formValues.addressType || "home",
        landmark: formValues.landmark || "",
        default: false,
        formatted: `["${formValues.address1}", "${formValues.city}", "${formValues.state}", "${formValues.zip}"]`,
        formatted_area: `${formValues.city}, ${formValues.state}`,
        updated_at: new Date().toISOString(),
      };
    }
  }

  function formatAddress(address) {
    return [
      address.address1,
      address.address2,
      address.landmark,
      address.city,
      address.province || address.state,
      address.zip,
    ]
      .filter(Boolean)
      .join(", ");
  }

  // Validate email field (React equivalent: desktopDeliveryAddressComponent.js validateField)
  function validateEmailField(value) {
    if (!value.trim()) {
      return "Email is required";
    }
    const emailRegex = /^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/;
    if (!emailRegex.test(value)) {
      return "Invalid email format";
    }
    return "";
  }

  // Handle email input change (React equivalent: desktopDeliveryAddressComponent.js handleInputChange)
  function handleEmailInputChange(e) {
    emailInput = e.target.value;
    continueError = ""; // Clear continue error when user types

    const fieldError = validateEmailField(emailInput);
    emailError = fieldError;
  }

  // Check if email field should be shown (React equivalent: desktopDeliveryAddressComponent.js email field condition)
  $: showEmailField =
    (settings?.preEmailMandatory && !customerEmail && !getCustomerEmail()) ||
    emailError === "Invalid email format" ||
    continueError?.includes("Email is required");

  // ⚡ CRITICAL: handleContinueClick - matches React app's desktopDeliveryAddressComponent.js exactly
  // React equivalent: handleContinueClick() → saves email FIRST, then handleContinue(), then updateShippingAddresses()
  async function handleContinueClick() {
    if (isContinuing) {
      return;
    }

    try {
      // Set loading state (React equivalent: setOtpData((prev) => ({ ...prev, isLoading: true })))
      isContinuing = true;
      continueError = "";
      actions.setLoading(true);

      // ⚡ Validate and save email FIRST (React equivalent: lines 417-424)
      // React app: if (settings?.preEmailMandatory) { validate + await setSessionValue }
      // React app: else if (formData?.email) { validate + await setSessionValue }

      if (settings?.preEmailMandatory) {
        // Validate form first
        emailError = validateEmailField(emailInput);
        if (emailError) {
          continueError = emailError;
          isContinuing = false;
          actions.setLoading(false);
          return;
        }

        // ⚡ CRITICAL: Save email to sessionStorage (React equivalent: await setSessionValue("customer-email", formData?.email))
        // Note: setCustomerEmail is synchronous, but we ensure it completes before proceeding
        if (emailInput.trim()) {
          setCustomerEmail(emailInput.trim()); // Save to sessionStorage
          actions.setCustomerEmail(emailInput.trim()); // Update store
          customerEmail = emailInput.trim();
          // Use Promise.resolve to match React's await pattern
          await Promise.resolve();
        }
      } else if (emailInput.trim()) {
        // Validate form first
        emailError = validateEmailField(emailInput);
        if (emailError) {
          continueError = emailError;
          isContinuing = false;
          actions.setLoading(false);
          return;
        }

        // ⚡ CRITICAL: Save email to sessionStorage (React equivalent: await setSessionValue("customer-email", formData?.email))
        // Note: setCustomerEmail is synchronous, but we ensure it completes before proceeding
        setCustomerEmail(emailInput.trim()); // Save to sessionStorage
        actions.setCustomerEmail(emailInput.trim()); // Update store
        customerEmail = emailInput.trim();
        // Use Promise.resolve to match React's await pattern
        await Promise.resolve();
      }

      // ⚡ Call handleContinue() - only after session is set (React equivalent: line 425)
      // This updates buyer identity via GraphQL
      await handleContinueInternal();

      // ⚡ REMOVED: saveShippingAddress API call
      // This API should only be called when:
      // 1. A new address is added (AddressFormScreen.svelte)
      // 2. An existing address is edited (AddressFormScreen.svelte)
      // It should NOT be called when just selecting an existing address
      // The API call is handled in AddressFormScreen.svelte when the form is submitted
    } catch (error) {

      // Determine error message based on error type
      let errorMessage = "Failed to continue. Please try again.";

      if (error.message) {
        if (
          error.message.includes("network") ||
          error.message.includes("fetch")
        ) {
          errorMessage =
            "Network error. Please check your connection and try again.";
        } else if (error.message.includes("timeout")) {
          errorMessage = "Request timed out. Please try again.";
        } else {
          errorMessage = error.message;
        }
      }

      continueError = errorMessage;

      // Auto-retry on network errors (up to MAX_RETRIES)
      if (
        retryCount < MAX_RETRIES &&
        (error.message?.includes("network") || error.message?.includes("fetch"))
      ) {
        retryCount++;
        setTimeout(() => {
          handleContinueClick();
        }, 2000 * retryCount); // Exponential backoff
      }
    } finally {
      isContinuing = false;
      actions.setLoading(false);
    }
  }

  // Retry handler for error display
  function handleRetry() {
    retryCount = 0;
    continueError = "";
    if (selectedId) {
      handleContinueClick();
    }
  }

  // Internal function that handles the actual continue logic (buyer identity update, cart attributes, etc.)
  // React equivalent: handleContinue() from otpStore.js
  async function handleContinueInternal() {

    // Find selected address - handle null IDs for new addresses
    const selectedAddress =
      selectedId === null
        ? addresses.find((addr) => addr.id === null) // Handle new addresses with null ID
        : addresses.find((addr) => addr.id === selectedId); // Handle addresses with actual IDs

    if (!selectedAddress) {

      throw new Error("Please select an address to continue.");
    }

    if (!cartData?.token) {

      throw new Error(
        "Cart information not available. Please refresh the page.",
      );
    }

    // Get email from multiple sources (prefer otpStore over sessionStorage)
    let emailForIdentity =
      emailInput.trim() ||
      customerEmail ||
      get(otpStore).verifiedEmail ||
      getCustomerEmail() ||
      null;

    // Check additional sources if still not found
    if (
      !emailForIdentity &&
      typeof window.parent !== "undefined" &&
      window.parent.sessionStorage
    ) {
      try {
        emailForIdentity =
          window.parent.sessionStorage.getItem("customer-email") ||
          window.parent.sessionStorage.getItem("cod_king_customer_email") ||
          null;

        // Check preOrderOtpResponse from sessionStorage
        if (!emailForIdentity) {
          const otpResponseStr = window.parent.sessionStorage.getItem(
            "preOrderOtpResponse",
          );
          if (otpResponseStr) {
            try {
              const parsed = JSON.parse(otpResponseStr);
              emailForIdentity = parsed.email || null;
            } catch (e) {
              // Ignore parse errors
            }
          }
        }
      } catch (e) {

      }
    }

    // Check store's preOrderOtpResponse as last resort
    if (!emailForIdentity) {
      const preOrderResponse = get(appStore).preOrderOtpResponse || {};
      emailForIdentity =
        preOrderResponse.email ||
        preOrderResponse.customer?.email ||
        preOrderResponse.customerEmail ||
        preOrderResponse.customer_email ||
        null;
    }

    const verifiedNumberData = getSessionValue("verifiedNumberData");
    const verifiedPhoneNumber = verifiedNumberData?.otpVerifiedPhoneNumber;
    const phoneForIdentity = normalizePhone(
      verifiedPhoneNumber || phoneNumber || selectedAddress.phone,
      false,
    );
    if (!phoneForIdentity) {
      throw new Error(
        "Verified phone number missing. Please restart the flow.",
      );
    }
    emailForIdentity = String(emailForIdentity || "").trim();
    if (isPreEmailMandatory(settings)) {
      if (!emailForIdentity || isNoEmailPlaceholder(emailForIdentity)) {
        emailForIdentity = null;
      }
    } else if (!emailForIdentity) {
      emailForIdentity = getNoEmailPlaceholder(phoneForIdentity) || null;
    }

    // Build buyer identity payload (pass verifiedEmail so it's used if address has no email)
    const buyerIdentityPayload = buildBuyerIdentityPayload(
      {
        email: emailForIdentity,
        first_name: selectedAddress.first_name || "",
        last_name: selectedAddress.last_name || "",
        address1: selectedAddress.address1 || "",
        address2: selectedAddress.address2 || "",
        city: selectedAddress.city || "",
        state: selectedAddress.province || selectedAddress.state || "",
        zip: selectedAddress.zip || "",
      },
      phoneForIdentity,
      get(otpStore).verifiedEmail,
    );

    // Set buyer identity in store and persist email for later (e.g. second OTP → address screen)
    if (emailForIdentity) otpStoreActions.setVerifiedEmail(emailForIdentity);
    otpStoreActions.setBuyerIdentity(buyerIdentityPayload);

    // Update cart with buyer identity (matching React app)
    const currentCartData = get(otpStore).currentCartData;
    const sessionCart = getSessionValue("shopify_cart");
    const cartToken = currentCartData?.token || sessionCart?.token;

    // Background the buyer-identity save only when a partial-payment step
    // precedes /checkout, giving the slow Storefront mutation time to land.
    // When partial payment is off the next stop is /checkout, so we must await —
    // otherwise the redirect cancels the in-flight mutation and the checkout is
    // not prefilled (this also covers the default first prefilled address).
    const isIndianUser = isIndianPhoneNumber(
      verifiedPhoneNumber || phoneForIdentity,
      get(appStore)?.countryCallingCode,
    );
    const fastRedirect =
      isIndianUser &&
      isPrefilledAddressEnabledForButton &&
      partialPaymentEnabledForButton;

    if (cartToken) {
      const cartId = getStorefrontCartId(cartToken);

      if (cartId) {
        const saveBuyerIdentity = updateBuyerIdentity(cartId, buyerIdentityPayload)
          .then((updatedCart) => {
            // Store the updated checkout URL if available (contains updated address)
            if (updatedCart?.checkoutUrl) {
              setSessionValue("updated_checkout_url", updatedCart.checkoutUrl);
            }
          })
          .catch(() => {
            // Don't throw - address selection should still work even if cart update fails
          });

        if (!fastRedirect) {
          await saveBuyerIdentity;
          // Small delay to ensure update propagates to Shopify's systems
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      } else {

      }
    } else {

    }

    // ⚡ Store selected address in sessionStorage (notifik-js-app equivalent)
    if (typeof window.parent !== "undefined" && window.parent.sessionStorage) {
      window.parent.sessionStorage.setItem(
        "cod_king_selected_address",
        JSON.stringify(selectedAddress),
      );
    }

    try {
      window.dispatchEvent(new CustomEvent("codk-address-updated"));
    } catch (_) {}

    // ⚡ Update cart attributes (notifik-js-app equivalent: addCartAttributeAndRedirect)
    try {
      const deviceId = getMachineId();
      const verifiedData =
        typeof window.parent !== "undefined" && window.parent.sessionStorage
          ? JSON.parse(
              window.parent.sessionStorage.getItem("verifiedNumberData") ||
                "{}",
            )
          : {};
      const verifiedPhoneNumber =
        verifiedData.otpVerifiedPhoneNumber || phoneForIdentity;
      const phoneNumberForCart = verifiedPhoneNumber
        .replace(/\+/g, "")
        .replace(/undefined/g, "");

      // ⚡ Update cart attributes via AJAX API
      const attributes = {
        _otpVerifiedPhoneNumber: phoneNumberForCart,
        _codkSessionId: deviceId,
        // Store address info in cart note for reference (though shipping address is set via GraphQL)
        _selectedAddress: JSON.stringify({
          firstName: selectedAddress.first_name,
          lastName: selectedAddress.last_name,
          address1: selectedAddress.address1,
          address2: selectedAddress.address2,
          city: selectedAddress.city,
          province: selectedAddress.province || selectedAddress.state,
          zip: selectedAddress.zip,
          country: selectedAddress.country || "India",
        }),
      };

      await cartFetch("/cart/update.js", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ attributes }),
      });

      // Force refresh to update UI and otpStore
      // await getCart(true);
    } catch (cartError) {

    }

    // Update state
    setSessionAddressCompleted(true);
    otpStoreActions.setIsPrefilledAddressCompleted(true);
    actions.selectAddress(selectedId);

    // ⚡ CRITICAL: Ensure state update propagates before determining next step
    // Use microtask delay to ensure store update is fully processed
    await new Promise((resolve) => setTimeout(resolve, 0));

    // ⚡ CRITICAL: Normalize partialPaymentEnabled setting (matching OtpInput.svelte)
    // Handle both camelCase and snake_case, and boolean/string values
    const partialPaymentEnabled =
      settings?.partialPaymentEnabled === true ||
      settings?.partialPaymentEnabled === "true" ||
      settings?.partial_payment_enabled === true ||
      settings?.partial_payment_enabled === "true";

    // Navigate to next screen based on flow

    // ALL screen changes must go through setScreenFromStep
    // getCurrentStep() will now read fresh state with isPrefilledAddressCompleted = true
    await getCurrentStep();
  }

  $: displayOrderTotal = formatCurrency(
    orderSummary.total,
    orderSummary.currency,
  );
  $: displayOriginalTotal = formatCurrency(
    orderSummary.originalTotal,
    orderSummary.currency,
  );
  $: if (settings) {
    initializeStoreInfo();
  }

  // Reactive statements for button text
  $: partialPaymentEnabledForButton =
    settings?.partialPaymentEnabled === true ||
    settings?.partialPaymentEnabled === "true" ||
    settings?.partial_payment_enabled === true ||
    settings?.partial_payment_enabled === "true";

  $: isPrefilledAddressEnabledForButton =
    settings?.isPrefilledAddressEnabled === true ||
    settings?.isPrefilledAddressEnabled === "true" ||
    settings?.is_prefilled_address_enabled === true ||
    settings?.is_prefilled_address_enabled === "true";

  // Check if cart is ready (both token and isCartReady flag)
  $: cartIsReady = $otpStore.isCartReady && cartData?.token;

  $: isCartReady = $otpStore.isCartReady || false;

  // ---------------------------------------------------------------------------
  // Dynamic Progress Bar (hide disabled steps)
  // ---------------------------------------------------------------------------
  const isTruthySetting = (value, defaultValue = true) => {
    if (value === true || value === 1 || value === "true" || value === "1")
      return true;
    if (value === false || value === 0 || value === "false" || value === "0")
      return false;
    return defaultValue;
  };

  // Mobile step (OTP/phone) can be disabled for some merchants
  $: isMobileStepEnabled = isTruthySetting(
    settings?.enablePreOrderOtp ?? settings?.enable_pre_order_otp,
    true,
  );

  // Address step depends on prefilled address setting
  $: isAddressStepEnabled = isTruthySetting(
    settings?.isPrefilledAddressEnabled ??
      settings?.is_prefilled_address_enabled,
    true,
  );

  $: progressScreens = [
    ...(isMobileStepEnabled ? [{ key: "mobile", label: "Mobile" }] : []),
    ...(isAddressStepEnabled ? [{ key: "address", label: "Address" }] : []),
    { key: "pay", label: "Pay" },
  ];

  $: progressActiveScreen = progressScreens.some((s) => s.key === "address")
    ? "address"
    : progressScreens[0]?.key || "pay";

  $: showProgressBar = progressScreens.length > 1;

  $: buttonText = isContinuing
    ? "Saving..."
    : !isCartReady
      ? "Loading..."
      : isPrefilledAddressEnabledForButton && partialPaymentEnabledForButton
        ? "Continue to Payment"
        : "Continue to Checkout";
</script>

<ScreenLayout
  promoBannerText={settings?.promoBannerText}
  showPromoBanner={!!settings?.promoBannerText}
>
  <ScreenHeader
    {storeLogoUrl}
    {storeName}
    backAction={handleBackNavigation}
    showProgress={showProgressBar}
  >
    <ProgressBar
      slot="progress"
      activeScreen={progressActiveScreen}
      screens={progressScreens}
    />
  </ScreenHeader>

  <ScreenContent>
    {#if !isCartReady}
      <CartLoadingScreen />
    {:else}
      <div class="address-content">
        <div class="address-summary-card">
          <div class="summary-icon">
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#404040"
              stroke-width="1.5"
            >
              <path
                d="M12 21s-8-4.438-8-11a8 8 0 0 1 16 0c0 6.562-8 11-8 11z"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
              <circle cx="12" cy="10" r="3" />
            </svg>
          </div>
          <div class="summary-text">
            <span class="summary-title">Your Address</span>
            <span class="summary-subtitle">
              {#if addresses.length}
                {addresses.length} saved {addresses.length === 1
                  ? "address"
                  : "addresses"}
              {:else}
                No saved addresses yet
              {/if}
            </span>
          </div>
        </div>

        <div class="delivery-header">
          <div class="delivery-title">Delivery Address</div>
          <button class="add-address-button" on:click={startAddNew}>
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#404040"
              stroke-width="2"
            >
              <line x1="12" y1="5" x2="12" y2="19" />
              <line x1="5" y1="12" x2="19" y2="12" />
            </svg>
            <span>Add Address</span>
          </button>
        </div>

        {#if showEmailField}
          <div class="email-field">
            <label for="email-input" class="email-label">Email Address</label>
            <input
              id="email-input"
              type="email"
              class="email-input"
              class:has-error={!!emailError || continueError?.includes("Email")}
              placeholder="Enter Email Address"
              value={emailInput}
              on:input={handleEmailInputChange}
            />
            {#if emailError}
              <div class="form-error">{emailError}</div>
            {/if}
          </div>
        {/if}

        <div class="address-list">
          {#if !addresses.length}
            <div class="empty-state-card">
              <p>No saved addresses yet. Add one to continue.</p>
              <button on:click={startAddNew}>Add your first address</button>
            </div>
          {:else}
            {#each showAllAddresses ? addresses : addresses.slice(0, 2) as address (address.id)}
              <div
                class="address-card"
                class:selected={selectedId === address.id}
                role="button"
                tabindex="0"
                on:click={(e) => {

                  selectAddress(address.id);
                }}
                on:keydown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();

                    selectAddress(address.id);
                  }
                }}
              >
                <div class="card-header">
                  <div class="card-recipient">
                    <div class="recipient-icon">
                      <svg
                        width="18"
                        height="18"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="#404040"
                        stroke-width="1.5"
                      >
                        <path
                          d="M3 9.5L12 3l9 6.5V21a.5.5 0 0 1-.5.5h-5a.5.5 0 0 1-.5-.5v-5h-6v5a.5.5 0 0 1-.5.5h-5A.5.5 0 0 1 3 21V9.5z"
                          stroke-linejoin="round"
                        />
                      </svg>
                    </div>
                    <div class="recipient-text">
                      <span class="recipient-name">{getFullName(address)}</span>
                      {#if getAddressTag(address)}
                        <span class="recipient-tag"
                          >{getAddressTag(address)}</span
                        >
                      {/if}
                    </div>
                  </div>
                  <div class="more-button-wrapper">
                    <button
                      class="more-button"
                      aria-label="More options"
                      on:click|stopPropagation={(e) =>
                        toggleDropdown(address.id, e)}
                    >
                      <span></span>
                      <span></span>
                      <span></span>
                    </button>
                    {#if openDropdownId === address.id}
                      <div
                        class="dropdown-menu"
                        role="menu"
                        tabindex="-1"
                        on:click|stopPropagation
                        on:keydown={(e) => {
                          if (e.key === "Escape") closeDropdown();
                        }}
                        on:mouseleave={closeDropdown}
                      >
                        <button
                          type="button"
                          class="dropdown-item"
                          role="menuitem"
                          on:click|stopPropagation={() => startEdit(address)}
                        >
                          <svg
                            class="edit-icon"
                            width="16"
                            height="16"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="var(--color-blue)"
                            stroke-width="1.5"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                          >
                            <path
                              d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"
                            ></path>
                            <path
                              d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"
                            ></path>
                          </svg>
                          <span>Edit</span>
                        </button>
                      </div>
                    {/if}
                  </div>
                </div>

                <div class="card-line">
                  <svg
                    width="14"
                    height="14"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#a1a1aa"
                    stroke-width="1.5"
                  >
                    <path
                      d="M12 21s-8-4.438-8-11a8 8 0 0 1 16 0c0 6.562-8 11-8 11z"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                    <circle cx="12" cy="10" r="3" />
                  </svg>
                  <p>{formatAddress(address)}</p>
                </div>

                <div class="card-line">
                  <svg
                    width="14"
                    height="14"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#a1a1aa"
                    stroke-width="1.5"
                  >
                    <path
                      d="M4 4h4l2 5-3 2a12 12 0 0 0 6 6l2-3 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 2 6a2 2 0 0 1 2-2z"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                  <p>{address.phone || phoneNumber}</p>
                </div>

                <div class="card-actions">
                  <button
                    class="deliver-button"
                    class:selected={selectedId === address.id}
                    on:click|stopPropagation={(e) => {

                      selectAddress(address.id);
                    }}
                  >
                    Deliver Here
                  </button>
                </div>
              </div>
            {/each}
          {/if}
        </div>

        {#if addresses.length > 2 && !showAllAddresses}
          <button
            class="view-all-button"
            on:click={() => (showAllAddresses = true)}
          >
            View All ({addresses.length - 2} more)
          </button>
        {/if}

        <ErrorDisplay
          error={continueError}
          onRetry={handleRetry}
          compact={true}
        />

        <div class="footer-container">
          <Footer />
        </div>
      </div>
    {/if}
  </ScreenContent>

  <!-- Sticky Continue Button with Logout -->
  {#if isCartReady}
    <div class="sticky-button-container">
      <Button
        variant="primary"
        loading={isContinuing || !isCartReady}
        on:click={handleContinueClick}
        fullWidth={true}
        disabled={isContinuing || !isCartReady || !hasSelectedAddress}
      >
        {buttonText}
      </Button>
      <LoginInfoSection />
    </div>
  {/if}
</ScreenLayout>

<script>
  /**
   * AddressSelectionContent - Address selection content (without ScreenLayout wrapper)
   * Used inside BottomSlider component
   * @component
   */
  import { onMount, onDestroy } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { get } from "svelte/store";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import {
    formatCurrency,
    formatTitle,
    formatPhoneNumber,
    checkImageAspectRatio,
    mapCartToOrderSummary,
    getShopifyRootPath,
  } from "../../utils/helpers.js";
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
    isOptimizedBuyNowEnabled,
  } from "../../services/sessionService.js";

  import { saveShippingAddress } from "../../services/api.js";
  import ErrorDisplay from "../shared/ErrorDisplay.svelte";
  import { handleBackNavigation as navigateBack } from "../../utils/navigationUtils.js";
  import { getCurrentStep } from "../../utils/stepUtils.js";
  import CartLoadingScreen from "../shared/CartLoadingScreen.svelte";
  import "../../styles/components/AddressSelection.css";
  import "../../styles/components/AddressSelection.desktop.css";
  import "../../styles/components/AddressSelection.mobile.css";
  import { createTranslator } from "../../utils/uiCustomization.js";

  // Merchant copy resolver (ui_customization → legacy setting → default)
  $: T = createTranslator($settingsStore);

  let storeLogoUrl = null;
  let storeLogoType = "fallback";
  let storeName = "";
  let isWideLogo = false;
  let lastLogoSource = null;

  let addresses = [];
  let selectedId = null;

  $: hasSelectedAddress =
    selectedId !== undefined &&
    ((selectedId === null && addresses.some((addr) => addr.id === null)) ||
      (selectedId !== null &&
        addresses.some((addr) => addr.id === selectedId)));

  let continueError = "";

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
  let cart = null;
  let phoneNumber = "";
  let customerEmail = "";
  let showAllAddresses = false;
  let openDropdownId = null;
  let selectedShippingHandle = null;

  $: verifiedData = getSessionValue("verifiedNumberData", null);
  $: isOtpVerified = !!(verifiedData && verifiedData.isOTPVerified);

  let unsubscribe = null;
  let handleClickOutside = null;

  onMount(() => {
    unsubscribe = appStore.subscribe((state) => {
      settings = state.settings;
      cart = state.cart || cart;
      phoneNumber = state.phoneNumber || phoneNumber;
      customerEmail = state.customerEmail || customerEmail;

      if (state.addresses && state.addresses.length) {
        addresses = [...state.addresses];
        selectedId =
          state.selectedAddressId || selectedId || addresses[0]?.id || null;
      }
    });
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
    selectedShippingHandle = getSessionValue("selected_shipping_handle");
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
    const preOrderOtpResponse = getSessionValue("preOrderOtpResponse") || {};
    const sessionAddresses = getShippingAddresses() || [];
    const addressesFromOtp =
      preOrderOtpResponse?.shippingAddress ??
      preOrderOtpResponse?.shippingAddresses ??
      preOrderOtpResponse?.shipping_addresses;
    const otpList = Array.isArray(addressesFromOtp) ? addressesFromOtp : [];

    if (sessionAddresses.length === 0 && otpList.length > 0) {
      setShippingAddresses(otpList);
      actions.setAddresses(otpList);
      addresses = [...otpList];
    } else if (sessionAddresses.length > 0 && addresses.length === 0) {
      actions.setAddresses(sessionAddresses);
      addresses = [...sessionAddresses];
    } else {
      addresses = sessionAddresses ? [...sessionAddresses] : [];
    }

    if (addresses.length > 0) {
      const storeSelectedId = get(appStore).selectedAddressId;
      if (
        storeSelectedId !== undefined &&
        storeSelectedId !== null &&
        addresses.some((a) => a.id === storeSelectedId)
      ) {
        selectedId = storeSelectedId;
      } else {
        selectedId = addresses[0]?.id || null;
        actions.selectAddress(selectedId);
      }

      if (selectedId !== undefined) {
        otpStoreActions.setSelectedAddress(selectedId);
        const selectedAddressObj = addresses.find(
          (addr) => addr.id === selectedId,
        );
        if (selectedAddressObj) {
          setSelectedAddress(selectedAddressObj);
        }
      }
    } else {
      actions.setScreen("address-form");
      otpStoreActions.setSelectedAddress(null);
    }

    const sessionEmail = getSessionValue("customer-email");
    if (sessionEmail) {
      emailInput = sessionEmail;
      customerEmail = sessionEmail;
      actions.setCustomerEmail(sessionEmail);
    }
  }

  function handleClose() {
    navigateBack();
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
    return "Home";
  }

  async function selectAddress(addressId) {
    if (isContinuing) return;
    isContinuing = true;
    selectedId = addressId;
    actions.selectAddress(addressId);
    otpStoreActions.setSelectedAddress(addressId);
    const selectedAddressObj = addresses.find((addr) => addr.id === addressId);
    if (selectedAddressObj) {
      setSelectedAddress(selectedAddressObj);
      otpStore.setCalculatedTaxData(null);
    }

    // Persist selection + mark the address step complete so navigation advances
    setShippingAddresses(addresses);
    setSessionAddressCompleted(true);
    otpStoreActions.setIsPrefilledAddressCompleted(true);

    // Fire the buyer-identity update job in the background (do not await)
    otpStore.handleContinue();

    try {
      // Close the address screen immediately and show the next screen (payment)
      await getCurrentStep();
    } catch (error) {
      isContinuing = false;
    }
  }

  function selectShippingOnAddress(handle) {
    selectedShippingHandle = handle;
    setSessionValue("selected_shipping_handle", handle);
    otpStore.setSelectedShippingHandle(handle);
  }

  async function startAddNew() {
    otpStoreActions.setIsEditAddress(false);
    otpStoreActions.setEditableAddress({});
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
    closeDropdown();
    otpStoreActions.setIsEditAddress(true);
    otpStoreActions.setEditableAddress(address);
    actions.setScreen("address-form");
  }

  async function deleteAddress(address) {
    closeDropdown();
    if (isContinuing || !address) return;

    const remaining = addresses.filter((a) => a.id !== address.id);
    addresses = remaining;
    setShippingAddresses(remaining);
    actions.setAddresses(remaining);

    if (selectedId === address.id) {
      selectedId = remaining[0]?.id ?? null;
      actions.selectAddress(selectedId);
      otpStoreActions.setSelectedAddress(selectedId);
      const sel = remaining.find((a) => a.id === selectedId);
      if (sel) setSelectedAddress(sel);
    }

    try {
      const phone = verifiedData?.otpVerifiedPhoneNumber || phoneNumber || "";
      await saveShippingAddress({
        phone,
        email: customerEmail,
        shippingAddresses: remaining,
      });
    } catch (_e) {}

    if (remaining.length === 0) {
      actions.setScreen("address-form");
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

  function handleEmailInputChange(e) {
    emailInput = e.target.value;
    continueError = "";

    const fieldError = validateEmailField(emailInput);
    emailError = fieldError;
  }

  $: showEmailField =
    (settings?.preEmailMandatory && !customerEmail && !getCustomerEmail()) ||
    emailError === "Invalid email format" ||
    continueError?.includes("Email is required");

  async function handleContinueClick() {
    if (isContinuing) {
      return;
    }

    try {
      isContinuing = true;
      continueError = "";
      actions.setLoading(true);

      if (settings?.preEmailMandatory) {
        emailError = validateEmailField(emailInput);
        if (emailError) {
          continueError = emailError;
          isContinuing = false;
          actions.setLoading(false);
          return;
        }

        if (emailInput.trim()) {
          setCustomerEmail(emailInput.trim());
          actions.setCustomerEmail(emailInput.trim());
          customerEmail = emailInput.trim();
          await Promise.resolve();
        }
      } else if (emailInput.trim()) {
        emailError = validateEmailField(emailInput);
        if (emailError) {
          continueError = emailError;
          isContinuing = false;
          actions.setLoading(false);
          return;
        }

        setCustomerEmail(emailInput.trim());
        actions.setCustomerEmail(emailInput.trim());
        customerEmail = emailInput.trim();
        await Promise.resolve();
      }

      await handleContinueInternal();
    } catch (error) {
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

      if (
        retryCount < MAX_RETRIES &&
        (error.message?.includes("network") || error.message?.includes("fetch"))
      ) {
        retryCount++;
        setTimeout(() => {
          handleContinueClick();
        }, 2000 * retryCount);
      }
    } finally {
      isContinuing = false;
      actions.setLoading(false);
    }
  }

  function handleRetry() {
    retryCount = 0;
    continueError = "";
    if (selectedId) {
      handleContinueClick();
    }
  }

  async function handleContinueInternal() {
    const selectedAddress =
      selectedId === null
        ? addresses.find((addr) => addr.id === null)
        : addresses.find((addr) => addr.id === selectedId);

    if (!selectedAddress) {
      throw new Error("Please select an address to continue.");
    }
    setShippingAddresses(addresses);
    setSelectedAddress(selectedAddress);
    actions.selectAddress(selectedId);
    otpStoreActions.setSelectedAddress(selectedId);
    await otpStore.handleContinue();

    setSessionAddressCompleted(true);
    otpStoreActions.setIsPrefilledAddressCompleted(true);
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

  $: codFormEnabledForIntro =
    settings?.codFormEnabled === true ||
    settings?.codFormEnabled === "true" ||
    settings?.cod_form_enabled === true ||
    settings?.cod_form_enabled === "true";

  $: hasWidgetPaymentProvider = (() => {
    let provider =
      settings?.privatePaymentProvider ?? settings?.private_payment_provider;
    if (typeof provider === "string") {
      try {
        provider = JSON.parse(provider);
      } catch {
        provider = /razorpay|api_key/.test(provider)
          ? { name: "razorpay" }
          : null;
      }
    }
    return !!(
      provider &&
      typeof provider === "object" &&
      (provider.name ||
        provider.api_key ||
        provider.api_key_id ||
        provider.secret)
    );
  })();

  $: introPhone = verifiedData?.otpVerifiedPhoneNumber
    ? formatPhoneNumber(verifiedData.otpVerifiedPhoneNumber)
    : formatPhoneNumber(phoneNumber, $appStore?.countryCode);

  $: introKey =
    codFormEnabledForIntro ||
    hasWidgetPaymentProvider ||
    partialPaymentEnabledForButton
      ? "addr_intro"
      : "addr_intro_checkout";

  $: introParts =
    introPhone && addresses.length ? T(introKey).split("{{phone}}") : [];

  $: isCartReady = $otpStore.isCartReady || false;
  $: optimizedBuyNow = ($otpStore.settings, isOptimizedBuyNowEnabled());

  $: buttonText = isContinuing
    ? "Saving..."
    : !optimizedBuyNow && !isCartReady
      ? "Loading..."
      : isPrefilledAddressEnabledForButton && partialPaymentEnabledForButton
        ? "Continue to Payment"
        : "Continue to Checkout";
</script>

{#if !optimizedBuyNow && !isCartReady}
  <CartLoadingScreen />
{:else}
  <div class="saved-address-body">
    {#if introParts.length}
      <p class="saved-address-intro">
        {introParts[0]}{#if introParts.length > 1}<strong
            class="saved-address-intro-phone">{introPhone}</strong
          >{introParts[1]}{/if}
      </p>
    {/if}

    <div class="saved-address-add-row">
      <button
        type="button"
        class="saved-address-add-btn"
        on:click={startAddNew}
      >
        {T("addr_add_new")}
      </button>
    </div>

    <!-- {#if showEmailField}
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
    {/if} -->

    <div class="saved-address-list">
      {#if !addresses.length}
        <div class="empty-state-card">
          <p>{T("addr_none_saved")}</p>
          <button on:click={startAddNew}>{T("addr_add_first")}</button>
        </div>
      {:else}
        {#each addresses as address (address.id)}
          <div
            class="saved-address-card"
            class:selected={selectedId === address.id}
            role="button"
            tabindex="0"
            on:click={() => selectAddress(address.id)}
            on:keydown={(e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                selectAddress(address.id);
              }
            }}
          >
            <div class="saved-address-radio" aria-hidden="true">
              <span
                class="saved-address-circle"
                class:checked={selectedId === address.id}
              ></span>
            </div>

            <div class="saved-address-content">
              <p class="saved-address-name">
                {getFullName(address)}
                {#if getAddressTag(address)}
                  <span class="saved-address-pill">{getAddressTag(address)}</span>
                {/if}
              </p>
              <p class="saved-address-detail">{formatAddress(address)}</p>
              {#if address.email || customerEmail}
                <p class="saved-address-detail">
                  {address.email || customerEmail}
                </p>
              {/if}
            </div>

            <div class="more-button-wrapper saved-address-more">
              <button
                type="button"
                class="more-button"
                aria-label="More options"
                aria-haspopup="menu"
                aria-expanded={openDropdownId === address.id}
                on:click|stopPropagation={(e) => toggleDropdown(address.id, e)}
              >
                <img
                  class="more-button-icon"
                  src="https://cdn.shopify.com/s/files/1/0776/0058/7973/files/threeDot.svg?v=1785228213"
                  alt=""
                />
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
                    <span>{T("addr_edit")}</span>
                  </button>
                </div>
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </div>

    <ErrorDisplay error={continueError} onRetry={handleRetry} compact={true} />
  </div>
{/if}

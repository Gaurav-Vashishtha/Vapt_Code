<script>
  import { onMount } from "svelte";
  import { settingsStore } from "../../stores/settingsStore.js";
  import { get } from "svelte/store";
  import { appStore, actions } from "../../stores/buttonManager.js";
  import otpStore, { otpStoreActions } from "../../stores/otpStore.js";
  import AddressForm from "../AddressForm.svelte";
  import ErrorDisplay from "../shared/ErrorDisplay.svelte";
  import ScreenContent from "../layouts/ScreenContent.svelte";
  import OrderSummaryCard from "../sections/OrderSummaryCard.svelte";
  import CartLoadingScreen from "../shared/CartLoadingScreen.svelte";
  import { handleBackNavigation as navigateBack } from "../../utils/navigationUtils.js";
  import { formatTitle, checkImageAspectRatio } from "../../utils/helpers.js";
  import { getCurrentStep } from "../../utils/stepUtils.js";
  import { saveShippingAddress } from "../../services/api.js";
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
  import { updateBuyerIdentity } from "../../services/cartService.js";
  import {
    getStorefrontCartId,
    buildBuyerIdentityPayload,
  } from "../../utilities/otpUtils.js";
  import "../../styles/components/screens/AddressFormScreen.css";
  import "../../styles/components/screens/AddressFormScreen.mobile.css";
  import "../../styles/components/screens/AddressFormScreen.desktop.css";

  const addressTemplate = {
    address1: "",
    address2: "",
    city: "",
    company: null,
    coordinates_validated: null,
    country: "India",
    country_code: "IN",
    country_code_v2: "IN",
    formatted: "",
    formatted_area: "",
    id: null,
    first_name: "",
    last_name: "",
    latitude: null,
    longitude: null,
    phone: "",
    province: "",
    province_code: "",
    zip: "",
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  let storeLogoUrl = null;
  let storeName = "";
  let settings = null;
  let phoneNumber = "";
  let customerEmail = "";
  let formMode = "add";
  let editableAddress = null;
  let formEmail = "";
  let formError = "";
  let isSavingAddress = false;

  $: verifiedData = getSessionValue("verifiedNumberData", null);
  $: isOtpVerified = !!(verifiedData && verifiedData.isOTPVerified);
  $: isCartReady = $otpStore.isCartReady || false;
  $: optimizedBuyNow = ($otpStore.settings, isOptimizedBuyNowEnabled());

  onMount(() => {
    const appState = get(appStore);
    const otpState = get(otpStore);
    settings = appState.settings;
    phoneNumber = appState.phoneNumber || "";
    customerEmail = getCustomerEmail() || appState.customerEmail || "";

    if (otpState.isEditAddress && otpState.editableAddress) {
      formMode = "edit";
      editableAddress = otpState.editableAddress;
      formEmail = customerEmail || editableAddress?.email || "";
    } else {
      formMode = "add";
      editableAddress = null;
      formEmail = "";
    }

    initializeStoreInfo();
  });

  async function initializeStoreInfo() {
    if (!settings) return;

    const preV2Title = settings.preV2Title;
    const shopDomain = window.parent?.Shopify?.shop || window.Shopify?.shop;
    const rawName =
      preV2Title || shopDomain?.replace(".myshopify.com", "") || "Store";
    storeName = formatTitle(rawName, 30);

    const brandLogoUrl = settings.brandLogoUrl || settings.brand_logo_url;
    if (brandLogoUrl) {
      try {
        await checkImageAspectRatio(brandLogoUrl);
        storeLogoUrl = brandLogoUrl;
      } catch (error) {

        storeLogoUrl = null;
      }
    } else {
      storeLogoUrl = null;
    }
  }

  function handleBackNavigation() {
    const state = get(appStore);
    const addresses = getShippingAddresses() || state.addresses || [];

    otpStoreActions.setIsEditAddress(false);
    otpStoreActions.setEditableAddress({});
    navigateBack();
  }

  async function processAddressSubmission(formData) {
    const verifiedNumberData = getSessionValue("verifiedNumberData");
    const verifiedPhoneNumber = verifiedNumberData?.otpVerifiedPhoneNumber;

    if (!verifiedPhoneNumber) {
      throw new Error(
        "Verified phone number missing. Please restart the flow.",
      );
    }

    const selectedForPayload = {
      email: formData.email,
      first_name: formData.firstName,
      last_name: formData.lastName,
      address1: formData.address1,
      address2: formData.address2 || "",
      city: formData.city,
      state: formData.state,
      zip: formData.zip,
    };

    try {
      if (formData.email) otpStoreActions.setVerifiedEmail(formData.email);
      const buyerIdentityPayload = buildBuyerIdentityPayload(
        selectedForPayload,
        verifiedPhoneNumber,
        get(otpStore).verifiedEmail,
      );
      otpStoreActions.setBuyerIdentity(buyerIdentityPayload);
      const currentCartData = get(otpStore).currentCartData;
      const sessionCart = getSessionValue("shopify_cart");
      const cartToken = currentCartData?.token || sessionCart?.token;

      if (cartToken) {
        const cartId = getStorefrontCartId(cartToken);

        if (cartId) {
          try {
            const updatedCart = await updateBuyerIdentity(
              cartId,
              buyerIdentityPayload,
            );
            if (updatedCart?.checkoutUrl) {
              setSessionValue("updated_checkout_url", updatedCart.checkoutUrl);
            }
            await new Promise((resolve) => setTimeout(resolve, 100));
          } catch (error) {
          }
        } else {

        }
      } else {

      }

      otpStoreActions.setIsPrefilledAddressCompleted(true);
      setSessionAddressCompleted(true);
    } catch (error) {

      throw error;
    }
  }

  async function handleFormSave(event) {
    const {
      firstName,
      lastName,
      phone: phoneFromForm,
      email: emailForApi,
      address1,
      address2,
      city,
      state,
      zip,
      company,
      addressType,
      landmark,
    } = event.detail || {};

    if (isSavingAddress) {
      return;
    }
    isSavingAddress = true;
    formError = "";
    actions.setLoading(true);

    try {
      const [first_name, last_name] = `${firstName} ${lastName}`
        .trim()
        .split(" ");

      const getProvinceCode = (stateName) => {
        if (!stateName) return "";
        return stateName.trim().slice(0, 2).toUpperCase();
      };

      const filledAddress = {
        id:
          formMode === "edit" && editableAddress
            ? editableAddress.id
            : `addr-${Date.now()}`,
        first_name: first_name || "",
        last_name: last_name || "",
        phone: phoneFromForm || phoneNumber || "",
        address1: address1.trim(),
        address2: (address2 || "").trim(),
        city: city.trim(),
        province: state.trim(),
        zip: zip.trim(),
        country: "India",
        country_code: "IN",
        country_code_v2: "IN",
        province_code: getProvinceCode(state),
        formatted: `["${address1.trim()}", "${city.trim()}", "${state.trim()}", "${zip.trim()}"]`,
        formatted_area: `${city.trim()}, ${state.trim()}`,
        created_at:
          formMode === "edit" && editableAddress
            ? editableAddress.created_at
            : new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };

      let shippingAddresses = getShippingAddresses() || [];

      if (formMode === "edit" && editableAddress) {
        const index = shippingAddresses.findIndex(
          (address) => address.id === editableAddress.id,
        );
        if (index !== -1) {
          shippingAddresses[index] = {
            ...editableAddress,
            ...filledAddress,
            id: editableAddress.id,
            created_at: editableAddress.created_at,
          };
        }
      } else {
        shippingAddresses.push(filledAddress);
      }

      setShippingAddresses(shippingAddresses);

      const formData = {
        firstName,
        lastName,
        email: emailForApi,
        address1,
        address2,
        city,
        state,
        zip,
      };
      await processAddressSubmission(formData);

      const verifiedNumberData = getSessionValue("verifiedNumberData");
      const phone = verifiedNumberData?.otpVerifiedPhoneNumber;
      const customerEmail = emailForApi || "";

      if (customerEmail) {
        setCustomerEmail(customerEmail);
        actions.setCustomerEmail(customerEmail);
      }

      if (!phone) {

        throw new Error(
          "Phone number is required to save address. Please ensure OTP verification completed.",
        );
      }

      const saveResponse = await saveShippingAddress({
        phone: phone,
        email: customerEmail,
        shippingAddresses: shippingAddresses,
      });

      if (saveResponse.success) {
      } else {

      }

      const selectedAddress =
        formMode === "edit" && editableAddress
          ? shippingAddresses.find((addr) => addr.id === editableAddress.id)
          : shippingAddresses[shippingAddresses.length - 1];

      if (selectedAddress) {
        setSelectedAddress(selectedAddress);
        actions.setAddresses(shippingAddresses, selectedAddress.id);
        otpStoreActions.setSelectedAddress(selectedAddress.id);
        otpStoreActions.setShippingAddressCount(shippingAddresses.length);
      }

      const settings = $settingsStore;
      const partialPaymentEnabled =
        settings?.partialPaymentEnabled === true ||
        settings?.partialPaymentEnabled === "true" ||
        settings?.partial_payment_enabled === true ||
        settings?.partial_payment_enabled === "true";

      await getCurrentStep();
      otpStoreActions.setIsEditAddress(false);
      otpStoreActions.setEditableAddress({});
    } catch (error) {

      formError = error.message || "Failed to save address. Please try again.";
    } finally {
      isSavingAddress = false;
      actions.setLoading(false);
    }
  }

  async function handleFormCancel() {
    if (isSavingAddress) return;
    await getCurrentStep();
    otpStoreActions.setIsEditAddress(false);
    otpStoreActions.setEditableAddress({});
  }

</script>

{#if !optimizedBuyNow && !isCartReady}
  <CartLoadingScreen />
{:else}
  <div class="address-form-layout">
    <div class="form-wrapper">
      <AddressForm
        mode={formMode}
        address={editableAddress || {}}
        email={formEmail || customerEmail}
        loading={isSavingAddress}
        phoneFallback={phoneNumber}
        emailMandatory={!!settings?.preEmailMandatory}
        showPhoneField={!!(settings?.cod_form_enabled === true || settings?.cod_form_enabled === "true") && !(settings?.enablePreOrderOtp === true || settings?.enable_pre_order_otp === true)}
        on:save={handleFormSave}
        on:cancel={handleFormCancel}
      />
      <ErrorDisplay error={formError} compact={true} />
    </div>
  </div>
{/if}

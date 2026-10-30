import { writable, get } from "svelte/store";
import { sendErrorToAPI } from "../services/errorReporter";
import { getAddressCount } from "../services/api.js";
import {
  fetchMachineDetails,
  sendOtpRequest,
  verifyOtpRequest,
  getCart,
  createCustomerLogin,
  IS_BUY_NOW_BUTTON,
  executePost,
} from "../services/otpService";
import {
  getMachineId,
  populateCallingCodeList,
  getSessionValue,
  setSessionValue,
  setCustomerEmail,
  removeSessionValue,
  PLEASE_ENTER_VALID_PHONE_NUMBER,
  generatePassword,
  getCurrentStep,
  setLocalValue,
  getCartItemsOrRefetch,
  saveDiscountSummaryToSession,
  buildBuyerIdentityPayload,
  getStorefrontCartId,
  getShopDomain,
  isNoEmailPlaceholder,
  isPreEmailMandatory,
} from "../utilities/otpUtils";

import { updateBuyerIdentity } from "../services/cartService";
import { appStore, actions } from "../stores/buttonManager.js";
import {
  createShopifyCustomer,
  handleCustomeShopifyLogin,
} from "../services/customerCredentialService";
import { emitShopifyVisitorIdentify } from "../utils/shopifyVisitor.js";
import {
  setOTPVerified,
  clearOTPVerified,
  isOptimizedBuyNowEnabled,
} from "../services/sessionService.js";

/** Always read settings from settingSession (single source of truth for feature flags). */
function getSettingsFromSession() {
  const raw = getSessionValue("settingSession");
  if (typeof raw === "string") {
    try {
      return JSON.parse(raw) || {};
    } catch {
      return {};
    }
  }
  return raw || {};
}

const initialState = {
  showOTPModal: false,
  isEditAddress: false,
  editableAddress: {},
  selectedAddress: 0,
  newDesign: false,
  isSmsLoading: false,
  isWhatsappLoading: false,
  isSkipLoading: false,
  isCustomerCredentialAvailable: false,
  isPartialPaymentCartReadyAndUpdated: false,
  isCartManipulationProcessCompleted: false,
  isBlurryPageLoaderEnabled: false,
  isPrefilledAddressCompleted: false,
  isCartReady: false,
  isSummaryOptimistic: false,
  isCartLoading: false,
  cartLoadFailed: false,
  isProceedingPayment: false,
  buyNowError: null,
  isLoginProcessCompleted: false,
  shippingAddressCount: 0,
  isPartialCartRevertToOriginalCartCompleted: false,
  isCreatingCarts: false,
  isLoaderLoading: false,
  isFullPercentage: false,
  isCOD: false,
  currentCartData: null,
  buyerIdentity: null,
  verifiedEmail: null,
  mode: "SMS",
  selectedRuleId: "",
  orderSummaryTotalQuantity: 0,
  otpData: {
    step: 1,
    phoneNumber: "",
    otp: "",
    error: "",
    timer: 60,
    isLoading: false,
    ip: "",
    countryCallingCode: "+91",
    callingCodeList: [],
    countryCode: "",
    showResendLink: true,
    showServerErrorText: false,
    showMaxRetryLimitReachedTxt: false,
    resendAttempts: 0,
    session: getSessionValue("verifiedNumberData"),
    currentProgressBarStep: 0,
    shopTitle: "",
    shopLogo:
      "https://cdn.shopify.com/s/files/1/0743/3119/3628/files/CK_logo_icon-1200px.png?v=1757062726",
    codkingTrusted: true,
    codking: "COD King",
    isValidNumber: false,
  },
  settings: {
    countryCodeList: [],
    enablePreOrderOtp: false,
    enterCodeText: "",
    failedToVerifyText: "",
    heading: "",
    invalidPhoneText: "",
    isNewDesignEnabled: false,
    maxTriesInCodKSettings: 3,
    otpWaitTimeInCodKSettings: 60,
    phonePlaceholder: "",
    prePrimaryButtonColor: "",
    prePrimaryButtonFontColor: "",
    preSecondaryButtonColor: "",
    preSecondaryButtonFontColor: "",
    preWhatsappButton: true,
    preWhatsappButtonText: "",
    redirectText: "",
    resendText: "",
    retryInText: "",
    sendBtnText: "",
    showSkipBtn: true,
    skipBtnText: "",
    subHeading: "",
    tooManyAttemptsText: "",
    verifyBtnText: "",
    verifyMobileText: "",
    verifyingText: "",
    wrongOtpText: "",
    preV2Title: "",
    storeFrontToken: "",
    preIsLoginEnabled: false,
    isPrefilledAddressEnabled: false,
    partialPaymentEnabled: false,
    preV2Theme: "",
    preV2ShowOrderSummary: true,
    debug: false,
    preEmailMandatory: "",
    preGeoCountries: "",
    preShowBranding: "",
    brandLogoUrl: "",
    showOfferAndReward: true,
    preV2ShowTaxInfo: false,
    isTaxIncludedWithProduct: false,
    preV2ShowShippingInfo: false,
    includeShippingInPaymentOptions: false,
    codkingLoading: false,
  },
  calculatedTaxData: null,
  selectedShippingHandle: null,
  // Merchant-set shipping charge on the selected payment option, mirrored here
  // so the order summary's bill can show the same figure as the option cards.
  optionShippingAmount: 0,
  orderSummary: {
    productData: [],
    totalPrice: 0,
    totalQuantity: 0,
    currencyCode: "USD",
    discountDetails: { code: "", type: "", value: "", amount: 0 },
    summaryLoading: true,
  },
};

function createOtpStore() {
  const { subscribe, set, update } = writable(initialState);

  return {
    subscribe,
    setOtpData: (updatedData) =>
      update((s) => ({ ...s, otpData: { ...s.otpData, ...updatedData } })),
    setSettings: (updatedSettings) =>
      update((s) => ({
        ...s,
        settings: { ...s.settings, ...updatedSettings },
      })),
    setCalculatedTaxData: (data) =>
      update((s) => ({ ...s, calculatedTaxData: data })),
    setSelectedShippingHandle: (handle) =>
      update((s) => ({ ...s, selectedShippingHandle: handle })),
    setOptionShippingAmount: (amount) =>
      update((s) => ({ ...s, optionShippingAmount: Number(amount) || 0 })),
    setIsCartReady: (status) => update((s) => ({ ...s, isCartReady: status })),
    /**
     * Paint the order summary instantly from a scraped/optimistic cart while the
     * real cart round-trips run in the background. Does NOT set isCartReady, so
     * the CTA still gates on authoritative data. Cleared once fetchProductDetails
     * reconciles with the real cart.
     */
    setOptimisticCart: (cart) =>
      update((s) => {
        // Never clobber an authoritative (already-loaded) cart.
        if (!cart || s.isCartReady) return s;
        const items = (cart.items || []).map((item) => ({
          variantId: item.variant_id,
          quantity: item.quantity,
          name: item.title,
          imageSrc: item?.featured_image?.url || "NA",
          price: (item.price || 0) / 100,
        }));
        return {
          ...s,
          currentCartData: cart,
          isSummaryOptimistic: true,
          orderSummary: {
            ...s.orderSummary,
            productData: items,
            totalPrice: (cart.total_price || 0) / 100,
            totalQuantity: cart.item_count || 0,
            currencyCode: cart.currency || "INR",
            summaryLoading: false,
          },
        };
      }),
    /**
     * Optimized Buy Now, but WITHOUT scraped data (e.g. quick view). Flips
     * isSummaryOptimistic so the payment screen renders instantly with skeletons
     * (order summary + payment methods) while the cart round-trips run in the
     * background. Does NOT populate currentCartData, so OrderSummaryCard shows
     * its skeleton until the authoritative cart lands.
     */
    setOptimisticPending: () =>
      update((s) =>
        s.isCartReady || s.currentCartData?.items?.length
          ? s
          : { ...s, isSummaryOptimistic: true },
      ),
    setIsCartLoading: (status) =>
      update((s) => ({ ...s, isCartLoading: status })),
    setIsProceedingPayment: (status) =>
      update((s) => ({ ...s, isProceedingPayment: status })),
    setBuyNowError: (err) => update((s) => ({ ...s, buyNowError: err })),
    clearBuyNowError: () => update((s) => ({ ...s, buyNowError: null })),
    setIsLoginProcessCompleted: (status) =>
      update((s) => ({ ...s, isLoginProcessCompleted: status })),
    setShippingAddressCount: (status) =>
      update((s) => ({ ...s, shippingAddressCount: status })),
    setIsPartialCartRevertToOriginalCartCompleted: (status) =>
      update((s) => ({
        ...s,
        isPartialCartRevertToOriginalCartCompleted: status,
      })),
    setIsCreatingCarts: (status) =>
      update((s) => ({ ...s, isCreatingCarts: status })),
    setIsLoaderLoading: (status) =>
      update((s) => ({ ...s, isLoaderLoading: status })),
    setIsFullPercentage: (value) =>
      update((s) => ({ ...s, isFullPercentage: value })),
    setIsCOD: (value) => update((s) => ({ ...s, isCOD: value })),
    setMode: (value) => update((s) => ({ ...s, mode: value })),
    setSelectedRuleId: (value) =>
      update((s) => ({ ...s, selectedRuleId: value })),
    setStep: (stepNumber) =>
      update((s) => ({ ...s, otpData: { ...s.otpData, step: stepNumber } })),
    setOtp: (updatedOTP) =>
      update((s) => ({ ...s, otpData: { ...s.otpData, otp: updatedOTP } })),
    setError: (error) =>
      update((s) => ({ ...s, otpData: { ...s.otpData, error } })),
    setIsLoading: (isLoading) =>
      update((s) => ({ ...s, otpData: { ...s.otpData, isLoading } })),
    setShowServerErrorText: (showError) =>
      update((s) => ({
        ...s,
        otpData: { ...s.otpData, showServerErrorText: showError },
      })),
    setShowOTPModal: (modal) => update((s) => ({ ...s, showOTPModal: modal })),
    setIsEditAddress: (isEdit) =>
      update((s) => ({ ...s, isEditAddress: isEdit })),
    setEditableAddress: (address) =>
      update((s) => ({ ...s, editableAddress: address })),
    setIsPrefilledAddressCompleted: (status) =>
      update((s) => ({ ...s, isPrefilledAddressCompleted: status })),
    setSelectedAddress: (id) => update((s) => ({ ...s, selectedAddress: id })),
    setIsSmsLoading: (value) => update((s) => ({ ...s, isSmsLoading: value })),
    setisWhatsAppLoading: (value) =>
      update((s) => ({ ...s, isWhatsappLoading: value })),
    setOrderSummaryTotalQuantity: (value) =>
      update((s) => ({ ...s, orderSummaryTotalQuantity: value })),
    setCustomerCredentialAvailability: (availability) =>
      update((s) => ({ ...s, isCustomerCredentialAvailable: availability })),
    setIsPartialPaymentCartReadyAndUpdated: (value) =>
      update((s) => ({ ...s, isPartialPaymentCartReadyAndUpdated: value })),
    setIsCartManipulationProcessCompleted: (value) =>
      update((s) => ({ ...s, isCartManipulationProcessCompleted: value })),

    setCurrentCartData: (cartData) => {
      update((s) => {
        // Preserve local-only attributes (e.g. _codkAmountType / _codkPaymentDescription
        // set during partial-payment selection but not yet persisted to Shopify) so a
        // mid-flow cart refetch doesn't wipe them.
        const prevAttrs = s.currentCartData?.attributes || {};
        const incomingAttrs = cartData?.attributes || {};
        const merged = { ...cartData, attributes: { ...incomingAttrs, ...prevAttrs } };
        return {
          ...s,
          currentCartData: s.buyerIdentity
            ? { ...merged, buyerIdentity: s.buyerIdentity }
            : merged,
        };
      });
    },

    patchCurrentCartData: (patch) => {
      update((s) => {
        if (!s.currentCartData) return s;
        return { ...s, currentCartData: { ...s.currentCartData, ...patch } };
      });
    },

    setBuyerIdentity: (buyerIdentity) => {
      update((s) => ({
        ...s,
        buyerIdentity,
        currentCartData: s.currentCartData
          ? { ...s.currentCartData, buyerIdentity }
          : s.currentCartData,
      }));
    },
    setVerifiedEmail: (email) =>
      update((s) => ({ ...s, verifiedEmail: email })),
    initializeOtpData: async () => {
      try {
        const result = await fetchMachineDetails();
        setLocalValue(
          "defaultCountry",
          (result?.data?.country || "").toLowerCase(),
        );
        const { settings } = get({ subscribe });
        update((s) => ({
          ...s,
          otpData: {
            ...s.otpData,
            ip: result?.data?.ip,
            callingCodeList: populateCallingCodeList(settings.countryCodeList),
          },
        }));

        // SSO auto-login is handled in main.js after settings are loaded
      } catch (error) {
        sendErrorToAPI(error, "otpStore.initializeOtpData", "error");
      }
    },

    handlePhoneSubmit: async (mode) => {
      const state = get({ subscribe });
      const {
        phoneNumber,
        ip,
        countryCallingCode,
        countryCode,
        isValidNumber,
      } = state.otpData;
      const isValidPhoneNumber = /^\+?[1-9]\d{1,14}$/.test(phoneNumber);

      if (!isValidPhoneNumber || !isValidNumber) {
        update((s) => ({
          ...s,
          otpData: {
            ...s.otpData,
            error: PLEASE_ENTER_VALID_PHONE_NUMBER,
            showServerErrorText: true,
          },
          isSmsLoading: false,
          isWhatsappLoading: false,
        }));
        return;
      }

      update((s) => ({
        ...s,
        isSmsLoading: mode === "SMS",
        isWhatsappLoading: mode === "WHATSAPP",
        otpData: {
          ...s.otpData,
          error: "",
          isLoading: true,
          showServerErrorText: false,
        },
      }));

      try {
        const s = getSettingsFromSession();
        const prefilledOn =
          s?.isPrefilledAddressEnabled === true ||
          s?.isPrefilledAddressEnabled === "true" ||
          s?.is_prefilled_address_enabled === true ||
          s?.is_prefilled_address_enabled === "true";
        if (prefilledOn) {
          getAddressCount(`${phoneNumber}`, getShopDomain()).then((res) => {
            if (res.success) {
              const email = res?.data?.email;
              if (
                email &&
                (!isPreEmailMandatory(s) || !isNoEmailPlaceholder(email))
              ) {
                setCustomerEmail(email);
                update((s) => ({ ...s, verifiedEmail: email }));
              }
              update((s) => ({
                ...s,
                shippingAddressCount: res.data?.shippingAddressCount,
              }));
            }
          });
        }

        const cartDataItems = await getCartItemsOrRefetch();
        const result = await sendOtpRequest({
          countryCode,
          phoneNumber,
          countryCallingCode,
          ipAddress: ip,
          deviceId: getMachineId(),
          shop: getShopDomain(),
          mode,
          cartDetails: cartDataItems,
        });

        const responseData = result.data || result;
        const responseStatus = responseData.status;

        if ((result.status === 200 && responseStatus === "Success") || responseStatus === "Success") {
          update((s) => ({
            ...s,
            otpData: {
              ...s.otpData,
              step: 2,
              isLoading: false,
              timer: s.settings.otpWaitTimeInCodKSettings || 60,
            },
          }));
        } else if (responseStatus === "Error") {
          const errorMessage = responseData.Notes || "Failed to send OTP. Please try again.";
          update((s) => ({
            ...s,
            otpData: {
              ...s.otpData,
              error: errorMessage,
              showServerErrorText: true,
            },
            isSmsLoading: false,
            isWhatsappLoading: false,
          }));
        } else {
          throw new Error("Failed to send OTP");
        }
      } catch (error) {
        update((s) => ({
          ...s,
          otpData: {
            ...s.otpData,
            error: error.message || "Failed to send OTP. Please try again.",
            showServerErrorText: true,
          },
          isSmsLoading: false,
          isWhatsappLoading: false,
        }));
        sendErrorToAPI(error, "otpStore.handlePhoneSubmit", "error");
      } finally {
        update((s) => ({
          ...s,
          otpData: { ...s.otpData, isLoading: false },
          isSmsLoading: false,
          isWhatsappLoading: false,
        }));
      }
    },

    handleOtpSubmit: async (mode) => {
      const state = get({ subscribe });
      const { countryCode, phoneNumber, countryCallingCode, ip, otp } =
        state.otpData;

      const widgetState = {
        setIsLoading: (val) =>
          update((s) => ({ ...s, otpData: { ...s.otpData, isLoading: val } })),
        setStep: (step) =>
          update((s) => ({ ...s, otpData: { ...s.otpData, step } })),
        setError: (err) =>
          update((s) => ({ ...s, otpData: { ...s.otpData, error: err } })),
        setShowServerErrorText: (val) =>
          update((s) => ({
            ...s,
            otpData: { ...s.otpData, showServerErrorText: val },
          })),
      };

      widgetState.setIsLoading(true);
      try {
        await verifyOtpRequest({
          countryCode,
          phoneNumber,
          countryCallingCode,
          ipAddress: ip,
          deviceId: getMachineId(),
          shop: getShopDomain(),
          otp,
          mode,
          widgetState,
        });
        widgetState.setError("");
      } catch (error) {
        widgetState.setIsLoading(false);
        widgetState.setError("Error in OTP verification.");
        widgetState.setShowServerErrorText(true);
        sendErrorToAPI(error, "otpStore.handleOtpSubmit");
      }
    },

    handleContinue: async () => {
      update((s) => ({
        ...s,
        otpData: { ...s.otpData, isLoading: true, error: "" },
      }));
      try {
        const shippingAddresses = getSessionValue("shipping_addresses") || [];
        const state = get({ subscribe });
        const selectedAddressId = state.selectedAddress;
        const verifiedNumberData = getSessionValue("verifiedNumberData");
        const verifiedPhoneNumber =
          verifiedNumberData?.otpVerifiedPhoneNumber || "";
        const email =
          state.verifiedEmail || getSessionValue("customer-email") || null;
        if (email) update((s) => ({ ...s, verifiedEmail: email }));

        const selected = shippingAddresses.find(
          (addr) => addr.id === selectedAddressId,
        );
        if (!selected) throw new Error("No address selected.");

        const cleanBuyerIdentity = buildBuyerIdentityPayload(
          selected,
          verifiedPhoneNumber,
          email,
        );

        update((s) => {
          const updatedCart = s.currentCartData
            ? { ...s.currentCartData, buyerIdentity: cleanBuyerIdentity }
            : s.currentCartData;
          return {
            ...s,
            buyerIdentity: cleanBuyerIdentity,
            currentCartData: updatedCart,
            isPrefilledAddressCompleted: true,
          };
        });

        const currentCartData = state.currentCartData;
        const sessionCart = getSessionValue("shopify_cart");
        const cartToken = currentCartData?.token || sessionCart?.token;

        const s = getSettingsFromSession();
        const prefilledOrCodForm =
          s?.isPrefilledAddressEnabled === true ||
          s?.isPrefilledAddressEnabled === "true" ||
          s?.is_prefilled_address_enabled === true ||
          s?.is_prefilled_address_enabled === "true" ||
          s?.cod_form_enabled === true ||
          s?.cod_form_enabled === "true";

        if (prefilledOrCodForm && cartToken) {
          const cartId = getStorefrontCartId(cartToken);

          if (cartId) {
            try {
              const updatedCart = await updateBuyerIdentity(
                cartId,
                cleanBuyerIdentity,
              );

              if (updatedCart?.checkoutUrl) {
                setSessionValue(
                  "updated_checkout_url",
                  updatedCart.checkoutUrl,
                );
              }
            } catch (_error) {}
          }
        }

        const nextStep = await getCurrentStep();
        update((s) => ({
          ...s,
          otpData: { ...s.otpData, isLoading: false },
        }));
      } catch (error) {
        update((s) => ({
          ...s,
          otpData: { ...s.otpData, isLoading: false, error: error.message },
        }));
        sendErrorToAPI(error, "otpStore.handleContinue");
      }
    },

    handleEmailSubmit: async (email) => {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!email || !emailRegex.test(email)) {
        update((s) => ({
          ...s,
          otpData: {
            ...s.otpData,
            error: "Please enter a valid email address.",
          },
        }));
        return;
      }

      update((s) => ({
        ...s,
        otpData: { ...s.otpData, error: "", isLoading: true },
      }));

      try {
        const password = generatePassword();
        const newCustomer = await createShopifyCustomer({ email, password });

        if (!newCustomer?.success) {
          const errMsg =
            newCustomer?.errors?.[0] || "Failed to create customer.";
          if (errMsg.includes("already in use"))
            throw new Error("Email already in use.");
          throw new Error(errMsg);
        }

        localStorage.setItem("newCustomer", JSON.stringify(newCustomer));
        const loginResult = await handleCustomeShopifyLogin(email, password);
        if (!loginResult?.success) throw new Error("Failed to log in.");

        const otpState = get({ subscribe }).otpData;
        emitShopifyVisitorIdentify({
          phone: otpState.phoneNumber,
          email,
          countryCallingCode: otpState.countryCallingCode,
        });

        await createCustomerLogin({
          shopifyCustomerId: newCustomer.customer.id,
          email,
          password,
          phone: `+${get({ subscribe }).otpData.phoneNumber}`,
          shopifyDomain: getShopDomain(),
        });

        update((s) => ({ ...s, isLoginProcessCompleted: true }));
        const currentQty = get({ subscribe }).orderSummaryTotalQuantity;

        if (currentQty === 0) {
          window.location.href = `https://${getShopDomain()}/account`;
        } else {
          const nextStep = await getCurrentStep();
          update((s) => ({
            ...s,
            otpData: { ...s.otpData, error: "" },
          }));
        }
      } catch (error) {
        update((s) => ({
          ...s,
          otpData: { ...s.otpData, error: error.message, isLoading: false },
        }));
        sendErrorToAPI(error, "otpStore.handleEmailSubmit");
      } finally {
        update((s) => ({ ...s, otpData: { ...s.otpData, isLoading: false } }));
      }
    },

    fetchProductDetails: async () => {
      update((s) => ({
        ...s,
        isCartManipulationProcessCompleted: false,
        isCartLoading: true,
        cartLoadFailed: false,
        orderSummary: { ...s.orderSummary, summaryLoading: true },
      }));
      try {
        const settings = getSessionValue("settingSession");
        const isPartialEnabled = settings?.partialPaymentEnabled === true;
        const partialVersion = settings?.partialPaymentFlowVersion;

        let cartData = await getCart(true);

        // Shopify cart is eventually consistent right after /cart/add.js.
        if (!cartData?.items || cartData.items.length === 0) {
          if (isOptimizedBuyNowEnabled()) {
            // Optimized: retry with exponential backoff instead of a flat wait.
            const backoffs = [50, 100, 200, 400];
            for (const delay of backoffs) {
              await new Promise((resolve) => setTimeout(resolve, delay));
              cartData = await getCart(true);
              if (cartData?.items && cartData.items.length > 0) break;
            }
          } else {
            // Original behavior: single flat 800ms wait + refetch.
            await new Promise((resolve) => setTimeout(resolve, 800));
            cartData = await getCart(true);
          }
        }

        if (!cartData) throw new Error("Cart unavailable");

        saveDiscountSummaryToSession();
        getStorefrontCartId(cartData?.token);

        update((s) => ({ ...s, currentCartData: cartData }));

        actions.setCart(cartData);

        const items = cartData.items.map((item) => ({
          variantId: item.variant_id,
          quantity: item.quantity,
          name: item.title,
          imageSrc: item?.featured_image?.url || "NA",
          price: parseFloat(item.presentment_price),
        }));

        const total = items.reduce(
          (acc, item) => acc + item.price * item.quantity,
          0,
        );
        const qty = items.reduce((acc, item) => acc + item.quantity, 0);

        let discountDetails = { code: "", type: "", value: "", amount: 0 };
        const apps = cartData.cart_level_discount_applications || [];
        if (apps.length > 0) {
          discountDetails = {
            code: apps[0].title,
            type: apps[0].value_type,
            value: apps[0].value,
            amount: (apps[0].total_allocated_amount || 0) / 100, // Convert from cents to decimal
          };
        } else {
          const items = cartData.items || [];
          for (const item of items) {
            if (
              item.line_level_discount_allocations &&
              item.line_level_discount_allocations.length > 0
            ) {
              const discount =
                item.line_level_discount_allocations[0].discount_application;
              discountDetails = {
                code: discount.title,
                type: discount.value_type,
                value: discount.value,
                amount: (discount.total_allocated_amount || 0) / 100, // Convert from cents to decimal
              };
              break;
            }
          }
        }

        update((s) => ({
          ...s,
          isCartLoading: false,
          orderSummary: {
            ...s.orderSummary,
            productData: items,
            totalPrice: total,
            totalQuantity: qty,
            currencyCode: cartData.currency || "USD",
            discountDetails,
            summaryLoading: false,
          },
          isCartReady: true,
          isSummaryOptimistic: false,
          orderSummaryTotalQuantity: qty,
          isCartManipulationProcessCompleted: true,
        }));
      } catch (error) {
        update((s) => ({
          ...s,
          isCartLoading: false,
          cartLoadFailed: true,
          isCartManipulationProcessCompleted: true,
          orderSummary: { ...s.orderSummary, summaryLoading: false },
        }));
        sendErrorToAPI(error, "otpStore.fetchProductDetails");
      }
    },
    handlePhoneSubmitSms: () => {
      update((s) => ({ ...s, mode: "SMS" }));
      return get({ subscribe }).handlePhoneSubmit("SMS");
    },
    handlePhoneSubmitWhatsapp: () => {
      update((s) => ({ ...s, mode: "WHATSAPP" }));
      return get({ subscribe }).handlePhoneSubmit("WHATSAPP");
    },

    handleSkip: async () => {
      update((s) => ({ ...s, isSkipLoading: true }));
      try {
        const { redirectToCheckout } = await import("../utils/helpers.js");
        redirectToCheckout("/checkout");
      } finally {
        update((s) => ({ ...s, isSkipLoading: false }));
      }
    },

    reset: () => set(initialState),
  };
}

export const performLogout = async (context = "Logout") => {
  try {
    const { actions } = await import("../stores/buttonManager.js");
    const { getShopDomain } = await import("../utils/helpers.js");
    const { clearPersistentData } = await import("../services/persistentSigninStorage.js");
    const { ssoLogout } = await import("../services/api.js");
    clearPersistentData(getShopDomain());

    // Clear SSO session on backend + delete codk_sso cookie
    console.log("[SSO] Logout triggered from", context, "- clearing persistent data + SSO session");
    ssoLogout(getShopDomain()).then((res) => {
      console.log("[SSO] Logout backend response:", res);
    }).catch((err) => {
      console.log("[SSO] Logout backend error:", err.message);
    });
    setOTPVerified("", false);
    clearOTPVerified();
    actions.setPhoneNumber("", "91");
    actions.setCountryCallingCode("+91");
    actions.setValidNumber(false);
    actions.setScreen("phone");

    // Clear address and buyer-identity state so new login does not see previous user's data
    setSessionValue("shipping_addresses", []);
    removeSessionValue("cod_king_selected_address");
    removeSessionValue("preOrderOtpResponse");
    removeSessionValue("customer-email");
    removeSessionValue("cod_king_customer_email");
    removeSessionValue("ssoValidatedToken");
    removeSessionValue("ssoAutoLoginAttempted");
    actions.setAddresses([], null);
    actions.setCustomerEmail("");

    (async () => {
      try {
        const { getMachineId } = await import("../utils/helpers.js");
        const deviceId = getMachineId();
        const existingCodkSessionId = deviceId;

        const response = await executePost({
          attributes: {
            _otpVerifiedPhoneNumber: "",
            ...(existingCodkSessionId && {
              _codkSessionId: existingCodkSessionId,
            }),
          },
        });

        if (!response.ok) {
          const text = await response.text();
          throw new Error(
            `cart/update.js failed: ${response.status} ${response.statusText} - ${text}`,
          );
        }
      } catch (_cartError) {}
    })();

    // Reset otpStore address/buyer state (dynamic import returns cached module)
    const { otpStore: store } = await import("./otpStore.js");
    store.setSelectedAddress(0);
    store.setBuyerIdentity(null);
    store.setVerifiedEmail(null);

    return { success: true };
  } catch (error) {
    return { success: false, error: error.message };
  }
};

export const otpStore = createOtpStore();
export const otpStoreActions = otpStore;
export default otpStore;

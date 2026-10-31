// stores/otpStore.js
import create from "zustand";
import { sendErrorToAPI } from "../services/errorReporter";
import {
  fetchMachineDetails,
  sendOtpRequest,
  verifyOtpRequest,
  manageBuyNowSkipButton,
  getCart,
  createCustomerLogin,
  executePost,
  getAddressCount,
} from "../services/otpService";
import {
  getMachineId,
  populateCallingCodeList,
  getSessionValue,
  setSessionValue,
  removeSessionValue,
  PLEASE_ENTER_VALID_PHONE_NUMBER,
  generatePassword,
  debugLog,
  getCurrentStep,
  setLocalValue,
  getCartItemsOrRefetch,
  // preCreateCartsForEligibleRules,
  saveDiscountSummaryToSession,
  buildBuyerIdentityPayload,
  getStorefrontCartId,
} from "../utilities/otpUtils";
import { getIsBuyNowButton } from "../services/domUtils";
import {
  updateBuyerIdentity,
  removeDiscountCodeAndAttribute,
} from "../services/cartService";
import {
  createShopifyCustomer,
  handleCustomeShopifyLogin,
} from "../services/customerCredentialService";
import { CartRevertService } from "../services/CartRevertService";
import { trackCheckoutInitiated } from "../services/funnelTracker";
// import productImagePlaceholder from "../components/assets/cart-icon.png";

const useOtpStore = create((set, get) => ({
  // Initial State
  showOTPModal: false,
  isEditAddress: false,
  editableAddress: {},
  selectedAddress: 0,
  newDesign: false,
  // Loading states
  isSmsLoading: false,
  isWhatsappLoading: false,
  isSkipLoading: false,
  isCustomerCredentialAvailable: false,
  isPartialPaymentCartReadyAndUpdated: false,
  isCartManipulationProcessCompleted: false,
  isBlurryPageLoaderEnabled: false,
  isPrefilledAddressCompleted: false,
  isCartReady: false,
  setIsCartReady: (status) => set({ isCartReady: status }),
  isBuyNowReady: false,
  setIsBuyNowReady: (status) => set({ isBuyNowReady: status }),
  isLoginProcessCompleted: false,
  setIsLoginProcessCompleted: (status) =>
    set({ isLoginProcessCompleted: status }),
  shippingAddressCount: 0,
  setShippingAddressCount: (status) => set({ shippingAddressCount: status }),
  isPartialCartRevertToOriginalCartCompleted: false,
  setIsPartialCartRevertToOriginalCartCompleted: (status) =>
    set({ isPartialCartRevertToOriginalCartCompleted: status }),
  isCreatingCarts: false,
  setIsCreatingCarts: (status) => set({ isCreatingCarts: status }),
  isFullPercentage: false,
  setIsFullPercentage: (value) => set({ isFullPercentage: value }),
  isCOD: false,
  setIsCOD: (value) => set({ isCOD: value }),
  currentCartData: null,
  setCurrentCartData: (cartData) => {
    const buyerIdentity = get().buyerIdentity;
    // Preserve local-only attributes (e.g. _codkAmountType / _codkPaymentDescription
    // set during partial-payment selection but not yet persisted to Shopify) so a
    // mid-flow cart refetch doesn't wipe them.
    const prevAttrs = get().currentCartData?.attributes || {};
    const incomingAttrs = cartData?.attributes || {};
    const merged = { ...cartData, attributes: { ...incomingAttrs, ...prevAttrs } };
    set({
      currentCartData: buyerIdentity ? { ...merged, buyerIdentity } : merged,
    });
  },
  resetCurrentCartData: () => {
    set({ currentCartData: null });
  },
  patchCurrentCartData: (patch) => {
    set((state) => {
      if (!state.currentCartData) return state;
      return {
        currentCartData: {
          ...state.currentCartData,
          ...patch,
        },
      };
    });
  },
  buyerIdentity: null,
  setBuyerIdentity: (buyerIdentity) => {
    set({ buyerIdentity });
    get().patchCurrentCartData({ buyerIdentity });
  },
  verifiedEmail: null,
  setVerifiedEmail: (email) => set({ verifiedEmail: email }),
  mode: "SMS",
  setMode: (value) => set({ mode: value }),
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
  },
  orderSummaryTotalQuantity: 0,
  selectedRuleId: "",
  setSelectedRuleId: (value) => set({ selectedRuleId: value }),
  setOrderSummary: (patch) =>
    set((state) => ({
      orderSummary: {
        ...state.orderSummary,
        ...patch,
      },
    })),
  resetOrderSummary: () => {
    set({
      orderSummary: {
        productData: [],
        totalPrice: 0,
        totalQuantity: 0,
        currencyCode: "USD",
        discountDetails: {
          code: "",
          type: "",
          value: "",
          amount: 0,
        },
        summaryLoading: true,
      },
    });
  },
  setStep: (stepNumber) => {
    set((state) => ({
      otpData: {
        ...state.otpData,
        step: stepNumber,
      },
    }));
  },

  initializeOtpData: async () => {
    try {
      const result = await fetchMachineDetails();
      setLocalValue(
        "defaultCountry",
        (result?.data?.country || "").toLowerCase(),
      );
      const countryCodeList = get().settings.countryCodeList;

      set((state) => ({
        otpData: {
          ...state.otpData,
          ip: result?.data?.ip,
          callingCodeList: populateCallingCodeList(countryCodeList),
          // countryCallingCode: countryCodeList[0]?.value || "+91",
          // countryCode: countryCodeList[0]?.name || "IN",
        },
      }));
    } catch (error) {
      console.error("Error initializing OTP data:", error);
      sendErrorToAPI(error, "otpStore.initializeOtpData", "error", {
        operation: "initializeOtpData",
        sessionData: getSessionValue("verifiedNumberData"),
      });
    }
  },

  handlePhoneSubmit: async (mode) => {
    const { phoneNumber, ip, countryCallingCode, countryCode, isValidNumber } =
      get().otpData;
    // Phone number validation: Ensure it's a 10-digit number
    const isValidPhoneNumber = /^\+?[1-9]\d{1,14}$/.test(phoneNumber);
    if (!isValidPhoneNumber || !isValidNumber) {
      set((state) => ({
        otpData: {
          ...state.otpData,
          error: PLEASE_ENTER_VALID_PHONE_NUMBER,
          showServerErrorText: true,
        },
        isSmsLoading: false,
        isWhatsappLoading: false,
      }));
      return; // Exit early if phone number is invalid
    }

    trackCheckoutInitiated({ mode });

    set({
      isSmsLoading: mode === "SMS",
      isWhatsappLoading: mode === "WHATSAPP",
    });
    set((state) => ({
      otpData: {
        ...state.otpData,
        error: "",
        isLoading: true,
        showServerErrorText: false,
      },
    }));

    try {
      const settings = get().settings;
      if (settings.isPrefilledAddressEnabled) {
        getAddressCount(`${phoneNumber}`, window.Shopify.shop)
          .then((res) => {
            if (res.success) {
              const email = res?.data?.email;
              if (email) {
                setSessionValue("customer-email", email);
                get().setVerifiedEmail(email);
              }
              get().setShippingAddressCount(res.data?.shippingAddressCount);
            }
          })
          .catch((err) => console.error("getAddressCount error:", err));
      }

      const cartDataItems = await getCartItemsOrRefetch();

      const result = await sendOtpRequest({
        countryCode,
        phoneNumber,
        countryCallingCode,
        ipAddress: ip,
        deviceId: getMachineId(),
        shop: window.Shopify.shop,
        mode,
        // device_type: getDeviceType(),
        cartDetails: cartDataItems,
      });
      if (result.status === 200 && result.data.status === "Success") {
        set((state) => ({
          otpData: {
            ...state.otpData,
            step: 2,
            isLoading: false,
            timer: get().settings.otpWaitTimeInCodKSettings || 60,
          },
        }));
        // updateCartDetails({
        //   device_id: getMachineId(),
        //   shop: window.Shopify.shop,
        //   device_type: getDeviceType(),
        //   cart_details: cartData?.items,
        // }).catch((err) => {
        //   console.warn("Non-blocking updateCartDetails failed:", err);
        // });
        // debugLog("Updated step to 2 after successful OTP submission.");
      } else {
        set((state) => ({
          otpData: {
            ...state.otpData,
            isLoading: false,
            error: "Failed to send OTP. Please try again.",
          },
          isSmsLoading: false,
          isWhatsappLoading: false,
        }));
      }
    } catch (error) {
      set((state) => ({
        otpData: {
          ...state.otpData,
          error: "Failed to send OTP. Please try again.",
          showServerErrorText: true,
        },
        isSmsLoading: false,
        isWhatsappLoading: false,
      }));
      sendErrorToAPI(error, "otpStore.handlePhoneSubmit", "error", {
        operation: "handlePhoneSubmit",
        mode,
        phoneNumber: phoneNumber ? phoneNumber.substring(0, 3) + "****" : null,
        countryCallingCode,
        countryCode,
        isValidNumber,
      });
    } finally {
      set((state) => ({
        otpData: {
          ...state.otpData,
          isLoading: false,
          isSmsLoading: false,
          isWhatsappLoading: false,
        },
      }));
    }
  },

  handleOtpSubmit: async (mode) => {
    const { countryCode, phoneNumber, countryCallingCode, ip, otp } =
      get().otpData;

    const widgetState = {
      setIsLoading: get().setIsLoading,
      setStep: get().setStep,
      setError: get().setError,
      setShowServerErrorText: get().setShowServerErrorText,
    };

    widgetState.setIsLoading(true);

    try {
      await verifyOtpRequest({
        countryCode,
        phoneNumber,
        countryCallingCode,
        ipAddress: ip,
        deviceId: getMachineId(),
        shop: window.Shopify.shop,
        otp,
        mode,
        widgetState,
      });
      // widgetState.setStep(3); // Set step to 3 after successful verification
      widgetState.setError("");
    } catch (error) {
      widgetState.setIsLoading(false);
      widgetState.setError("Error in OTP verification.");
      widgetState.setShowServerErrorText(true);

      // Add OTP submission context to the error
      error.otpContext = {
        countryCode,
        phoneNumber,
        countryCallingCode,
        ip,
        otp: otp ? otp.substring(0, 2) + "****" : null, // Mask OTP for security
        mode,
        deviceId: getMachineId(),
        shop: window.Shopify.shop,
      };

      sendErrorToAPI(error, "otpStore.handleOtpSubmit");
    } finally {
      // widgetState.setIsLoading(false);
    }
  },

  handleResendOtp: async () => {
    const { resendAttempts, timer } = get().otpData;
    const maxTries = get().settings.maxTriesInCodKSettings || 3;

    if (resendAttempts >= maxTries) {
      set((state) => ({
        otpData: {
          ...state.otpData,
          showMaxRetryLimitReachedTxt: true,
          showResendLink: false,
        },
      }));
      return;
    }

    if (timer === 0) {
      set((state) => ({ otpData: { ...state.otpData, isLoading: true } }));
      try {
        const mode = get().mode; // Get the current mode from store
        await get().handlePhoneSubmit(mode);
        set((state) => ({
          otpData: {
            ...state.otpData,
            resendAttempts: state.otpData.resendAttempts + 1,
          },
        }));
      } catch (error) {
        set((state) => ({
          otpData: { ...state.otpData, error: "Error while resending OTP." },
        }));
        sendErrorToAPI(error, "otpStore.handleResendOtp", "error", {
          operation: "handleResendOtp",
          resendAttempts,
          timer,
          maxTries: get().settings.maxTriesInCodKSettings || 3,
        });
      } finally {
        set((state) => ({ otpData: { ...state.otpData, isLoading: false } }));
      }
    }
  },

  onSkipButtonClick: () => {
    set((state) => ({
      otpData: { ...state.otpData, isLoading: true },
    }));
    if (getIsBuyNowButton()) {
      manageBuyNowSkipButton();
      set((state) => ({ otpData: { ...state.otpData, isLoading: false } }));
    } else {
      window.location = "/checkout";
      set((state) => ({ otpData: { ...state.otpData, isLoading: false } }));
    }
  },

  onChangePhonNoBtnClick: () => {
    set((state) => ({
      otpData: {
        ...state.otpData,
        phoneNumber: "",
        otp: "",
        error: "",
        step: 1,
      },
    }));
    set({
      isSmsLoading: false,
      isWhatsappLoading: false,
    });
  },

  // Setters
  setOtpData: (updatedData) => {
    set((state) => ({
      otpData: { ...state.otpData, ...updatedData },
    }));
  },

  setSettings: (updatedSettings) => {
    set((state) => ({
      settings: { ...state.settings, ...updatedSettings },
    }));
  },
  setOtp: (updatedOTP) => {
    set((state) => ({
      otpData: {
        ...state.otpData,
        otp: updatedOTP,
      },
    }));
  },
  setError: (error) => {
    set((state) => ({
      otpData: {
        ...state.otpData,
        error: error,
      },
    }));
  },
  setIsLoading: (isLoading) =>
    set((state) => ({
      otpData: {
        ...state.otpData,
        isLoading: isLoading,
      },
    })),
  setShowServerErrorText: (showError) =>
    set((state) => ({
      otpData: {
        ...state.otpData,
        showServerErrorText: showError,
      },
    })),
  setShowOTPModal: (modal) => set({ showOTPModal: modal }),
  setIsEditAddress: (isEdit) => set({ isEditAddress: isEdit }),
  setEditableAddress: (address) => set({ editableAddress: address }),
  setIsPrefilledAddressCompleted: (address) =>
    set({ isPrefilledAddressCompleted: address }),
  setSelectedAddress: (id) => set({ selectedAddress: id }),
  setIsSmsLoading: (value) => set({ isSmsLoading: value }),
  setisWhatsAppLoading: (value) => set({ isWhatsappLoading: value }),
  setOrderSummaryTotalQuantity: (value) =>
    set({ orderSummaryTotalQuantity: value }),
  setCustomerCredentialAvailability: (availability) =>
    set({ isCustomerCredentialAvailable: availability }),
  setIsPartialPaymentCartReadyAndUpdated: (value) =>
    set({ isPartialPaymentCartReadyAndUpdated: value }),
  setIsCartManipulationProcessCompleted: (value) =>
    set({ isCartManipulationProcessCompleted: value }),

  // Wrapper function for SMS submission
  handlePhoneSubmitSms: async () => {
    get().setMode("SMS");
    await get().handlePhoneSubmit("SMS");
  },

  // Wrapper function for WhatsApp submission
  handlePhoneSubmitWhatsapp: async () => {
    get().setMode("WHATSAPP");
    await get().handlePhoneSubmit("WHATSAPP");
  },

  // Function to handle the skip action
  handleSkip: async () => {
    set({ isSkipLoading: true });
    try {
      await get().onSkipButtonClick();
    } catch (error) {
      console.error("Error skipping:", error);
      sendErrorToAPI(error, "otpStore.handleSkip", "error", {
        operation: "handleSkip",
        isBuyNowButton: getIsBuyNowButton(),
      });
    } finally {
      set({ isSkipLoading: false });
    }
  },

  // Function to create a buyer identity based on selected address
  createBuyerIdentity: (selected, phone) => {
    return {
      email: selected.email,
      phone: phone,
      countryCode: "IN",
      deliveryAddressPreferences: [
        {
          deliveryAddress: {
            address1: selected.address1,
            address2: selected.address2 || "",
            city: selected.city,
            province: selected.state,
            country: "India",
            zip: selected.zip,
            firstName: selected.first_name,
            lastName: selected.last_name,
            phone: phone,
          },
        },
      ],
    };
  },

  // Update an existing cart with the buyer identity
  handleCartUpdate: async (cartId, buyerIdentity) => {
    try {
      const updatedCart = await updateBuyerIdentity(cartId, buyerIdentity);

      const checkoutUrl = updatedCart?.checkoutUrl;
      if (checkoutUrl) {
        removeSessionValue("created-cart");
        return updatedCart;
      } else {
        console.error("Checkout URL is missing in update response.");
        return null;
      }
    } catch (error) {
      console.error("Error updating buyer identity:", error);
      sendErrorToAPI(error, "otpStore.updateBuyerIdentity", "error", {
        operation: "updateBuyerIdentity",
        phoneNumber: phoneNumber ? phoneNumber.substring(0, 3) + "****" : null,
        verification: verification ? "present" : "missing",
      });
      throw error;
    }
  },

  handleContinue: async () => {
    set((state) => ({
      otpData: {
        ...state.otpData,
        isLoading: true,
        error: "", // Clear any existing error
      },
    }));

    try {
      const shippingAddresses = getSessionValue("shipping_addresses") || [];
      const selectedAddress = get().selectedAddress;
      const verifiedNumberData = getSessionValue("verifiedNumberData");
      const verifiedPhoneNumber =
        verifiedNumberData?.otpVerifiedPhoneNumber || "";
      const email =
        get().verifiedEmail || getSessionValue("customer-email") || null;
      if (email) get().setVerifiedEmail(email);

      const addresses = shippingAddresses?.map((item, index) => ({
        id: item.id,
        first_name: item.first_name,
        last_name: item.last_name,
        address1: item.address1,
        address2: item.address2,
        city: item.city,
        state: item.province,
        zip: item.zip,
        email, // null if not available
      }));

      let selected = addresses.find(
        (address) => String(address.id) === String(selectedAddress),
      );

      // If user didn't click any address, fallback to the first address
      // so they can directly click "Continue" and we still build buyer identity.
      if (!selected && addresses.length > 0) {
        selected = addresses[0];
        set({ selectedAddress: selected.id });
      }

      if (!selected) {
        set((state) => ({
          otpData: {
            ...state.otpData,
            isLoading: false,
            error: "No address selected.",
          },
        }));
        return;
      }

      const cleanBuyerIdentity = buildBuyerIdentityPayload(
        selected,
        verifiedPhoneNumber,
      );

      get().setBuyerIdentity(cleanBuyerIdentity);

      get().setIsPrefilledAddressCompleted(true);

      const nextStep = await getCurrentStep();
      get().setStep(nextStep);

      set((state) => ({
        otpData: {
          ...state.otpData,
          isLoading: false,
          error: "",
        },
      }));
    } catch (error) {
      console.error("Error in handleContinue:", error);
      sendErrorToAPI(error, "otpStore.handleContinue", "error", {
        operation: "handleContinue",
        currentStep: getCurrentStep(),
        isCartReady: get().isCartReady,
      });
      set((state) => ({
        otpData: {
          ...state.otpData,
          isLoading: false,
          error: error?.message || "An error occurred. Please try again.",
        },
      }));
    }
  },

  handleAddressSelect: async (id) => {
    set({ selectedAddress: id });

    // Update cart with buyer identity when address is selected
    try {
      const addresses = getSessionValue("shipping_addresses") || [];
      const selectedAddress = addresses.find(
        (address) => String(address.id) === String(id),
      );

      if (selectedAddress) {
        const verifiedNumberData = getSessionValue("verifiedNumberData");
        const verifiedPhoneNumber = verifiedNumberData?.otpVerifiedPhoneNumber;
        const email =
          get().verifiedEmail ||
          getSessionValue("customer-email") ||
          selectedAddress.email ||
          "";

        // Build buyer identity payload
        const buyerIdentityPayload = buildBuyerIdentityPayload(
          {
            email,
            first_name: selectedAddress.first_name || "",
            last_name: selectedAddress.last_name || "",
            address1: selectedAddress.address1 || "",
            address2: selectedAddress.address2 || "",
            city: selectedAddress.city || "",
            state: selectedAddress.province || "",
            zip: selectedAddress.zip || "",
          },
          verifiedPhoneNumber || selectedAddress.phone,
        );

        // Set buyer identity in store
        get().setBuyerIdentity(buyerIdentityPayload);

        // Update cart with buyer identity
        const currentCartData = get().currentCartData;
        const sessionCart = getSessionValue("shopify_cart");
        const cartToken = currentCartData?.token || sessionCart?.token;

        if (cartToken) {
          const cartId = getStorefrontCartId(cartToken);
          if (cartId) {
            debugLog(
              "🔄 Updating cart with buyer identity on address selection",
            );
            await updateBuyerIdentity(cartId, buyerIdentityPayload);
            debugLog("✅ Cart updated with buyer identity successfully");
          }
        }
      }
    } catch (error) {
      console.error(
        "Error updating cart with buyer identity on address select:",
        error,
      );
      // Don't throw - address selection should still work even if cart update fails
    }

    if (typeof window !== "undefined" && typeof window.closeModal === "function") {
      window.closeModal();
    }
  },
  handleEditAddress: (id) => {
    const addresses = getSessionValue("shipping_addresses") || [];
    const selected = addresses.find(
      (address) => String(address.id) === String(id),
    );

    if (selected) {
      set({
        isEditAddress: true,
        editableAddress: selected,
      });
      get().setStep(4);
    } else {
      console.error("Address not found for editing:", id);
    }
  },

  handleAddAddress: () => {
    set({
      isEditAddress: false,
      editableAddress: {},
    });
    get().setStep(4);
  },

  handleEmailSubmit: async (email) => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/; // Simple email regex

    // Validate the email address
    if (!email || !emailRegex.test(email)) {
      set((state) => ({
        otpData: {
          ...state.otpData,
          error: "Please enter a valid email address.",
        },
      }));
      return;
    }

    // Indicate loading
    set((state) => ({
      otpData: {
        ...state.otpData,
        error: "",
        isLoading: true,
      },
    }));

    try {
      const password = generatePassword();

      const newCustomer = await createShopifyCustomer({ email, password });

      if (!newCustomer?.success) {
        const errorMessage =
          newCustomer?.errors?.[0] ||
          "Failed to create customer. Please try again later.";

        const specificErrorMessage = `We have sent an email to ${email}, please click the link included to verify your email address.`;

        if (errorMessage.includes(specificErrorMessage)) {
          throw new Error(
            "This email is already in use, please use a different email for signup.",
          );
        } else {
          throw new Error(errorMessage);
        }
      }

      localStorage.setItem("newCustomer", JSON.stringify(newCustomer));

      const loginResult = await handleCustomeShopifyLogin(email, password);

      if (!loginResult?.success) {
        throw new Error("Failed to log in customer. Please try again.");
      }

      const shopifyCustomerId = newCustomer.customer.id;
      const shopifyDomain = window.Shopify.shop;

      await createCustomerLogin({
        shopifyCustomerId,
        email,
        password,
        phone: `+${get().otpData.phoneNumber}`,
        shopifyDomain,
      });

      const orderSummaryTotalQuantity = get().orderSummaryTotalQuantity;
      get().setIsLoginProcessCompleted(true);
      if (orderSummaryTotalQuantity === 0) {
        window.location.href = `https://${window.Shopify.shop}/account`;
        return;
      } else if (orderSummaryTotalQuantity > 0) {
        const currentStep = await getCurrentStep();
        get().setStep(currentStep);
        return;
      }
      set((state) => ({
        otpData: {
          ...state.otpData,
          step: currentStep, // Dynamically set the next step
          error: "",
        },
      }));
    } catch (error) {
      console.error("Error during email submission:", error.message || error);
      sendErrorToAPI(error, "otpStore.handleEmailSubmit", "error", {
        operation: "handleEmailSubmit",
        email: email ? email.substring(0, 3) + "****" : null,
      });
      set((state) => ({
        otpData: {
          ...state.otpData,
          error: error.message || "An error occurred during signup.",
        },
      }));
    } finally {
      // Reset loading state
      set((state) => ({
        otpData: {
          ...state.otpData,
          isLoading: false,
        },
      }));
    }
  },

  redirectTOCheckout: function () {
    setTimeout(() => {
      window.location.href = "/checkout";
    }, 500);
    get().setOtpData({ isLoading: false });
  },

  // Pure state
  orderSummary: {
    productData: [],
    totalPrice: 0,
    totalQuantity: 0,
    currencyCode: "USD",
    discountDetails: {
      code: "",
      type: "",
      value: "",
      amount: 0,
    },
    summaryLoading: true,
  },

  fetchProductDetails: async () => {
    try {
      // debugger;
      get().setOrderSummary({ summaryLoading: true });
      // set({ isCartManipulationProcessCompleted: false });

      // CRITICAL: Remove discount codes FIRST before fetching cart data
      // This ensures currentCartData always has clean cart without old discount codes
      const settings = getSessionValue("settingSession");
      const isPartialEnabled = settings?.partialPaymentEnabled === true;
      const partialPaymentFlowVersion = settings?.partialPaymentFlowVersion;

      // if (partialPaymentFlowVersion == 2 && isPartialEnabled == true) {
      //   await removeDiscountCodeAndAttribute();
      //   setSessionValue("codk_created_discount_code", null);
      //   setSessionValue("codk_discount_summary", null);
      // }

      let cartData = await getCart(true);

      if (!cartData?.items || cartData.items.length === 0) {
        console.warn("⚠️ Cart items missing or empty. Retrying getCart...");
        cartData = await getCart(true);
      }

      saveDiscountSummaryToSession();

      const cartToken = cartData?.token;
      getStorefrontCartId(cartToken);

      get().setCurrentCartData(cartData);

      // if (isPartialEnabled && partialPaymentFlowVersion == 2) {
      //   preCreateCartsForEligibleRules().catch((preCreateError) => {
      //     console.warn(
      //       "⚠️ preCreateCartsForEligibleRules failed:",
      //       preCreateError
      //     );
      //   });
      // }

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
      const quantityCount = items.reduce((acc, item) => acc + item.quantity, 0);

      let discountDetails = { code: "", type: "", value: "", amount: 0 };

      const cartDiscountApplications =
        cartData.cart_level_discount_applications || [];
      if (cartDiscountApplications.length > 0) {
        discountDetails = {
          code: cartDiscountApplications[0].title,
          type: cartDiscountApplications[0].value_type,
          value: cartDiscountApplications[0].value,
          amount: cartDiscountApplications[0].total_allocated_amount,
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
              amount: discount.total_allocated_amount,
            };
            break;
          }
        }
      }

      get().setOrderSummary({
        productData: items,
        totalPrice: total,
        totalQuantity: quantityCount,
        currencyCode: cartData.currency || "USD",
        discountDetails: discountDetails,
        summaryLoading: false,
      });

      // get().setOrderSummaryTotalQuantity(quantityCount);
      // get().setIsCartManipulationProcessCompleted(true);
      get().setIsCartReady(true);
    } catch (error) {
      console.error("Error fetching product details:", error);
      sendErrorToAPI(error, "otpStore.fetchProductDetails", "error", {
        operation: "fetchProductDetails",
        cartToken: get().currentCartData?.token || "unknown",
      });
      // get().setIsCartManipulationProcessCompleted(true);
      get().setIsCartReady(true); // Ensure skeleton loader is removed even on error
      // get().setOrderSummary({ summaryLoading: false }); // Stop summary loading state
    }
  },

  initializeFetchProductDetails: async () => {
    await get().fetchProductDetails();
  },
}));

export default useOtpStore;

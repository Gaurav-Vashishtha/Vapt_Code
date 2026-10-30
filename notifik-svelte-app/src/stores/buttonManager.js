// Button Manager - Central state management for the Svelte OTP flow
// Handles modal state, screen navigation, and button actions (matching React app's ButtonManager.js)
import { writable, get } from "svelte/store";
import { mapCartToOrderSummary } from "../utils/helpers.js";
import { getSessionValue, setSessionValue } from "../services/sessionService.js";
import { settingsStore } from "./settingsStore.js";
import {
  hideCartDrawer,
  showCartDrawer,
  initializeCartDrawerManager,
  disconnectCartDrawerButtonBlockObservers,
} from "../utils/cartDrawerManager.js";
import { notifyParentToDestroyIframe } from "../utilities/otpUtils.js";

// Initialize cart drawer manager on load (like React's OTPManager useEffect)
if (typeof window !== "undefined") {
  initializeCartDrawerManager();
}

// Initial state - matches notifik-js-app state structure
const initialState = {
  currentScreen: "phone",
  previousScreen: null,
  initialScreen: "phone",
  isOpen: false,

  phoneNumber: "",
  countryCode: "91",
  countryCallingCode: "+91",
  isValidNumber: false,

  otpCode: ["", "", "", ""],
  timerSeconds: 60,
  canResend: false,
  resendAttempts: 0,
  otpMode: "SMS",

  addresses: [],
  selectedAddressId: null,

  paymentRules: [],
  cartTotal: 0,
  currencyCode: "INR",

  cart: {
    items: [],
    total_price: 0,
    original_total_price: 0,
    total_discount: 0,
    attributes: {},
    token: null,
  },

  ip_address: "",
  deviceId: "",

  settings: null,

  /** Primary CTA on payment screen: label, loading, disabled, action ('submit' | 'complete_order' | 'pay_now') */
  primaryButton: {
    label: "Proceed to Payment",
    loading: false,
    disabled: true,
    action: "submit",
  },

  /** Global logout confirm (rendered at modal root so it’s not clipped on payment screen) */
  showCodOrderFlow: false,
  showLogoutConfirm: false,
  logoutConfirmPhone: "",
  logoutConfirmLoading: false,
  logoutConfirmOnConfirm: null,

  isLoading: false,
  isVerifying: false,

  error: null,

  isOTPSkipped: false,
  isBuyNowButton: false,

  preOrderOtpResponse: null,
  customerEmail: null,
  debug: true,
};

// Initialize state with persisted values from sessionStorage
const verifiedData = getSessionValue("verifiedNumberData", null);
const settings = getSessionValue("settingSession", null);

const initialStoreState = {
  ...initialState,
  // Restore phone number and country code from verifiedNumberData
  phoneNumber: verifiedData?.otpVerifiedPhoneNumber || initialState.phoneNumber,
  countryCode: verifiedData?.countryCode || initialState.countryCode,
  countryCallingCode:
    verifiedData?.countryCallingCode || initialState.countryCallingCode,
  // Restore settings
  settings: settings || initialState.settings,
};

// Create writable store with persisted initial state
export const appStore = writable(initialStoreState);

// Helper functions to update specific parts of state
export const actions = {
  setScreen(screen) {

    appStore.update((state) => {
      // ⚡ CRITICAL: Only track previousScreen if:
      // 1. Current screen is not the default/initial screen ("phone")
      // 2. Current screen is different from the new screen
      // 3. Current screen is not "processing" (which indicates returning from checkout)
      // This prevents tracking "phone" as previousScreen when user never actually saw it
      // (e.g., when OTP is disabled and modal opens directly to payment/address)
      // Also prevents tracking "processing" as previousScreen when returning from checkout
      const isInitialScreen =
        state.currentScreen === "phone" &&
        (state.currentScreen === state.initialScreen || !state.previousScreen);
      const isScreenChanging = state.currentScreen !== screen;
      const isResettingFromProcessing = state.currentScreen === "processing";

      // Don't track previousScreen if:
      // - It's the initial screen transition (phone → something)
      // - OR we're resetting from "processing" (user returned from checkout)
      const shouldTrackPrevious =
        !isInitialScreen && isScreenChanging && !isResettingFromProcessing;

      const newState = {
        ...state,
        // Only update previousScreen if we're navigating from a real screen (not initial default)
        previousScreen: shouldTrackPrevious
          ? state.currentScreen
          : state.previousScreen,
        currentScreen: screen,
      };

      return newState;
    });
  },

  async openModal() {
    try {
      appStore.update((state) => ({ ...state, isOpen: true }));
      const { otpStoreActions } = await import("./otpStore.js");
      otpStoreActions.clearBuyNowError();

      return true;
    } catch (error) {

      // Dispatch failure event
      if (typeof window !== "undefined") {
        window.dispatchEvent(
          new CustomEvent("codking:openModalFailure", {
            detail: {
              error: error.message,
              stack: error.stack,
              timestamp: new Date().toISOString(),
            },
          }),
        );
      }

      return false;
    }
  },

  closeModal({ destroyIframe = true } = {}) {
    appStore.update((state) => ({ ...state, isOpen: false }));
    import("../services/sessionService.js")
      .then(async (sessionService) => {
        // Reset order summary complete flag
        sessionService.resetOrderSummaryComplete();
        // Reset cart revert flag (per latest guidance, also on modal close)
        sessionService.resetCartRevertIsComplete();
        // Reset cart readiness so next open recomputes summary/pre-create carts
        appStore.update((state) => ({ ...state, isCartReady: false }));
        // Reset otpStore cart readiness (used by OrderSummaryCard for buy now flow)
        const { otpStoreActions } = await import("./otpStore.js");
        otpStoreActions.setIsCartReady(false);
        // Reset partial payment readiness flag
        sessionService.setSessionValue(
          "isPartialPaymentCartReadyAndUpdated",
          false,
        );
        // Reset partial_payment_results
        sessionService.setSessionValue("partial_payment_results", null);
        // Reset partial_payment_cart_results
        sessionService.setSessionValue("partial_payment_cart_results", null);
        // Reset Buy Now variant if any (quantity is no longer stored; picked from DOM each time)
        sessionService.setSessionValue("cod_king_buy_now_variantId", null);
        // Reset created discount code
        const createdDiscountCode = sessionService.getSessionValue(
          "codk_created_discount_code",
        );
        if (createdDiscountCode) {
          sessionService.setSessionValue("codk_created_discount_code", null);
        }
      })
      .catch((error) => {

      });
    // Stop observing parent DOM when modal closes (avoids slowing the page)
    disconnectCartDrawerButtonBlockObservers();
    // Destroy iframe on close
    if (destroyIframe) {
      notifyParentToDestroyIframe();
    }
  },

  setPhoneNumber(phoneNumber, countryCode) {
    appStore.update((state) => ({ ...state, phoneNumber, countryCode }));
  },

  setOtpCode(otpCode) {
    appStore.update((state) => ({ ...state, otpCode }));
  },

  setTimer(seconds, canResend = false) {
    appStore.update((state) => ({
      ...state,
      timerSeconds: seconds,
      canResend,
    }));
  },

  setCanResend(canResend) {
    appStore.update((state) => ({ ...state, canResend }));
  },

  setOtpMode(mode) {
    appStore.update((state) => ({ ...state, otpMode: mode }));
  },

  setValidNumber(isValid) {
    appStore.update((state) => ({ ...state, isValidNumber: isValid }));
  },

  setCountryCallingCode(code) {
    appStore.update((state) => ({ ...state, countryCallingCode: code }));
  },

  setAddresses(addresses, selectedAddressId = null) {
    appStore.update((state) => ({
      ...state,
      addresses,
      selectedAddressId: selectedAddressId || addresses[0]?.id || null,
      // Note: shippingAddressCount is now managed by otpStore
      // shippingAddressCount: addresses.length,
    }));
  },

  selectAddress(addressId) {
    appStore.update((state) => ({ ...state, selectedAddressId: addressId }));
  },

  // setPaymentRules(rules, selectedRuleId = null) {
  //   appStore.update((state) => ({
  //     ...state,
  //     paymentRules: rules,
  //     selectedRuleId: selectedRuleId || rules[0]?.id || null,
  //   }));
  // },

  setSettings(settings) {
    /* One way in, three places to keep in step: the store the UI renders from,
       the app state, and the sessionStorage copy the plain .js helpers read on
       demand. Settings changing under a running widget is what the admin's
       live preview does on every keystroke. */
    settingsStore.set(settings);
    appStore.update((state) => ({ ...state, settings }));
    try {
      setSessionValue("settingSession", settings);
    } catch (_e) {}
  },

  setPrimaryButton(primaryButton) {
    appStore.update((state) => ({
      ...state,
      primaryButton: { ...state.primaryButton, ...primaryButton },
    }));
  },

  setShowCodOrderFlow(show) {
    appStore.update((state) => ({ ...state, showCodOrderFlow: !!show }));
  },

  setCartTotal(total, currencyCode = "INR") {
    appStore.update((state) => ({ ...state, cartTotal: total, currencyCode }));
  },

  setCart(cart) {
    appStore.update((state) => {
      return {
        ...state,
        cart,
      };
    });
  },

  setDeviceId(deviceId) {
    appStore.update((state) => ({ ...state, deviceId }));
  },

  // Loading states
  setLoading(isLoading) {
    appStore.update((state) => ({ ...state, isLoading }));
  },

  setVerifying(isVerifying) {
    appStore.update((state) => ({ ...state, isVerifying }));
  },

  // Error states
  setError(error) {
    appStore.update((state) => ({ ...state, error }));
  },

  // Feature flags
  setPreOrderOtpResponse(response) {
    appStore.update((state) => ({
      ...state,
      preOrderOtpResponse: response,
    }));
  },

  setOTPSkipped(skipped) {
    appStore.update((state) => ({
      ...state,
      isOTPSkipped: skipped,
    }));
  },

  setIsBuyNowButton(isBuyNow) {
    appStore.update((state) => ({
      ...state,
      isBuyNowButton: isBuyNow,
    }));
  },

  setCustomerEmail(email) {
    appStore.update((state) => ({
      ...state,
      customerEmail: email,
    }));
  },

  openLogoutConfirm(phone, onConfirm) {
    appStore.update((state) => ({
      ...state,
      showLogoutConfirm: true,
      logoutConfirmPhone: phone || "",
      logoutConfirmOnConfirm: onConfirm || null,
      logoutConfirmLoading: false,
    }));
  },

  closeLogoutConfirm() {
    appStore.update((state) => ({
      ...state,
      showLogoutConfirm: false,
      logoutConfirmPhone: "",
      logoutConfirmOnConfirm: null,
      logoutConfirmLoading: false,
    }));
  },

  setLogoutConfirmLoading(value) {
    appStore.update((state) => ({
      ...state,
      logoutConfirmLoading: value,
    }));
  },
};

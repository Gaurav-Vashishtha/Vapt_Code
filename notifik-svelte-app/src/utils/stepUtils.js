import {
  getSessionValue,
  setSessionValue,
  setAddressCompleted,
  setSelectedAddress,
  setCustomerEmail,
  getShopDomain,
} from "../services/sessionService.js";
import { get } from "svelte/store";
import { appStore, actions } from "../stores/buttonManager.js";
import { otpStore } from "../stores/otpStore.js";
import { samePhoneNumber } from "./helpers.js";

// checkShippingConditions - exact replica from React app
export function checkShippingConditions() {
  const preOrderOtpResponse = getSessionValue("preOrderOtpResponse");
  const settings = getSessionValue("settingSession");

  // Case 1: Login flow enabled and no shipping address available
  if (
    settings?.preIsLoginEnabled === true &&
    settings?.isPrefilledAddressEnabled === true &&
    (!preOrderOtpResponse?.shippingAddress ||
      !preOrderOtpResponse?.shippingAddress.length)
  ) {
    setSessionValue("customer-id", preOrderOtpResponse?.customerId);
    setCustomerEmail(preOrderOtpResponse?.email);
    return { success: true, nextStep: 4 }; // Add address
  }

  // Case 2: Login flow enabled and shipping address exists
  if (
    settings?.preIsLoginEnabled === true &&
    settings?.isPrefilledAddressEnabled === true &&
    preOrderOtpResponse?.shippingAddress?.length > 0
  ) {
    setSessionValue("shipping_addresses", preOrderOtpResponse?.shippingAddress);
    setSessionValue("customer-id", preOrderOtpResponse?.customerId);
    setCustomerEmail(preOrderOtpResponse?.email);
    return { success: true, nextStep: 3 }; // View address
  }

  // Case 3: Prefilled address enabled but login flow disabled
  if (
    settings?.preIsLoginEnabled === false &&
    settings?.isPrefilledAddressEnabled === true
  ) {
    if (preOrderOtpResponse?.shippingAddress?.length > 0) {
      setSessionValue(
        "shipping_addresses",
        preOrderOtpResponse.shippingAddress,
      );
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setCustomerEmail(preOrderOtpResponse?.email);
      return { success: true, nextStep: 3 }; // View address
    } else {
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setCustomerEmail(preOrderOtpResponse?.email);
      return { success: true, nextStep: 4 }; // Add address
    }
  }

  // Case 4: Prefilled address and login flow both disabled
  if (
    settings?.preIsLoginEnabled === false &&
    settings?.isPrefilledAddressEnabled === false
  ) {
    return { success: true, nextStep: 5 }; // Proceed to verified tick mark
  }

  // Case 5: Partial payment enabled and prefilled address enabled
  if (
    settings?.partialPaymentEnabled === true &&
    settings?.isPrefilledAddressEnabled === true
  ) {
    if (preOrderOtpResponse?.shippingAddress?.length > 0) {
      setSessionValue(
        "shipping_addresses",
        preOrderOtpResponse.shippingAddress,
      );
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setCustomerEmail(preOrderOtpResponse?.email);
      return { success: true, nextStep: 3 }; // Proceed to view address
    } else {
      setSessionValue("customer-id", preOrderOtpResponse?.customerId);
      setCustomerEmail(preOrderOtpResponse?.email);
      return { success: true, nextStep: 4 }; // Add address
    }
  }

  // Case 6: Partial payment enabled and prefilled address disabled
  if (
    settings?.partialPaymentEnabled === true &&
    settings?.isPrefilledAddressEnabled === false
  ) {
    setSessionValue("customer-id", preOrderOtpResponse?.customerId);
    setCustomerEmail(preOrderOtpResponse?.email);
    return { success: true, nextStep: 5 }; // Proceed to verified tick
  }

  // Case 7: Partial payment and login flow both disabled
  if (
    settings?.partialPaymentEnabled === false &&
    settings?.preIsLoginEnabled === false
  ) {
    return { success: true, nextStep: 5 }; // Proceed to verified tick mark
  }

  // Default case
  return { success: true, nextStep: 5 };
}

// handleCustomeShopifyLogin - exact replica from React app
const handleCustomeShopifyLogin = async (email, password) => {
  try {
    const csrfTokenElement = document.querySelector(
      'input[name="authenticity_token"]',
    );
    const csrfToken = csrfTokenElement
      ? /** @type {HTMLInputElement} */ (csrfTokenElement).value
      : null;

    const body = new URLSearchParams({
      form_type: "customer_login",
      utf8: "\u2713",
      authenticity_token: csrfToken || "",
      "customer[email]": email,
      "customer[password]": password,
      return_url: window.location.href,
    }).toString();

    const response = await fetch("/account/login", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });

    if (!response.ok) return { success: false, error: "Login failed. Please try again." };
    return checkShippingConditions();
  } catch (_error) {
    return { success: false, error: "Login failed. Please try again." };
  }
};

/**
 * Get current step - EXACT replica of React app's getCurrentStep
 *
 * This function:
 * 1. Determines the current step using the exact same logic as React app
 * 2. Maps the step number to a screen name (Svelte-specific)
 * 3. Sets the screen directly via actions.setScreen()
 *
 * @returns {Promise<string>} Screen name ("phone", "otp", "address", etc.)
 */
export async function getCurrentStep() {
  const settings = getSessionValue("settingSession") || {};
  const session = getSessionValue("verifiedNumberData");
  let currentStepKey;
  // Settings may arrive normalized (camelCase) or raw (snake_case), and values
  // can be booleans or "true"/"false" strings — read both so routing flags like
  // OTP enablement never silently fall through as undefined.
  const truthy = (v) => v === true || v === "true";
  const enablePreOrderOtp =
    truthy(settings.enablePreOrderOtp) || truthy(settings.enable_pre_order_otp);
  const isPrefilledAddressEnabled =
    truthy(settings.isPrefilledAddressEnabled) ||
    truthy(settings.is_prefilled_address_enabled);
  const partialPaymentEnabled =
    truthy(settings.partialPaymentEnabled) ||
    truthy(settings.partial_payment_enabled);
  const preIsLoginEnabled =
    truthy(settings.preIsLoginEnabled) || truthy(settings.pre_is_login_enabled);
  const codFormRaw = settings.cod_form_enabled ?? settings.codFormEnabled;
  const codFormEnabled = !!(codFormRaw === true || codFormRaw === "true");
  let pp = settings.private_payment_provider ?? settings.privatePaymentProvider;
  if (typeof pp === "string") {
    try {
      pp = JSON.parse(pp);
    } catch {
      pp = /razorpay|api_key/.test(pp) ? { name: "razorpay" } : null;
    }
  }
  const hasPaymentProvider = !!(
    pp &&
    typeof pp === "object" &&
    (pp.name || pp.api_key || pp.api_key_id || pp.secret)
  );
  const needsAddressStep = !!(isPrefilledAddressEnabled || codFormEnabled || hasPaymentProvider);

  // A prior verification is only valid for the number it was issued to. If a
  // different number was entered since, the stored verifiedNumberData is stale —
  // force re-verification instead of reusing the previous number's saved address.
  const enteredPhone = get(appStore)?.phoneNumber;
  const verifiedPhone = session?.otpVerifiedPhoneNumber;
  const staleVerification = !!(
    verifiedPhone &&
    enteredPhone &&
    !samePhoneNumber(verifiedPhone, enteredPhone)
  );
  const isOtpVerified = !!(session && session.isOTPVerified && !staleVerification);

  // Define the step keys
  const steps = {
    OTP_VERIFICATION: "OTP_VERIFICATION",
    CUSTOMER_LOGIN: "CUSTOMER_LOGIN",
    SHIPPING_ADDRESS: "SHIPPING_ADDRESS",
    ADD_ADDRESS: "ADD_ADDRESS",
    PARTIAL_PAYMENT: "PARTIAL_PAYMENT",
    REDIRECTION_TO_CHECKOUT: "REDIRECTION_TO_CHECKOUT",
  };

  // Create the mapping relation:
  const mapping = {
    OTP_VERIFICATION: 1,
    CUSTOMER_LOGIN: 6,
    SHIPPING_ADDRESS: 3,
    ADD_ADDRESS: 4,
    PARTIAL_PAYMENT: 7,
    REDIRECTION_TO_CHECKOUT: 5,
  };

  const handlePreLoginEnabled = async (preIsLoginEnabled) => {
    if (preIsLoginEnabled) {
      // ⚡ CRITICAL: Read fresh state to get latest orderSummaryTotalQuantity (from otpStore)
      const currentOtpState = get(otpStore);
      const { email, password } =
        getSessionValue("preOrderOtpResponse")?.customerLogin || {};
      if (email && password) {
        setSessionValue("CustomerCredential", { email, password });
        otpStore.setCustomerCredentialAvailability(true);
        const loginResult = await handleCustomeShopifyLogin(email, password);
        if (loginResult.success) {
          otpStore.setIsLoginProcessCompleted(true);
          // ⚡ CRITICAL: Read fresh state again after setting login completed (from otpStore)
          const updatedOtpState = get(otpStore);
          if (updatedOtpState.orderSummaryTotalQuantity === 0) {
            window.location.href = `https://${window.Shopify.shop}/account`;
            return;
          } else if (updatedOtpState.orderSummaryTotalQuantity > 0) {
            return getMappedStep(); // Proceed to next step
          }
        } else {
          otpStore.setCustomerCredentialAvailability(false);
          otpStore.setIsLoginProcessCompleted(false);
          currentStepKey = steps.CUSTOMER_LOGIN;
          return currentStepKey;
        }
      } else {
        otpStore.setCustomerCredentialAvailability(false);
        otpStore.setIsLoginProcessCompleted(false);
        currentStepKey = steps.CUSTOMER_LOGIN;
        return currentStepKey;
      }
    }
  };

  async function getMappedStep() {
    // ⚡ CRITICAL: Always read fresh state to get latest completion flags
    // This ensures that when setAddressCompleted(true) is called, we see the updated value
    // Priority order (matches React app):
    // 1. OTP verification (if enabled and not verified)
    // 2. Login flow (if enabled and not completed)
    // 3. Address selection (if enabled and not completed)
    // 4. Partial payment (if enabled and not completed)
    // 5. Default: redirect to checkout

    // ⚡ CRITICAL: Read completion flags from otpStore (matching React app)
    const latestOtpState = get(otpStore);
    const latestAppState = get(appStore);
    const {
      isPrefilledAddressCompleted,
      isPartialPaymentCartReadyAndUpdated,
      isLoginProcessCompleted,
    } = latestOtpState;

    // ⚡ DEBUG: Log the actual value to see why it's false

    // Priority 1: OTP verification (if enabled and not verified)
    if (enablePreOrderOtp && !isOtpVerified) {
      currentStepKey = steps.OTP_VERIFICATION;
      return currentStepKey;
    }

    // Priority 2: Login flow (if enabled and not completed)
    if (preIsLoginEnabled && !isLoginProcessCompleted) {
      return await handlePreLoginEnabled(preIsLoginEnabled);
    }

    // Priority 3: Address selection (if address step needed and not completed)
    // Show shipping address screen first when: prefilled address, COD form, or Pay Now is used
    if (needsAddressStep && !isPrefilledAddressCompleted) {
      // COD form on with auto-fill off: don't reuse a saved address, make the
      // customer enter one. Other flows keep their existing reuse behavior.
      if (codFormEnabled && !isPrefilledAddressEnabled) {
        otpStore.setIsEditAddress(false);
        otpStore.setEditableAddress({});
        currentStepKey = steps.ADD_ADDRESS;
        return currentStepKey;
      }
      // If addresses exist in OTP response, populate session and store so the address screen shows "select address" not "add address"
      const preOrderFromSession = getSessionValue("preOrderOtpResponse");
      const preOrderFromStore = get(appStore).preOrderOtpResponse;
      const preOrderOtpResponse = preOrderFromSession || preOrderFromStore;
      const addressesFromOtp =
        preOrderOtpResponse?.shippingAddress ??
        preOrderOtpResponse?.shippingAddresses ??
        preOrderOtpResponse?.shipping_addresses;
      // Saved addresses can live in the OTP response, the shipping_addresses
      // session key, or the app store. Only treat the user as having "no saved
      // address" (→ add-address form) when ALL of these are empty.
      const sessionAddresses = getSessionValue("shipping_addresses");
      const storeAddresses = get(appStore)?.addresses;
      const firstNonEmpty = (...candidates) =>
        candidates.find((c) => Array.isArray(c) && c.length > 0) || null;
      const list = firstNonEmpty(
        addressesFromOtp,
        sessionAddresses,
        storeAddresses,
      );
      if (list?.length > 0) {
        setSessionValue("shipping_addresses", list);
        actions.setAddresses(list); // selects first address by default
        // When partial payment is enabled, auto-select first address and skip to payment for faster checkout
        if (partialPaymentEnabled) {
          setSelectedAddress(list[0]); // required for orderService.resolveShippingAddress (COD/Razorpay)
          otpStore.setIsPrefilledAddressCompleted(true);
          setAddressCompleted(true);
          // Fall through to Priority 4 (partial payment) — do not return
        } else {
          currentStepKey = steps.SHIPPING_ADDRESS;
          return currentStepKey;
        }
      } else {
        // No saved addresses for this verified number.
        // Prefilled address is only a checkout convenience (it pre-fills the
        // address at Shopify checkout). If nothing in the widget actually needs
        // the address collected here — no COD form, no in-widget payment provider,
        // no partial payment — then showing an "add address" form is pure friction.
        // Skip it and redirect straight to checkout instead.
        const addressRequiredInWidget =
          codFormEnabled || hasPaymentProvider || partialPaymentEnabled;
        if (!addressRequiredInWidget) {
          currentStepKey = steps.REDIRECTION_TO_CHECKOUT;
          return currentStepKey;
        }
        // Otherwise open the address form directly (in "add" mode) instead of an
        // empty address-list screen.
        otpStore.setIsEditAddress(false);
        otpStore.setEditableAddress({});
        currentStepKey = steps.ADD_ADDRESS;
        return currentStepKey;
      }
    }

    // Priority 4: Partial payment (if enabled and not completed)
    if (partialPaymentEnabled && !isPartialPaymentCartReadyAndUpdated) {
      currentStepKey = steps.PARTIAL_PAYMENT;
      return currentStepKey;
    }

    // Priority 5: All steps complete → Redirect to checkout
    currentStepKey = steps.REDIRECTION_TO_CHECKOUT;
    return currentStepKey;
  }

  // Call getMappedStep and await its result
  currentStepKey = await getMappedStep();

  // Get the step number from mapping
  const stepNumber = mapping[currentStepKey];

  // INTERNAL: Map step number to screen name (Svelte-specific)
  // React app uses step numbers directly in layout, Svelte app uses screen names
  // ⚡ CRITICAL: Read fresh state to get latest phoneNumber
  const currentState = get(appStore);
  const phoneNumber = currentState?.phoneNumber;
  const hasPhoneNumber = !!(
    phoneNumber &&
    typeof phoneNumber === "string" &&
    phoneNumber.trim()
  );
  const latestSession = getSessionValue("verifiedNumberData");
  const latestIsOtpVerified = !!(latestSession && latestSession.isOTPVerified);

  // Step 1 from getCurrentStep means OTP_VERIFICATION
  // React app shows: step 1=phone (ContactForm), step 2=otp (VerifyOTPForm)
  // In Svelte: If phone was submitted but OTP not verified, show OTP screen
  // If phone not submitted yet, show phone screen (initial state)
  const step1Screen = hasPhoneNumber && !latestIsOtpVerified ? "otp" : "phone";

  // Map step numbers to screen names (matching React app's layout rendering)
  const screenMapping = {
    1: step1Screen, // OTP_VERIFICATION → OTP if phone submitted, else phone
    3: "address", // SHIPPING_ADDRESS → React step 3 (address selection)
    4: "address-form", // Add/edit address → React step 4
    5: "processing", // REDIRECTION_TO_CHECKOUT → React step 5 (processing/verified)
    6: "phone", // CUSTOMER_LOGIN → React step 6 (login/email form) - Note: Svelte app doesn't have separate login screen
    7: "payment", // PARTIAL_PAYMENT → React step 7 (payment screen)
  };

  const screenName = screenMapping[stepNumber] || "phone";

  // Set the screen directly (all step logic is now in one place)
  actions.setScreen(screenName);

  // Return screen name for any callers that need it
  return screenName;
}

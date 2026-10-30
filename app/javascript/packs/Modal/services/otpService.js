import axios from "axios";
import { IS_BUY_NOW_BUTTON } from "../services/domUtils";
import { sendErrorToAPI } from "./errorReporter";
import {
  getSessionValue,
  setSessionValue,
  FAILED_TO_VERIFY_OTP,
  removeSessionValue,
  debugLog,
  getMachineId,
  hashJsonObject,
  simplifyCartItems,
  getDeviceType,
  getMachineDetailsFromBrowser,
  getCurrentStep,
  addCartAttributesWithOtpStore,
} from "../utilities/otpUtils";
import { emitShopifyVisitorIdentify } from "../utilities/shopifyVisitor";
import { syncSessionWithCart } from "../utilities/syncSessionWithCart";
// import { createCart } from "./cartService";
// import useOtpStore from "../stores/otpStore";
// import { removePartialPaymentVariants } from "../components/partialPaymentFlow/partialPaymentUtilities";

const OTP_VERIFIED = "OTP_VERIFIED";
let preOrderOtpResponse = null;

// Fetches settings for OTP from the server
export const fetchSettings = async () => {
  try {
    const response = await axios.get(
      `https://${process.env.APP_HOST}/script/lightweight_settings?domain=${window.Shopify.shop}`,
    );
    return response;
  } catch (error) {
    console.error("Error fetching settings:", error);
    sendErrorToAPI(error, "fetchSettings", "error", {
      operation: "fetchSettings",
      domain: window.Shopify.shop,
    });
    throw error;
  }
};

export const fetchMachineDetails = async () => {
  try {
    const cachedMachineDetails = getSessionValue("machineDetails");
    if (cachedMachineDetails) {
      return cachedMachineDetails;
    }

    const response = await axios.get("https://ipapi.co/json/");

    setSessionValue("machineDetails", response);

    return response;
  } catch (error) {
    console.error("Error fetching machine details from API:", error);

    try {
      const fallbackData = await getMachineDetailsFromBrowser();

      if (fallbackData) {
        setSessionValue("machineDetails", fallbackData);
        return fallbackData;
      }
    } catch (browserError) {
      console.error("Browser fallback also failed:", browserError);
    }

    sendErrorToAPI(error, "fetchMachineDetails", "error", {
      operation: "fetchMachineDetails",
      shop: window.Shopify.shop,
      fallbackAttempted: true,
    });
    throw error;
  }
};

// Fetches cart attributes to check OTP verification status
export const getCartAttributes = async () => {
  try {
    const response = await axios.get(`${window.Shopify.routes.root}cart.js`);
    return response;
  } catch (error) {
    console.error("Error fetching cart attributes:", error);
    sendErrorToAPI(error, "getCartAttributes", "error", {
      operation: "getCartAttributes",
      shop: window.Shopify.shop,
    });
    throw error;
  }
};

// Sends OTP to the user's phone number
export const sendOtpRequest = async ({
  countryCode,
  phoneNumber,
  countryCallingCode,
  ipAddress,
  deviceId,
  mode = "SMS",
  device_type,
  cartDetails,
}) => {
  try {
    const cartFilteredData = simplifyCartItems(cartDetails);
    const response = await axios.post(
      `https://${process.env.APP_HOST}/order_confirmations/pre_order_otp`,
      {
        country_code: countryCode,
        phone: phoneNumber,
        ip_address: ipAddress,
        device_id: deviceId,
        shop: window.Shopify.shop,
        mode: mode,
        device_type,
        cart_details: cartFilteredData,
      },
    );
    return response;
  } catch (error) {
    console.error("Error sending OTP:", error);
    sendErrorToAPI(error, "sendOtpRequest", "error", {
      operation: "sendOtpRequest",
      mode,
      phoneNumber: phoneNumber ? phoneNumber.substring(0, 3) + "****" : null,
      countryCode,
      shop: window.Shopify.shop,
    });
    throw error;
  }
};

export const verifyOtpRequest = ({
  countryCode,
  countryCallingCode,
  phoneNumber,
  ipAddress,
  deviceId,
  otp,
  mode,
  widgetState,
}) => {
  const sessionEmail = getSessionValue("customer-email");
  const verifyBody = {
    country_code: countryCode,
    phone: phoneNumber,
    ip_address: ipAddress,
    device_id: deviceId,
    shop: window.Shopify.shop,
    otp: otp,
    mode: mode,
  };
  if (sessionEmail && String(sessionEmail).trim()) {
    verifyBody.email = String(sessionEmail).trim();
  }

  // Step 1: Verify OTP
  return fetch(
    `https://${process.env.APP_HOST}/order_confirmations/pre_order_otp_verify`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(verifyBody),
    },
  )
    .then((response) => response.json())
    .then((data) => {
      preOrderOtpResponse = data;
      setSessionValue("preOrderOtpResponse", preOrderOtpResponse);

      if (data.verification) {
        const settings = getSessionValue("settingSession");

        if (data.verification) {
          return addCartAttribute(phoneNumber, data.verification, widgetState, {
            countryCallingCode,
          });
        }
      } else {
        widgetState.setIsLoading(false);
        widgetState.setError(FAILED_TO_VERIFY_OTP);

        // Create error with payload information
        const error = new Error("OTP verification failed");
        error.payload = {
          request: {
            country_code: countryCode,
            phone: phoneNumber,
            ip_address: ipAddress,
            device_id: deviceId,
            shop: window.Shopify.shop,
            otp: otp,
            mode: mode,
          },
          response: data,
        };

        sendErrorToAPI(error, "verifyOtpRequest", "error", {
          operation: "verifyOtpRequest",
          request: {
            country_code: countryCode,
            phone: phoneNumber ? phoneNumber.substring(0, 3) + "****" : null,
            ip_address: ipAddress,
            device_id: deviceId,
            shop: window.Shopify.shop,
            otp: otp ? otp.substring(0, 2) + "****" : null,
            mode: mode,
          },
          response: data,
        });
        return Promise.reject(error);
      }
    })
    .catch((error) => {
      console.error("Error verifying OTP:", error);
      widgetState.setIsLoading(false);
      widgetState.setError(FAILED_TO_VERIFY_OTP);
      widgetState.setShowServerErrorText(true);

      // Add payload information to the error
      error.payload = {
        request: {
          country_code: countryCode,
          phone: phoneNumber,
          ip_address: ipAddress,
          device_id: deviceId,
          shop: window.Shopify.shop,
          otp: otp,
          mode: mode,
        },
        response: null, // No response due to network/parsing error
      };

      sendErrorToAPI(error, "verifyOtpRequest", "error", {
        operation: "verifyOtpRequest",
        request: {
          country_code: countryCode,
          phone: phoneNumber ? phoneNumber.substring(0, 3) + "****" : null,
          ip_address: ipAddress,
          device_id: deviceId,
          shop: window.Shopify.shop,
          otp: otp ? otp.substring(0, 2) + "****" : null,
          mode: mode,
        },
        response: null, // No response due to network/parsing error
      });
      throw error;
    });
};

export const manageBuyNowSkipButton = () => {
  if (IS_BUY_NOW_BUTTON) {
    let variantID = null;
    let quantity = 1; // default quantity

    // 1. Check via URL parameter "variant"
    const urlParams = new URLSearchParams(window.location.search);
    const variantIdFromURL = urlParams.get("variant");
    if (variantIdFromURL) {
      variantID = parseInt(variantIdFromURL, 10);
    }

    if (!variantID) {
      const variantInput = document.querySelector("input.product-variant-id");
      if (variantInput && variantInput.value) {
        variantID = variantInput.value;
      }
    }

    if (!variantID) {
      const acceleratedCheckout = document.querySelector(
        "shopify-accelerated-checkout",
      );
      if (acceleratedCheckout) {
        const variantParams =
          acceleratedCheckout.getAttribute("variant-params");
        if (variantParams) {
          try {
            const variantArray = JSON.parse(variantParams);
            if (variantArray && variantArray.length > 0 && variantArray[0].id) {
              variantID = variantArray[0].id;
            }
          } catch (error) {
            console.error("Error parsing variant-params JSON:", error);
          }
        }
      }
    }

    if (!variantID) {
      const variantSelect = document.querySelector('[name="id"]');
      if (variantSelect && variantSelect.value) {
        variantID = variantSelect.value;
      }
    }

    const quantityInput = document.querySelector('[name="quantity"]');
    if (quantityInput && quantityInput.value) {
      quantity = parseInt(quantityInput.value, 10) || 1;
    }

    if (!variantID) {
      console.error("No variant ID found by any logic.");
    }

    // Step 1: Clear the cart
    clearCart()
      .then(() => {
        // Step 2: Add the item to the cart
        let formData = {
          items: [
            {
              id: variantID,
              quantity: quantity,
            },
          ],
        };

        return fetch(window.Shopify.routes.root + "cart/add.js", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(formData),
        });
      })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        return response.json();
      })
      .then((data) => {
        // Step 3: Redirect to checkout
        setTimeout(() => {
          window.location.href = "/checkout";
        }, 100); // Slight delay before redirecting
      })
      .catch((error) => {
        console.error("Error:", error);
        sendErrorToAPI(error, "manageBuyNowSkipButton", "error", {
          operation: "manageBuyNowSkipButton",
          isBuyNowButton: IS_BUY_NOW_BUTTON,
        });
      });
  }
};

export const executePost = (data) => {
  return fetch(`${window.Shopify.routes.root}cart/update.js`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Requested-With": "XMLHttpRequest",
    },
    body: JSON.stringify(data),
  })
    .then((response) => {
      if (!response.ok) {
        const err = new Error(`Error updating cart: ${response.statusText}`);
        sendErrorToAPI(err, "executePost.updateCart", "error", {
          operation: "executePost.updateCart",
          status: response.status,
          statusText: response.statusText,
        });
        throw err;
      }
      return response;
    })
    .catch((error) => {
      console.error("Error updating cart:", error);
      sendErrorToAPI(error, "executePost.updateCart", "error", {
        operation: "executePost.updateCart",
        data: data ? Object.keys(data) : null,
      });
      throw error;
    });
};

export const addCartAttribute = async (
  codkCartOtpVerifiedPhoneNo,
  isCodkOtpVerifed,
  widgetState,
  opts = {},
) => {
  const attributes = {
    _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
    _codkSessionId: getMachineId(),
  };

  addCartAttributesWithOtpStore(attributes);

  try {
    const response = await executePost({ attributes });

    const responseData = await response.json();
    return await addLineAttribute(
      codkCartOtpVerifiedPhoneNo,
      isCodkOtpVerifed,
      responseData,
      widgetState,
      opts,
    );
  } catch (error) {
    console.error("Error adding cart attribute:", error);
    widgetState?.setIsLoading?.(false);
    widgetState?.setError?.("Failed to update cart attributes");
    sendErrorToAPI(error, "addCartAttribute", "error", {
      operation: "addCartAttribute",
      phoneNumber: codkCartOtpVerifiedPhoneNo,
    });
    throw error;
  }
};

export const createDiscountCode = async ({
  shopifyDomain,
  title,
  discountValue,
  type = "amount",
}) => {
  try {
    const params = new URLSearchParams({
      shopifyDomain: shopifyDomain || window.Shopify?.shop,
      title: title || "Flash Sale",
      discountValue: String(discountValue),
      type: type,
    });

    const apiUrl = `https://${
      process.env.APP_HOST
    }/order_confirmations/create_discount_code?${params.toString()}`;

    const response = await axios.get(apiUrl);

    if (response.data?.error) {
      console.error("API returned error:", response.data.error);
      if (response.data.error.includes("created but code not returned")) {
        console.warn("Discount was created but code not returned from API");
        return {
          ...response,
          data: {
            ...response.data,
            error: response.data.error,
            discountCreated: true,
          },
        };
      }
      throw new Error(response.data.error || "Failed to create discount code");
    }

    return response;
  } catch (error) {
    // Handle HTTP errors (like 500)
    if (error.response?.data?.error) {
      const errorMessage = error.response.data.error;
      // If discount was created but code not returned, return partial success
      if (errorMessage.includes("created but code not returned")) {
        console.warn(
          "Discount was created but code not returned from API (500 error)",
        );
        return {
          data: {
            error: errorMessage,
            discountCreated: true,
          },
        };
      }
    }

    console.error("Error creating discount code:", error);
    sendErrorToAPI(error, "createDiscountCode", "error", {
      operation: "createDiscountCode",
      shopifyDomain,
      title,
      discountValue,
      type,
    });
    throw error;
  }
};

const addLineAttribute = async (
  codkCartOtpVerifiedPhoneNo,
  isCodkOtpVerified,
  attrsResp,
  widgetState,
  opts = {},
) => {
  const settings = getSessionValue("settingSession");
  const { preIsLoginEnabled } = settings;
  const { setStep, setIsLoading, setError } = widgetState;
  const payload = {
    // line: attrsResp.items.findIndex((item) => !item.gift_card) + 1,
    line: attrsResp.items.findIndex((item) => item.variant_id || item.id) + 1,
    quantity: attrsResp.items[0]?.quantity,
    properties: {
      ...attrsResp.items[0]?.properties,
      _otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
      _codkSessionId: getMachineId(),
    },
  };

  try {
    setIsLoading(true);
    const response = await fetch(
      `${window.Shopify.routes.root}cart/change.js`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      },
    );

    if (!response.ok) {
      const errorData = await response.json();
      setError("Failed to update cart line attribute", errorData);
      sendErrorToAPI(
        new Error(errorData?.message || "Failed to update cart line attribute"),
        "addLineAttribute.change",
        "error",
        {
          operation: "addLineAttribute.change",
          response: errorData,
        },
      );
      return { success: false, error: errorData.message || "Unknown error" };
    }

    const data = await response.json();

    const verifiedNumber = {
      otpVerifiedPhoneNumber: codkCartOtpVerifiedPhoneNo,
      isOTPVerified: true,
    };
    await setSessionValue("verifiedNumberData", verifiedNumber);

    emitShopifyVisitorIdentify({
      phone: codkCartOtpVerifiedPhoneNo,
      email: getSessionValue("customer-email"),
      countryCallingCode: opts.countryCallingCode,
    });

    const nextStep = await getCurrentStep();
    setStep(nextStep);
    setIsLoading(false);
    return { success: true, data };
  } catch (error) {
    console.error("Error adding line attribute:", error);
    setError("Network error while adding line attribute", error);
    setIsLoading(false);
    sendErrorToAPI(error, "addLineAttribute.change", "error", {
      operation: "addLineAttribute.change",
      networkError: true,
    });
    return { success: false, error: "Network error. Please try again." };
  }
};

let cacheHitCount = 0;
let shopifyCallCount = 0;
export async function getCart(init = false, retryCount = 0) {
  const MAX_RETRIES = 5;
  const SESSION_KEY = "shopify_cart";

  if (!init) {
    const cachedCart = getSessionValue(SESSION_KEY);
    if (cachedCart) {
      cacheHitCount++;

      try {
        const useOtpStore = (await import("../stores/otpStore")).default;
        const otpStore = useOtpStore.getState();
        if (otpStore && otpStore.setCurrentCartData) {
          const currentCartData = otpStore.currentCartData;
          if (
            !currentCartData ||
            currentCartData.token !== cachedCart.token ||
            currentCartData.items?.length !== cachedCart.items?.length
          ) {
            otpStore.setCurrentCartData(cachedCart);
          }
        }
      } catch (otpStoreError) {}

      return cachedCart;
    }

    return await getCart(true, retryCount);
  }

  try {
    shopifyCallCount++;
    const response = await fetch(`${window.Shopify.routes.root}cart.js`, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      const err = new Error(`Fetch failed with status ${response.status}`);
      throw err;
    }

    const cartData = await response.json();
    const cachedCart = getSessionValue(SESSION_KEY);

    updateCartIfNeeded(cartData, cachedCart);
    setSessionValue(SESSION_KEY, cartData);

    try {
      const useOtpStore = (await import("../stores/otpStore")).default;
      const otpStore = useOtpStore.getState();
      if (otpStore && otpStore.setCurrentCartData) {
        const currentCartData = otpStore.currentCartData;
        if (
          !currentCartData ||
          currentCartData.token !== cartData.token ||
          currentCartData.items?.length !== cartData.items?.length
        ) {
          otpStore.setCurrentCartData(cartData);
        }
      }
    } catch (otpStoreError) {}

    return cartData;
  } catch (error) {
    console.error(
      `getCart(init=${init}) attempt ${retryCount + 1} failed:`,
      error,
    );

    // Report error to API

    if (retryCount + 1 < MAX_RETRIES) {
      return await getCart(true, retryCount + 1);
    } else {
      console.warn("getCart failed after max retries");
      return null;
    }
  }
}

export async function clearCart() {
  return fetch(window.Shopify.routes.root + "cart/clear.js", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
  })
    .then((response) => {
      if (!response.ok) {
        const err = new Error("Error clearing the cart");
        sendErrorToAPI(err, "clearCart", "error", {
          operation: "clearCart",
          status: response.status,
          statusText: response.statusText,
        });
        throw err;
      }
      return response.json();
    })
    .then((data) => {
      syncSessionWithCart();
    })
    .catch((error) => {
      console.error("Error:", error);
      sendErrorToAPI(error, "clearCart", "error", {
        operation: "clearCart",
        networkError: true,
      });
    });
}

export const updateShippingAddresses = async ({
  phone,
  email,
  shippingAddresses,
}) => {
  try {
    const response = await axios.post(
      `https://${process.env.APP_HOST}/order_confirmations/post_shipping_address`,
      {
        phone: phone,
        email: email,
        shippingAdrress: shippingAddresses,
      },
      {
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
    return response.data;
  } catch (error) {
    console.error("Error sending shipping addresses:", error);
    sendErrorToAPI(error, "updateShippingAddresses", "error", {
      operation: "updateShippingAddresses",
      phone: phone ? phone.substring(0, 3) + "****" : null,
      shop: window.Shopify.shop,
    });
    throw error;
  }
};

export const fetchZipDetails = async ({ zip, country_code }) => {
  try {
    const response = await axios.get(
      // `https://${process.env.APP_HOST}/order_confirmations/zip_details`,
      `https://app.codking.tech/order_confirmations/zip_details`,
      {
        params: { zip, country_code },
      },
    );
    return response.data;
  } catch (error) {
    console.error("Error fetching zip details:", error);
    sendErrorToAPI(error, "fetchZipDetails", "error", {
      operation: "fetchZipDetails",
      zip: zip ? zip.substring(0, 2) + "****" : null,
      country_code,
    });
    throw error;
  }
};

export const createCustomerLogin = async ({
  shopifyCustomerId,
  email,
  password,
  phone,
  shopifyDomain,
}) => {
  try {
    const response = await axios.post(
      `https://${process.env.APP_HOST}/order_confirmations/create_customer_login`,
      {
        shopifyCustomerId,
        email,
        password,
        phone,
        shopifyDomain,
      },
      {
        headers: {
          "Content-Type": "application/json",
        },
      },
    );

    if (response.status === 200) {
      debugLog("Customer login created successfully:", response.data);
      return response.data; // Return the response for further use
    } else {
      console.error("Failed to create customer login:", response.data);
      const err = new Error("Error creating customer login.");
      sendErrorToAPI(err, "createCustomerLogin", "error", {
        operation: "createCustomerLogin",
        response: response.data,
      });
      throw err;
    }
  } catch (error) {
    console.error("Error creating customer login:", error);
    sendErrorToAPI(error, "createCustomerLogin", "error", {
      operation: "createCustomerLogin",
      networkError: true,
    });
    throw error; // Propagate the error for the calling code to handle
  }
};

export const callPartialRuleSets = async ({ productId, shopifyDomain }) => {
  try {
    const response = await axios.get(
      `https://${process.env.APP_HOST}/order_confirmations/partial_rule_sets`,
      {
        params: {
          shopifyDomain,
          productId,
        },
        headers: {
          "Content-Type": "application/json",
        },
      },
    );

    if (response.status === 200) {
      return response.data;
    } else {
      console.error("Failed to fetch Partial Rule Sets:", response.data);
      const err = new Error("Error fetching Partial Rule Sets.");
      sendErrorToAPI(err, "callPartialRuleSets", "error", {
        operation: "callPartialRuleSets",
        response: response.data,
      });
      throw err;
    }
  } catch (error) {
    console.error("Error fetching Partial Rule Sets:", error);
    sendErrorToAPI(error, "callPartialRuleSets", "error", {
      operation: "callPartialRuleSets",
      productId,
      shopifyDomain,
    });
    throw error; // Propagate the error for the calling code to handle
  }
};

export const createPartialCart = async (
  shopifyDomain,
  cartRuleId,
  inputCart = "",
) => {
  const url = `https://${process.env.APP_HOST}/order_confirmations/partial_cart`;
  const headers = {
    "Content-Type": "application/json",
  };

  const payload = {
    _codkSessionId: getMachineId(),
    shopifyDomain,
    cartRuleId,
    inputCart,
  };

  try {
    const response = await axios.post(url, payload, { headers });

    const { response: responseData } = response.data;

    return {
      success: true,
      data: responseData,
    };
  } catch (error) {
    console.error("Error in fetchPartialCart API call:", error);
    sendErrorToAPI(error, "createPartialCart", "error", {
      operation: "createPartialCart",
      productId,
      shopifyDomain,
    });
    return {
      success: false,
      error: error.message,
    };
  }
};

export const getAddressCount = async (phone, shopifyDomain) => {
  const url = `https://${process.env.APP_HOST}/order_confirmations/shipping_address_count`;
  const headers = {
    "Content-Type": "application/json",
  };

  const params = {
    phone,
    shopifyDomain,
  };

  try {
    const response = await axios.get(url, { params, headers });

    return {
      success: true,
      data: response.data,
    };
  } catch (error) {
    console.error("Error in getAddressCount API call:", error);
    sendErrorToAPI(error, "getAddressCount", "error", {
      operation: "getAddressCount",
      shop: window.Shopify.shop,
    });
    return {
      success: false,
      error: error.message,
    };
  }
};

export const updateCartDetails = async ({
  device_id,
  shop,
  device_type,
  cart_details,
}) => {
  const url = `https://${process.env.APP_HOST}/order_confirmations/update_cart_details`;
  const headers = {
    "Content-Type": "application/json",
  };
  const cartFilteredData = simplifyCartItems(cart_details);
  const payload = {
    device_id,
    shop,
    device_type,
    cart_details: cartFilteredData,
  };

  try {
    const response = await axios.post(url, payload, { headers });

    const { response: responseData } = response.data;

    return {
      success: true,
      data: responseData,
    };
  } catch (error) {
    console.error("❌ Error in updateCartDetails API call:", error);
    sendErrorToAPI(error, "updateCartDetails", "error", {
      operation: "updateCartDetails",
      shop: window.Shopify.shop,
    });
    return {
      success: false,
      error: error?.response?.data || error.message,
    };
  }
};

export const updateCartIfNeeded = async (cartData, cachedCart) => {
  const session = getSessionValue("verifiedNumberData");
  const cartHash = await hashJsonObject(cartData);
  const cachedHash = await hashJsonObject(cachedCart);
  const settings = getSessionValue("settingSession");

  if (
    (session?.otpVerifiedPhoneNumber || settings?.partialPaymentEnabled) &&
    cartHash != cachedHash &&
    cartData?.items.length > 0
  ) {
    updateCartDetails({
      device_id: getMachineId(),
      shop: window.Shopify.shop,
      device_type: getDeviceType(),
      cart_details: cartData?.items,
    }).catch((err) => {
      console.warn("Non-blocking updateCartDetails failed:", err);
    });
  }
};

// Add this to your otpService.js file

export const postErrorPayload = async (payload) => {
  try {
    const response = await axios.post(
      `https://${process.env.APP_HOST}/order_confirmations/post_error_payload`,
      {
        payload: payload,
      },
      {
        headers: {
          "Content-Type": "application/json",
        },
      },
    );

    if (response.status === 200) {
      return {
        success: true,
        data: response.data,
      };
    } else {
      console.error("❌ postErrorPayload API failed:", response.data);
      return {
        success: false,
        error: response.data,
      };
    }
  } catch (error) {
    console.error("❌ Error in postErrorPayload API call:", error);
    return {
      success: false,
      error: error?.response?.data || error.message,
    };
  }
};

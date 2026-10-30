import axios from "axios";
import { sendErrorToAPI } from "./errorReporter";
import qs from "qs";
import { createLightweightGraphQLClient } from "./lightweightGraphQLClient";
import { executeWithErrorHandling } from "./errorHandler";
import {
  checkShippingConditions,
  debugLog,
  getSessionValue,
} from "../utilities/otpUtils";

// Define the customerCreate mutation
const CUSTOMER_CREATE_MUTATION = `
  mutation customerCreate($input: CustomerCreateInput!) {
    customerCreate(input: $input) {
      customer {
        id
        email
        firstName
        lastName
      }
      customerUserErrors {
        field
        message
      }
    }
  }
`;

// Function to create a new customer
export const createShopifyCustomer = async (input) => {
  return executeWithErrorHandling(
    async () => {
      const settings = getSessionValue("settingSession");
      const shopifyDomain = window.Shopify?.shop;
      const storefrontToken = settings?.storeFrontToken;

      if (!shopifyDomain || !storefrontToken) {
        throw new Error("Shopify configuration not found");
      }

      const client = createLightweightGraphQLClient(
        shopifyDomain,
        storefrontToken
      );
      const { data } = await client.mutateWithCacheClear(
        CUSTOMER_CREATE_MUTATION,
        { input }
      );

      // Check if customer was created successfully
      if (data?.customerCreate?.customer) {
        debugLog(
          "Customer successfully created:",
          data.customerCreate.customer
        );
        return {
          success: true,
          customer: data.customerCreate.customer,
        };
      }

      // Handle user errors returned from the mutation
      if (data?.customerCreate?.customerUserErrors?.length) {
        const errors = data.customerCreate.customerUserErrors.map(
          (err) => err.message
        );
        console.error("User errors:", errors);

        return {
          success: false,
          errors,
        };
      }

      // Unexpected response handling
      console.error("Unexpected response format:", data);
      return {
        success: false,
        errors: ["Unexpected response format from the server."],
      };
    },
    { operation: "createCustomer" }
  );
};

export async function handleCustomeShopifyLogin(email, password) {
  try {
    const csrfToken = document.querySelector(
      'input[name="authenticity_token"]'
    )?.value;

    const response = await axios.post(
      "/account/login",
      qs.stringify({
        form_type: "customer_login",
        utf8: "\u2713",
        authenticity_token: csrfToken,
        "customer[email]": email,
        "customer[password]": password,
        return_url: window.location.href,
      }),
      {
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
      }
    );

    debugLog("Login successful:", response.data);

    return checkShippingConditions();
  } catch (error) {
    console.error("Login failed:", error.response?.data || error.message);
    sendErrorToAPI(error, "handleCustomeShopifyLogin");
    return { success: false, error: "Login failed. Please try again." };
  }
}

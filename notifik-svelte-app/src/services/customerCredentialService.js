import { sendErrorToAPI } from "./errorReporter";
import { createLightweightGraphQLClient } from "./lightweightGraphQLClient";
import { executeWithErrorHandling } from "./errorHandler";
import {
  //   checkShippingConditions,
  getSessionValue,
  getShopDomain,
} from "../utilities/otpUtils";
import { checkShippingConditions } from "../utils/stepUtils";

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
      const shopifyDomain = getShopDomain();
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

        return {
          success: false,
          errors,
        };
      }

      // Unexpected response handling

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
    const tokenInput = document.querySelector(
      'input[name="authenticity_token"]'
    );
    const csrfToken =
      tokenInput && "value" in tokenInput
        ? /** @type {HTMLInputElement} */ (tokenInput).value
        : undefined;

    const params = new URLSearchParams();
    params.append("form_type", "customer_login");
    params.append("utf8", "\u2713");
    if (csrfToken) {
      params.append("authenticity_token", csrfToken);
    }
    params.append("customer[email]", email);
    params.append("customer[password]", password);
    params.append("return_url", window.location.href);

    const response = await fetch("/account/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params,
    });

    if (!response.ok) {
      // Try to get error text if possible
      const errText = await response.text().catch(() => response.statusText);
      throw new Error(`HTTP Error ${response.status}: ${errText}`);
    }

    const responseText = await response.text();

    return checkShippingConditions();
  } catch (error) {

    sendErrorToAPI(error, "handleCustomeShopifyLogin");
    return { success: false, error: "Login failed. Please try again." };
  }
}

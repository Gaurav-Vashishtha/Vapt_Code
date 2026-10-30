import { createLightweightGraphQLClient } from "../services/lightweightGraphQLClient";
import { debugLog, getSessionValue } from "../utilities/otpUtils";

let client = null; // Lightweight GraphQL Client instance

// Function to wait for settings and initialize the Lightweight GraphQL Client
const waitForSettingsAndCreateClient = async (
  retryInterval = 1000,
  maxRetries = 10
) => {
  let retries = 0;

  while (retries < maxRetries) {
    const settings = getSessionValue("settingSession");

    if (settings?.storeFrontToken) {
      initializeClient(settings.storeFrontToken);
      return;
    }

    console.warn(
      `Storefront token is not available yet. Retrying... (${
        retries + 1
      }/${maxRetries})`
    );
    retries++;
    await new Promise((resolve) => setTimeout(resolve, retryInterval));
  }

  throw new Error(
    "Failed to retrieve storefront token after multiple retries."
  );
};

// Function to initialize the Lightweight GraphQL Client
const initializeClient = (storefrontAccessToken) => {
  const shopifyDomain = window.Shopify.shop;

  client = createLightweightGraphQLClient(shopifyDomain, storefrontAccessToken);

  debugLog("Lightweight GraphQL Client initialized successfully.");
};

// Function to get the Lightweight GraphQL Client instance
export const getClient = () => {
  if (!client) {
    throw new Error("Lightweight GraphQL Client has not been initialized yet.");
  }
  return client;
};

// Start waiting for settings and initializing the client
waitForSettingsAndCreateClient().catch((error) => {
  console.error("Error initializing Lightweight GraphQL Client:", error.message);
});

export default getClient;

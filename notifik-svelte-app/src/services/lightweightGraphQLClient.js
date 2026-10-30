/**
 * Lightweight GraphQL Client - Apollo Client Replacement (ported from React app)
 */
import { sendErrorToAPI } from "./errorReporter.js";

class LightweightGraphQLClient {
  constructor(shopifyDomain, storefrontToken) {
    this.endpoint = `https://${shopifyDomain}/api/2024-07/graphql.json`;
    this.headers = {
      "X-Shopify-Storefront-Access-Token": storefrontToken,
      "Content-Type": "application/json",
    };
    this.cache = new Map();
    this.cacheTimeout = 5 * 60 * 1000;
    this.pendingRequests = new Map();
    this.maxRetries = 3;
    this.retryDelay = 1000;
  }

  generateCacheKey(query, variables = {}) {
    return `${query}-${JSON.stringify(variables)}`;
  }

  isCacheValid(cacheEntry) {
    return Date.now() - cacheEntry.timestamp < this.cacheTimeout;
  }

  getCachedData(query, variables = {}) {
    const cacheKey = this.generateCacheKey(query, variables);
    const cached = this.cache.get(cacheKey);
    if (cached && this.isCacheValid(cached)) {
      return cached.data;
    }
    if (cached) {
      this.cache.delete(cacheKey);
    }
    return null;
  }

  setCachedData(query, variables = {}, data) {
    const cacheKey = this.generateCacheKey(query, variables);
    this.cache.set(cacheKey, {
      data,
      timestamp: Date.now(),
    });
  }

  clearCache() {
    this.cache.clear();
  }

  clearCacheForQuery(queryPattern) {
    for (const [key] of this.cache) {
      if (key.includes(queryPattern)) {
        this.cache.delete(key);
      }
    }
  }

  async retryRequest(requestFn, retryCount = 0) {
    try {
      return await requestFn();
    } catch (error) {
      if (retryCount < this.maxRetries && this.isRetryableError(error)) {
        const delay = this.retryDelay * Math.pow(2, retryCount);
        await new Promise((resolve) => setTimeout(resolve, delay));
        return this.retryRequest(requestFn, retryCount + 1);
      }
      throw error;
    }
  }

  isRetryableError(error) {
    if (error.name === "TypeError" && error.message.includes("fetch")) {
      return true;
    }
    if (error.status >= 500 && error.status < 600) {
      return true;
    }
    if (error.status === 429) {
      return true;
    }
    return false;
  }

  handleGraphQLError(response, query, variables) {
    if (response.errors && response.errors.length > 0) {
      const error = new Error("GraphQL Error");
      error.name = "GraphQLError";
      error.errors = response.errors;
      error.query = query;
      error.variables = variables;
      error.userMessage = this.getUserFriendlyMessage(response.errors);
      sendErrorToAPI(error, "LightweightGraphQLClient.handleGraphQLError");
      throw error;
    }
  }

  getUserFriendlyMessage(errors) {
    const messages = errors.map((err) => {
      if (err.message.includes("Storefront access token")) {
        return "Authentication failed. Please check your store configuration.";
      }
      if (err.message.includes("cart")) {
        return "Cart operation failed. Please try again.";
      }
      if (err.message.includes("customer")) {
        return "Customer operation failed. Please check your information.";
      }
      return err.message;
    });
    return messages.join("; ");
  }

  async mutate(query, variables = {}, options = {}) {
    const {
      skipCache = false,
      clearCacheAfter = false,
      cacheTimeout = this.cacheTimeout,
    } = options;

    if (!skipCache) {
      const cachedData = this.getCachedData(query, variables);
      if (cachedData) {
        return { data: cachedData };
      }
    }

    const requestKey = this.generateCacheKey(query, variables);
    if (this.pendingRequests.has(requestKey)) {
      return this.pendingRequests.get(requestKey);
    }

    const requestPromise = this.retryRequest(async () => {
      try {
        const response = await fetch(this.endpoint, {
          method: "POST",
          headers: this.headers,
          body: JSON.stringify({ query, variables }),
        });

        if (!response.ok) {
          const error = new Error(
            `HTTP ${response.status}: ${response.statusText}`
          );
          error.status = response.status;
          error.statusText = response.statusText;
          sendErrorToAPI(error, "LightweightGraphQLClient.fetch");
          throw error;
        }

        const result = await response.json();
        this.handleGraphQLError(result, query, variables);

        if (result.data && !skipCache) {
          this.setCachedData(query, variables, result.data);
        }

        if (clearCacheAfter) {
          this.clearCache();
        }

        return result;
      } catch (error) {
        sendErrorToAPI(error, "LightweightGraphQLClient.mutate");
        throw error;
      }
    });

    this.pendingRequests.set(requestKey, requestPromise);

    try {
      const result = await requestPromise;
      return result;
    } finally {
      this.pendingRequests.delete(requestKey);
    }
  }

  async query(query, variables = {}, options = {}) {
    return this.mutate(query, variables, {
      skipCache: false,
      clearCacheAfter: false,
      ...options,
    });
  }

  async mutateWithCacheClear(query, variables = {}, options = {}) {
    return this.mutate(query, variables, {
      skipCache: true,
      clearCacheAfter: true,
      ...options,
    });
  }

  getCacheStats() {
    return {
      size: this.cache.size,
      keys: Array.from(this.cache.keys()),
      pendingRequests: this.pendingRequests.size,
    };
  }

  setCacheTimeout(timeoutMs) {
    this.cacheTimeout = timeoutMs;
  }

  setRetryConfig(maxRetries, retryDelay) {
    this.maxRetries = maxRetries;
    this.retryDelay = retryDelay;
  }
}

export const createLightweightGraphQLClient = (
  shopifyDomain,
  storefrontToken
) => {
  return new LightweightGraphQLClient(shopifyDomain, storefrontToken);
};

export default LightweightGraphQLClient;

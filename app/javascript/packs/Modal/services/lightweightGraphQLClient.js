/**
 * Lightweight GraphQL Client - Apollo Client Replacement
 * Features: Error handling, caching, retry logic, and request deduplication
 *
 * For comprehensive details on the Apollo Client removal and the implementation
 * of this lightweight client, please see the documentation in:
 * Apollo_Client_Removal_Details.md
 */

import { sendErrorToAPI } from "./errorReporter";

class LightweightGraphQLClient {
  constructor(shopifyDomain, storefrontToken) {
    this.endpoint = `https://${shopifyDomain}/api/2024-07/graphql.json`;
    this.headers = {
      "X-Shopify-Storefront-Access-Token": storefrontToken,
      "Content-Type": "application/json",
    };

    // In-memory cache (similar to Apollo's InMemoryCache)
    this.cache = new Map();
    this.cacheTimeout = 5 * 60 * 1000; // 5 minutes default

    // Request deduplication
    this.pendingRequests = new Map();

    // Retry configuration
    this.maxRetries = 3;
    this.retryDelay = 1000; // 1 second
  }

  /**
   * Generate cache key for a query and variables
   */
  generateCacheKey(query, variables = {}) {
    return `${query}-${JSON.stringify(variables)}`;
  }

  /**
   * Check if cached data is still valid
   */
  isCacheValid(cacheEntry) {
    return Date.now() - cacheEntry.timestamp < this.cacheTimeout;
  }

  /**
   * Get cached data if available and valid
   */
  getCachedData(query, variables = {}) {
    const cacheKey = this.generateCacheKey(query, variables);
    const cached = this.cache.get(cacheKey);

    if (cached && this.isCacheValid(cached)) {
      return cached.data;
    }

    // Remove expired cache entry
    if (cached) {
      this.cache.delete(cacheKey);
    }

    return null;
  }

  /**
   * Store data in cache
   */
  setCachedData(query, variables = {}, data) {
    const cacheKey = this.generateCacheKey(query, variables);
    this.cache.set(cacheKey, {
      data,
      timestamp: Date.now(),
    });
  }

  /**
   * Clear cache (useful for mutations that change data)
   */
  clearCache() {
    this.cache.clear();
  }

  /**
   * Clear specific cache entries (for targeted cache invalidation)
   */
  clearCacheForQuery(queryPattern) {
    for (const [key] of this.cache) {
      if (key.includes(queryPattern)) {
        this.cache.delete(key);
      }
    }
  }

  /**
   * Retry logic with exponential backoff
   */
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

  /**
   * Check if error is retryable
   */
  isRetryableError(error) {
    // Retry on network errors, 5xx server errors, and rate limiting
    if (error.name === "TypeError" && error.message.includes("fetch")) {
      return true; // Network error
    }

    if (error.status >= 500 && error.status < 600) {
      return true; // Server error
    }

    if (error.status === 429) {
      return true; // Rate limiting
    }

    return false;
  }

  /**
   * Enhanced error handling with detailed error information
   */
  handleGraphQLError(response, query, variables) {
    if (response.errors && response.errors.length > 0) {
      const error = new Error("GraphQL Error");
      error.name = "GraphQLError";
      error.errors = response.errors;
      error.query = query;
      error.variables = variables;

      // Add user-friendly error messages
      error.userMessage = this.getUserFriendlyMessage(response.errors);

      sendErrorToAPI(error, "LightweightGraphQLClient.handleGraphQLError");
      throw error;
    }
  }

  /**
   * Get user-friendly error messages
   */
  getUserFriendlyMessage(errors) {
    const messages = errors.map((err) => {
      // Handle common Shopify GraphQL errors
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

  /**
   * Main mutation method with caching, error handling, and retry logic
   */
  async mutate(query, variables = {}, options = {}) {
    const {
      skipCache = false,
      clearCacheAfter = false,
      cacheTimeout = this.cacheTimeout,
    } = options;

    // Check cache first (unless skipCache is true)
    if (!skipCache) {
      const cachedData = this.getCachedData(query, variables);
      if (cachedData) {
        return { data: cachedData };
      }
    }

    // Check for pending requests (deduplication)
    const requestKey = this.generateCacheKey(query, variables);
    if (this.pendingRequests.has(requestKey)) {
      return this.pendingRequests.get(requestKey);
    }

    // Create the request promise
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

        // Handle GraphQL errors
        this.handleGraphQLError(result, query, variables);

        // Cache successful responses
        if (result.data && !skipCache) {
          this.setCachedData(query, variables, result.data);
        }

        // Clear cache if requested (for mutations)
        if (clearCacheAfter) {
          this.clearCache();
        }

        return result;
      } catch (error) {
        sendErrorToAPI(error, "LightweightGraphQLClient.mutate");
        throw error;
      }
    });

    // Store pending request for deduplication
    this.pendingRequests.set(requestKey, requestPromise);

    try {
      const result = await requestPromise;
      return result;
    } finally {
      // Clean up pending request
      this.pendingRequests.delete(requestKey);
    }
  }

  /**
   * Query method (alias for mutate with different default options)
   */
  async query(query, variables = {}, options = {}) {
    return this.mutate(query, variables, {
      skipCache: false,
      clearCacheAfter: false,
      ...options,
    });
  }

  /**
   * Mutation method with cache clearing
   */
  async mutateWithCacheClear(query, variables = {}, options = {}) {
    return this.mutate(query, variables, {
      skipCache: true,
      clearCacheAfter: true,
      ...options,
    });
  }

  /**
   * Get cache statistics (useful for debugging)
   */
  getCacheStats() {
    return {
      size: this.cache.size,
      keys: Array.from(this.cache.keys()),
      pendingRequests: this.pendingRequests.size,
    };
  }

  /**
   * Configure cache timeout
   */
  setCacheTimeout(timeoutMs) {
    this.cacheTimeout = timeoutMs;
  }

  /**
   * Configure retry settings
   */
  setRetryConfig(maxRetries, retryDelay) {
    this.maxRetries = maxRetries;
    this.retryDelay = retryDelay;
  }
}

// Factory function to create client instance
export const createLightweightGraphQLClient = (
  shopifyDomain,
  storefrontToken
) => {
  return new LightweightGraphQLClient(shopifyDomain, storefrontToken);
};

// Export the class for direct usage
export default LightweightGraphQLClient;

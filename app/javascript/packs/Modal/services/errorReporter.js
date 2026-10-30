import { postErrorPayload } from "./otpService";
import { IS_BUY_NOW_BUTTON } from "./domUtils";
import { getMachineId } from "../utilities/otpUtils";

// Error grouping and deduplication
class ErrorGroupingManager {
  constructor() {
    this.errorGroups = new Map();
    this.groupingWindow = 5 * 60 * 1000; // 5 minutes
    this.maxGroupSize = 50; // Max errors per group
  }

  // Generate a unique fingerprint for error grouping
  generateErrorFingerprint(error, operation, shop) {
    const errorMessage = error?.message || String(error);
    const errorName = error?.name || "UnknownError";
    const operationName = operation || "unknown";

    // Create fingerprint based on error characteristics
    const fingerprint = {
      // Core error identity
      errorName,
      operationName,

      // Normalized error message (remove dynamic parts)
      normalizedMessage: this.normalizeErrorMessage(errorMessage),

      // Shop context (prominent for debugging)
      shop: shop || "unknown",

      // Buy Now button context - separate grouping for cart vs buy-now flows
      isBuyNowButton: IS_BUY_NOW_BUTTON,

      // Error type classification
      errorType: this.classifyErrorType(error),

      // Stack trace signature (first few lines)
      stackSignature: this.extractStackSignature(error?.stack),
    };

    return JSON.stringify(fingerprint);
  }

  // Normalize error messages to group similar errors
  normalizeErrorMessage(message) {
    if (!message) return "unknown";

    // Remove dynamic content like IDs, timestamps, URLs
    return message
      .replace(/\d+/g, "[NUMBER]") // Replace numbers
      .replace(/https?:\/\/[^\s]+/g, "[URL]") // Replace URLs
      .replace(/[a-f0-9]{8,}/gi, "[ID]") // Replace IDs
      .replace(/\d{4}-\d{2}-\d{2}/g, "[DATE]") // Replace dates
      .replace(/\d{2}:\d{2}:\d{2}/g, "[TIME]") // Replace times
      .trim();
  }

  // Classify error type for better grouping
  classifyErrorType(error) {
    if (error?.status) {
      if (error.status >= 500) return "server_error";
      if (error.status >= 400) return "client_error";
    }

    if (error?.name) {
      const name = error.name.toLowerCase();
      if (name.includes("network") || name.includes("fetch"))
        return "network_error";
      if (name.includes("timeout")) return "timeout_error";
      if (name.includes("graphql")) return "graphql_error";
      if (name.includes("validation")) return "validation_error";
    }

    return "unknown_error";
  }

  // Extract stack signature for grouping
  extractStackSignature(stack) {
    if (!stack) return "no_stack";

    const lines = stack.split("\n").slice(0, 3); // First 3 lines
    return lines
      .map((line) => line.replace(/\d+/g, "[NUMBER]")) // Normalize line numbers
      .join("|");
  }

  // Check if error should be grouped or reported individually
  shouldGroupError(fingerprint) {
    const now = Date.now();
    const group = this.errorGroups.get(fingerprint);

    if (!group) {
      // New error group
      this.errorGroups.set(fingerprint, {
        firstOccurrence: now,
        lastOccurrence: now,
        count: 1,
        errors: [],
      });
      return false; // Report immediately for new groups
    }

    // Check if within grouping window
    if (now - group.firstOccurrence > this.groupingWindow) {
      // Reset group after window expires
      this.errorGroups.set(fingerprint, {
        firstOccurrence: now,
        lastOccurrence: now,
        count: 1,
        errors: [],
      });
      return false;
    }

    // Update existing group
    group.lastOccurrence = now;
    group.count++;

    // Report if count reaches certain thresholds
    const reportThresholds = [1, 5, 10, 25, 50]; // Report at these counts
    return !reportThresholds.includes(group.count);
  }

  // Get group summary for reporting
  getGroupSummary(fingerprint) {
    const group = this.errorGroups.get(fingerprint);
    if (!group) return null;

    return {
      fingerprint,
      totalCount: group.count,
      firstOccurrence: group.firstOccurrence,
      lastOccurrence: group.lastOccurrence,
      duration: group.lastOccurrence - group.firstOccurrence,
      frequency:
        group.count / ((group.lastOccurrence - group.firstOccurrence) / 1000), // errors per second
    };
  }

  // Clean up old groups
  cleanup() {
    const now = Date.now();
    for (const [fingerprint, group] of this.errorGroups.entries()) {
      if (now - group.lastOccurrence > this.groupingWindow * 2) {
        this.errorGroups.delete(fingerprint);
      }
    }
  }

  // Sanitize parameters to remove sensitive data
  sanitizeParams(params) {
    if (!params || typeof params !== "object") {
      return params;
    }

    const sensitiveKeys = [
      "password",
      "secret",
      "key",
      "api_key",
      "auth",
      "authorization",
      "ssn",
      "credit_card",
      "card_number",
      "cvv",
      "pin",
    ];

    const sanitize = (obj) => {
      if (Array.isArray(obj)) {
        return obj.map((item) => sanitize(item));
      }

      if (obj && typeof obj === "object") {
        const sanitized = {};
        for (const [key, value] of Object.entries(obj)) {
          const lowerKey = key.toLowerCase();
          if (sensitiveKeys.some((sensitive) => lowerKey.includes(sensitive))) {
            sanitized[key] = "[FILTERED]";
          } else if (typeof value === "object") {
            sanitized[key] = sanitize(value);
          } else {
            // Truncate long strings to avoid huge payloads
            sanitized[key] =
              typeof value === "string" && value.length > 500
                ? value.substring(0, 500) + "..."
                : value;
          }
        }
        return sanitized;
      }

      return obj;
    };

    return sanitize(params);
  }
}

// Global error grouping manager
const errorGroupingManager = new ErrorGroupingManager();

// Cleanup old groups every 10 minutes
setInterval(() => {
  errorGroupingManager.cleanup();
}, 10 * 60 * 1000);

// Enhanced error reporter with intelligent grouping
export const sendErrorToAPI = async (
  error,
  operation = "unknown",
  severity = "error",
  params = null,
  fullPayload = null
) => {
  try {
    const now = new Date().toISOString();

    // Enhanced shop information extraction - CRITICAL for debugging
    const shopInfo = {
      shop: (window.Shopify && window.Shopify.shop) || "unknown",
      shopDomain: (window.Shopify && window.Shopify.shop) || "unknown",
      shopId: (window.Shopify && window.Shopify.shopId) || null,
      currency: (window.Shopify && window.Shopify.currency) || null,
      locale: (window.Shopify && window.Shopify.locale) || null,
      country: (window.Shopify && window.Shopify.country) || null,
      // Additional shop context
      themeId:
        window.Shopify && window.Shopify.theme ? window.Shopify.theme.id : null,
      themeName:
        window.Shopify && window.Shopify.theme
          ? window.Shopify.theme.name
          : null,
      // Check if we're in Shopify admin or storefront
      context: window.location.href.includes("/admin") ? "admin" : "storefront",
    };

    const pageUrl =
      typeof window !== "undefined" ? window.location.href : "unknown";

    // Generate error fingerprint for grouping (using shop domain)
    const fingerprint = errorGroupingManager.generateErrorFingerprint(
      error,
      operation,
      shopInfo.shop
    );

    // Check if this error should be grouped or reported
    const shouldGroup = errorGroupingManager.shouldGroupError(fingerprint);

    if (shouldGroup) {
      // Skip reporting this individual error (it's part of a group)
      const buyNowContext = IS_BUY_NOW_BUTTON ? " [BUY-NOW]" : " [CART]";
      console.log(
        `🔄 Error grouped for shop "${
          shopInfo.shop
        }"${buyNowContext} (${fingerprint.substring(
          0,
          50
        )}...) - skipping individual report`
      );
      return;
    }

    // Get group summary if this is a threshold report
    const groupSummary = errorGroupingManager.getGroupSummary(fingerprint);

    // Extract meaningful error information
    const errorInfo = {
      message: error?.message || String(error),
      name: error?.name || "UnknownError",
      status: error?.status || null,
      statusText: error?.statusText || null,

      // Add grouping information
      grouping: {
        fingerprint: fingerprint.substring(0, 100) + "...", // Truncated for readability
        isGrouped: groupSummary ? groupSummary.totalCount > 1 : false,
        groupSummary: groupSummary
          ? {
              totalCount: groupSummary.totalCount,
              duration: groupSummary.duration,
              frequency: groupSummary.frequency.toFixed(2),
            }
          : null,
      },
    };

    // Add GraphQL specific info if available
    if (error?.errors && Array.isArray(error.errors)) {
      errorInfo.graphqlErrors = error.errors.map((err) => ({
        message: err.message,
        locations: err.locations,
        path: err.path,
      }));
    }

    // Add user-friendly message if available
    if (error?.userMessage) {
      errorInfo.userMessage = error.userMessage;
    }

    // Add query info for GraphQL errors (truncated for privacy)
    if (error?.query) {
      errorInfo.queryHash = error.query.substring(0, 100) + "...";
    }

    // Add variables info (sanitized)
    if (error?.variables) {
      errorInfo.variablesKeys = Object.keys(error.variables);
    }

    // Add payload information if available (request/response data)
    if (error?.payload) {
      errorInfo.payload = errorGroupingManager.sanitizeParams(error.payload);
    }

    // Add OTP context information if available
    if (error?.otpContext) {
      errorInfo.otpContext = errorGroupingManager.sanitizeParams(
        error.otpContext
      );
    }

    // Add full payload if provided
    if (fullPayload) {
      errorInfo.fullPayload = errorGroupingManager.sanitizeParams(fullPayload);
    }

    // Build focused context for debugging
    const context = {
      // Essential browser info
      userAgent:
        typeof navigator !== "undefined" ? navigator.userAgent : "unknown",
      platform:
        typeof navigator !== "undefined" ? navigator.platform : "unknown",
      language:
        typeof navigator !== "undefined" ? navigator.language : "unknown",
      onLine: typeof navigator !== "undefined" ? navigator.onLine : undefined,

      // Error stack (truncated to avoid huge payloads)
      stack: error?.stack
        ? error.stack.split("\n").slice(0, 10).join("\n")
        : null,

      // Modal state info
      modalState:
        typeof window !== "undefined" ? window.codkModalState : "unknown",

      // Cart info (if available) - removed cartToken for privacy

      // Buy Now button context - CRITICAL for debugging cart vs buy-now flows
      isBuyNowButton: IS_BUY_NOW_BUTTON,

      // Session ID for tracking user sessions
      codkSessionId: getMachineId(),

      // Function parameters that caused the error (sanitized)
      params: params ? errorGroupingManager.sanitizeParams(params) : null,
    };

    // Determine tracking ID based on grouping
    const trackingId =
      groupSummary && groupSummary.totalCount > 1
        ? "CODKING_CLIENT_ERROR_GROUPED"
        : "CODKING_CLIENT_ERROR";

    const payload = JSON.stringify({
      trackingId,
      severity,
      timestamp: now,
      operation,

      // Prominent shop information for easy identification
      shop: shopInfo.shop,
      shopInfo: {
        domain: shopInfo.shopDomain,
        id: shopInfo.shopId,
        currency: shopInfo.currency,
        locale: shopInfo.locale,
        country: shopInfo.country,
      },

      url: pageUrl,
      error: errorInfo,
      context,
    });

    await postErrorPayload(payload);

    // Log grouping info for debugging
    const buyNowContext = context.isBuyNowButton ? " [BUY-NOW]" : " [CART]";
    if (groupSummary && groupSummary.totalCount > 1) {
      console.log(
        `📊 Error group reported for shop "${shopInfo.shop}"${buyNowContext}: ${
          groupSummary.totalCount
        } occurrences in ${(groupSummary.duration / 1000).toFixed(1)}s`
      );
    } else {
      console.log(
        `🚨 Error reported for shop "${shopInfo.shop}"${buyNowContext}: ${errorInfo.message}`
      );
    }
  } catch (reportErr) {
    // Do not throw from reporter
    // eslint-disable-next-line no-console
    console.warn("Failed to report error:", reportErr);
  }
};

// Utility function to get error group statistics
export const getErrorGroupStats = () => {
  const stats = {
    totalGroups: errorGroupingManager.errorGroups.size,
    groups: [],
  };

  for (const [
    fingerprint,
    group,
  ] of errorGroupingManager.errorGroups.entries()) {
    stats.groups.push({
      fingerprint: fingerprint.substring(0, 100) + "...",
      count: group.count,
      duration: group.lastOccurrence - group.firstOccurrence,
      frequency:
        group.count / ((group.lastOccurrence - group.firstOccurrence) / 1000),
    });
  }

  return stats;
};

// Utility function to clear error groups (useful for testing)
export const clearErrorGroups = () => {
  errorGroupingManager.errorGroups.clear();
  console.log("🧹 Error groups cleared");
};

// Utility function to get shop-specific error statistics
export const getShopErrorStats = () => {
  const shopStats = new Map();

  for (const [
    fingerprint,
    group,
  ] of errorGroupingManager.errorGroups.entries()) {
    try {
      const parsed = JSON.parse(fingerprint);
      const shop = parsed.shop || "unknown";

      if (!shopStats.has(shop)) {
        shopStats.set(shop, {
          shop,
          totalErrors: 0,
          errorGroups: 0,
          mostCommonError: null,
          maxFrequency: 0,
        });
      }

      const stats = shopStats.get(shop);
      stats.totalErrors += group.count;
      stats.errorGroups += 1;

      const frequency =
        group.count / ((group.lastOccurrence - group.firstOccurrence) / 1000);
      if (frequency > stats.maxFrequency) {
        stats.maxFrequency = frequency;
        stats.mostCommonError = parsed.normalizedMessage;
      }
    } catch (e) {
      // Skip invalid fingerprints
    }
  }

  return Array.from(shopStats.values()).sort(
    (a, b) => b.totalErrors - a.totalErrors
  );
};

// Utility function to log current shop context (useful for debugging)
export const logCurrentShopContext = () => {
  const shopInfo = {
    shop: (window.Shopify && window.Shopify.shop) || "unknown",
    shopId: (window.Shopify && window.Shopify.shopId) || null,
    currency: (window.Shopify && window.Shopify.currency) || null,
    locale: (window.Shopify && window.Shopify.locale) || null,
    country: (window.Shopify && window.Shopify.country) || null,
    themeId:
      window.Shopify && window.Shopify.theme ? window.Shopify.theme.id : null,
    context: window.location.href.includes("/admin") ? "admin" : "storefront",
  };

  console.log("🏪 Current Shop Context:", shopInfo);
  return shopInfo;
};

// Utility function to get current shop information
export const getCurrentShopInfo = () => {
  return {
    shop: (window.Shopify && window.Shopify.shop) || "unknown",
    shopId: (window.Shopify && window.Shopify.shopId) || null,
    currency: (window.Shopify && window.Shopify.currency) || null,
    locale: (window.Shopify && window.Shopify.locale) || null,
    country: (window.Shopify && window.Shopify.country) || null,
    url: typeof window !== "undefined" ? window.location.href : "unknown",
  };
};

// Utility function to test error reporting with current shop info
export const testErrorReporting = (
  testMessage = "Test error from error reporter"
) => {
  const shopInfo = getCurrentShopInfo();
  console.log(`🧪 Testing error reporting for shop: ${shopInfo.shop}`);

  const testError = new Error(testMessage);
  testError.name = "TestError";

  return sendErrorToAPI(testError, "testErrorReporting", "error");
};

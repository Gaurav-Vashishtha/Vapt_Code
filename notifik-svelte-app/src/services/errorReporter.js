/**
 * Error Reporting Service
 *
 * Comprehensive error reporting with intelligent grouping and deduplication
 * Matches React app's errorReporter.js functionality
 */

import { getMachineId } from "../utils/helpers.js";
import { getRouteUrl } from "./api.js";

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
      errorName,
      operationName,
      normalizedMessage: this.normalizeErrorMessage(errorMessage),
      shop: shop || "unknown",
      errorType: this.classifyErrorType(error),
      stackSignature: this.extractStackSignature(error?.stack),
    };

    return JSON.stringify(fingerprint);
  }

  // Normalize error messages to group similar errors
  normalizeErrorMessage(message) {
    if (!message) return "unknown";

    return message
      .replace(/\d+/g, "[NUMBER]")
      .replace(/https?:\/\/[^\s]+/g, "[URL]")
      .replace(/[a-f0-9]{8,}/gi, "[ID]")
      .replace(/\d{4}-\d{2}-\d{2}/g, "[DATE]")
      .replace(/\d{2}:\d{2}:\d{2}/g, "[TIME]")
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

    const lines = stack.split("\n").slice(0, 3);
    return lines.map((line) => line.replace(/\d+/g, "[NUMBER]")).join("|");
  }

  // Check if error should be grouped or reported individually
  shouldGroupError(fingerprint) {
    const now = Date.now();
    const group = this.errorGroups.get(fingerprint);

    if (!group) {
      this.errorGroups.set(fingerprint, {
        firstOccurrence: now,
        lastOccurrence: now,
        count: 1,
        errors: [],
      });
      return false;
    }

    if (now - group.firstOccurrence > this.groupingWindow) {
      this.errorGroups.set(fingerprint, {
        firstOccurrence: now,
        lastOccurrence: now,
        count: 1,
        errors: [],
      });
      return false;
    }

    group.lastOccurrence = now;
    group.count++;

    const reportThresholds = [1, 5, 10, 25, 50];
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
        group.count / ((group.lastOccurrence - group.firstOccurrence) / 1000),
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
if (typeof window !== "undefined") {
  setInterval(() => {
    errorGroupingManager.cleanup();
  }, 10 * 60 * 1000);
}

/**
 * Enhanced error reporter with intelligent grouping
 * @param {Error} error - The error object
 * @param {string} operation - Operation name where error occurred
 * @param {string} severity - Error severity (error, warning, info)
 * @param {Object} params - Additional context parameters
 */
export const sendErrorToAPI = async (
  error,
  operation = "unknown",
  severity = "error",
  params = null
) => {
  try {
    const now = new Date().toISOString();

    // Get shop information
    const shopInfo = {
      shop:
        (typeof window !== "undefined" && window.parent?.Shopify?.shop) ||
        (typeof window !== "undefined" && window.Shopify?.shop) ||
        "unknown",
      shopDomain:
        (typeof window !== "undefined" && window.parent?.Shopify?.shop) ||
        (typeof window !== "undefined" && window.Shopify?.shop) ||
        "unknown",
      currency:
        (typeof window !== "undefined" && window.parent?.Shopify?.currency) ||
        (typeof window !== "undefined" && window.Shopify?.currency) ||
        null,
    };

    const pageUrl =
      typeof window !== "undefined" ? window.location.href : "unknown";

    // Generate error fingerprint for grouping
    const fingerprint = errorGroupingManager.generateErrorFingerprint(
      error,
      operation,
      shopInfo.shop
    );

    // Check if this error should be grouped or reported
    const shouldGroup = errorGroupingManager.shouldGroupError(fingerprint);

    if (shouldGroup) {
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
      grouping: {
        fingerprint: fingerprint.substring(0, 100) + "...",
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

    // Build context
    const context = {
      userAgent:
        typeof navigator !== "undefined" ? navigator.userAgent : "unknown",
      platform:
        typeof navigator !== "undefined" ? navigator.platform : "unknown",
      language:
        typeof navigator !== "undefined" ? navigator.language : "unknown",
      onLine: typeof navigator !== "undefined" ? navigator.onLine : undefined,
      stack: error?.stack
        ? error.stack.split("\n").slice(0, 10).join("\n")
        : null,
      codkSessionId: getMachineId(),
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
      shop: shopInfo.shop,
      shopInfo: {
        domain: shopInfo.shopDomain,
        currency: shopInfo.currency,
      },
      url: pageUrl,
      error: errorInfo,
      context,
    });

    // Send error to backend
    await postErrorPayload(payload);

    // Log grouping info for debugging
    if (groupSummary && groupSummary.totalCount > 1) {
    } else {
    }
  } catch (reportErr) {

  }
};

/**
 * Post error payload to backend
 */
const postErrorPayload = async (payload) => {
  try {
    const routeUrl = getRouteUrl();
    const response = await fetch(`${routeUrl}/script/post_error`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: payload,
    });

    if (!response.ok) {

    }
  } catch (error) {

  }
};


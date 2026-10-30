/**
 * API Logger Utility
 * 
 * Centralized logging for all API calls (Shopify, Backend, GraphQL)
 * Tracks: endpoint, method, screen context, timing, request/response data
 */

const API_LOG_PREFIX = "[API LOG]";
const LOG_STORAGE_KEY = "codk_api_logs";

// Maximum number of logs to keep in memory
const MAX_LOGS = 500;

// In-memory log storage
let apiLogs = [];

// Load logs from sessionStorage on initialization
try {
  const stored = sessionStorage.getItem(LOG_STORAGE_KEY);
  if (stored) {
    apiLogs = JSON.parse(stored);
    // Keep only last MAX_LOGS entries
    if (apiLogs.length > MAX_LOGS) {
      apiLogs = apiLogs.slice(-MAX_LOGS);
    }
  }
} catch (_e) {}

/**
 * Get current screen context
 */
function getCurrentScreen() {
  try {
    // Try to get from buttonManager (appStore)
    if (typeof window !== "undefined" && window.appStore) {
      const store = window.appStore;
      let currentScreen = null;
      const unsubscribe = store.subscribe((state) => {
        currentScreen = state.currentScreen;
      });
      unsubscribe();
      if (currentScreen) return currentScreen;
    }
    
    // Try to get from sessionStorage
    const screen = sessionStorage.getItem("codk_current_screen");
    if (screen) return screen;
    
    return "unknown";
  } catch (e) {
    return "unknown";
  }
}

/**
 * Get modal state
 */
function getModalState() {
  try {
    if (typeof window !== "undefined") {
      const win = /** @type {Window & typeof globalThis & { codkModalState?: string }} */ (window);
      return win.codkModalState || "closed";
    }
    return "closed";
  } catch (e) {
    return "closed";
  }
}

/**
 * Sanitize sensitive data from logs
 */
function sanitizeData(data) {
  if (!data || typeof data !== "object") return data;
  
  const sensitiveKeys = [
    "phone", "phoneNumber", "phone_number",
    "email", "customerEmail", "customer_email",
    "otp", "otpCode", "otp_code",
    "ip_address", "ipAddress",
    "device_id", "deviceId",
    "token", "access_token", "session_id",
    "password", "password_hash"
  ];
  
  const sanitized = { ...data };
  
  for (const key in sanitized) {
    const lowerKey = key.toLowerCase();
    if (sensitiveKeys.some(sk => lowerKey.includes(sk.toLowerCase()))) {
      if (typeof sanitized[key] === "string" && sanitized[key].length > 0) {
        const value = sanitized[key];
        if (value.length > 4) {
          sanitized[key] = value.substring(0, 2) + "****" + value.substring(value.length - 2);
        } else {
          sanitized[key] = "****";
        }
      } else {
        sanitized[key] = "****";
      }
    }
  }
  
  return sanitized;
}

/**
 * Log an API call
 */
export function logApiCall({
  type, // 'shopify' | 'backend' | 'graphql' | 'external'
  endpoint,
  method = "GET",
  screen = null,
  phase = null, // 'before_modal' | 'modal_open' | 'screen_transition' | 'user_action'
  requestData = null,
  responseData = null,
  status = null,
  statusText = null,
  duration = null,
  error = null,
  metadata = {}
}) {
  const timestamp = new Date().toISOString();
  const currentScreen = screen || getCurrentScreen();
  const modalState = getModalState();
  
  const logEntry = {
    id: `${timestamp}-${Math.random().toString(36).substr(2, 9)}`,
    timestamp,
    type,
    endpoint,
    method,
    screen: currentScreen,
    modalState,
    phase: phase || (modalState === "open" ? "modal_open" : "before_modal"),
    requestData: requestData ? sanitizeData(requestData) : null,
    responseData: responseData ? sanitizeData(responseData) : null,
    status,
    statusText,
    duration,
    error: error ? error.message || String(error) : null,
    metadata
  };
  
  // Add to in-memory logs
  apiLogs.push(logEntry);
  
  // Keep only last MAX_LOGS entries
  if (apiLogs.length > MAX_LOGS) {
    apiLogs = apiLogs.slice(-MAX_LOGS);
  }
  
  // Save to sessionStorage (async, non-blocking)
  try {
    sessionStorage.setItem(LOG_STORAGE_KEY, JSON.stringify(apiLogs));
  } catch (e) {
    // Ignore storage errors (might be full)
  }
  
  // Console log with formatted output
  const logMessage = [
    API_LOG_PREFIX,
    `[${type.toUpperCase()}]`,
    method,
    endpoint,
    `[Screen: ${currentScreen}]`,
    `[Phase: ${logEntry.phase}]`,
    duration ? `[${duration}ms]` : "",
    status ? `[Status: ${status}]` : "",
    error ? `[ERROR: ${error}]` : ""
  ].filter(Boolean).join(" ");
  
  
  return logEntry;
}

/**
 * Get all API logs
 */
export function getApiLogs() {
  return [...apiLogs];
}

/**
 * Get API logs filtered by criteria
 */
export function getApiLogsFiltered({
  type = null,
  screen = null,
  phase = null,
  endpoint = null,
  since = null
} = {}) {
  return apiLogs.filter(log => {
    if (type && log.type !== type) return false;
    if (screen && log.screen !== screen) return false;
    if (phase && log.phase !== phase) return false;
    if (endpoint && !log.endpoint.includes(endpoint)) return false;
    if (since) {
      const logTime = new Date(log.timestamp).getTime();
      const sinceTime = new Date(since).getTime();
      if (logTime < sinceTime) return false;
    }
    return true;
  });
}

/**
 * Get API call summary
 */
export function getApiCallSummary() {
  const summary = {
    total: apiLogs.length,
    byType: {},
    byScreen: {},
    byPhase: {},
    byEndpoint: {},
    errors: [],
    totalDuration: 0,
    averageDuration: 0
  };
  
  apiLogs.forEach(log => {
    // Count by type
    summary.byType[log.type] = (summary.byType[log.type] || 0) + 1;
    
    // Count by screen
    summary.byScreen[log.screen] = (summary.byScreen[log.screen] || 0) + 1;
    
    // Count by phase
    summary.byPhase[log.phase] = (summary.byPhase[log.phase] || 0) + 1;
    
    // Count by endpoint
    summary.byEndpoint[log.endpoint] = (summary.byEndpoint[log.endpoint] || 0) + 1;
    
    // Track errors
    if (log.error || (log.status && log.status >= 400)) {
      summary.errors.push({
        endpoint: log.endpoint,
        error: log.error,
        status: log.status,
        timestamp: log.timestamp
      });
    }
    
    // Sum duration
    if (log.duration) {
      summary.totalDuration += log.duration;
    }
  });
  
  // Calculate average duration
  const logsWithDuration = apiLogs.filter(log => log.duration);
  if (logsWithDuration.length > 0) {
    summary.averageDuration = summary.totalDuration / logsWithDuration.length;
  }
  
  return summary;
}

/**
 * Clear all logs
 */
export function clearApiLogs() {
  apiLogs = [];
  try {
    sessionStorage.removeItem(LOG_STORAGE_KEY);
  } catch (e) {
    // Ignore
  }
}

/**
 * Export logs as JSON
 */
export function exportApiLogs() {
  return JSON.stringify({
    exportedAt: new Date().toISOString(),
    summary: getApiCallSummary(),
    logs: apiLogs
  }, null, 2);
}

/**
 * Log Shopify API call wrapper
 */
export function logShopifyApiCall(endpoint, method, requestData, responseData, duration, error, metadata = {}) {
  return logApiCall({
    type: "shopify",
    endpoint,
    method,
    requestData,
    responseData,
    duration,
    error,
    status: responseData?.status || (error ? 500 : 200),
    metadata: {
      ...metadata,
      isShopifyApi: true
    }
  });
}

/**
 * Log Backend API call wrapper
 */
export function logBackendApiCall(endpoint, method, requestData, responseData, duration, error, metadata = {}) {
  return logApiCall({
    type: "backend",
    endpoint,
    method,
    requestData,
    responseData,
    duration,
    error,
    status: responseData?.status || (error ? 500 : 200),
    metadata: {
      ...metadata,
      isBackendApi: true
    }
  });
}

/**
 * Log GraphQL API call wrapper
 */
export function logGraphQLApiCall(endpoint, mutation, variables, responseData, duration, error, metadata = {}) {
  return logApiCall({
    type: "graphql",
    endpoint,
    method: "POST",
    requestData: {
      mutation,
      variables: sanitizeData(variables)
    },
    responseData,
    duration,
    error,
    status: responseData?.errors ? 400 : 200,
    metadata: {
      ...metadata,
      isGraphQL: true,
      mutation
    }
  });
}

/**
 * Log External API call wrapper (IP services, etc.)
 */
export function logExternalApiCall(endpoint, method, requestData, responseData, duration, error, metadata = {}) {
  return logApiCall({
    type: "external",
    endpoint,
    method,
    requestData,
    responseData,
    duration,
    error,
    status: responseData?.status || (error ? 500 : 200),
    metadata: {
      ...metadata,
      isExternalApi: true
    }
  });
}

// Expose to window for debugging
if (typeof window !== "undefined") {
  const win = /** @type {Window & typeof globalThis & { codkApiLogger?: typeof import('./apiLogger.js') }} */ (window);
  win.codkApiLogger = {
    getLogs: getApiLogs,
    getFilteredLogs: getApiLogsFiltered,
    getSummary: getApiCallSummary,
    clearLogs: clearApiLogs,
    exportLogs: exportApiLogs
  };
  
}


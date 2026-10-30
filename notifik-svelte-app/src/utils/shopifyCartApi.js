import { logShopifyApiCall } from "./apiLogger.js";
import { getShopifyRootPath } from "./helpers.js";

const RETRYABLE_STATUS = new Set([409, 423, 429]);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Re-export for backward compatibility
export { getShopifyRootPath };

export const getShopifyFetch = () => {
  if (
    typeof window !== "undefined" &&
    window.parent &&
    window.parent !== window &&
    typeof window.parent.fetch === "function"
  ) {
    return window.parent.fetch.bind(window.parent);
  }

  return fetch;
};

const normalizeRoot = (root) => {
  if (!root || root === "/") return "";
  return root.endsWith("/") ? root.slice(0, -1) : root;
};

const buildCartUrl = (pathOrUrl, root) => {
  if (!pathOrUrl) return root || "/";

  let url;
  if (/^https?:\/\//i.test(pathOrUrl)) {
    url = pathOrUrl;
  } else {
    const normalizedRoot = normalizeRoot(root);
    if (normalizedRoot && pathOrUrl.startsWith(normalizedRoot)) {
      url = pathOrUrl;
    } else if (pathOrUrl.startsWith("/")) {
      url = `${normalizedRoot}${pathOrUrl}`;
    } else {
      url = `${normalizedRoot}/${pathOrUrl}`;
    }
  }

  // Add app=codk query parameter to all cart service calls
  // Only add if it's a cart-related endpoint
  if (/\/cart(\.js|\/)/i.test(url)) {
    const separator = url.includes("?") ? "&" : "?";
    return `${url}${separator}app=codk`;
  }

  return url;
};

let cartQueue = Promise.resolve();

const enqueueCartRequest = (task) => {
  const run = cartQueue.then(() => task());
  cartQueue = run.catch(() => {});
  return run;
};

const shouldRetry = (status) => RETRYABLE_STATUS.has(status);

/**
 * Perform a Shopify cart mutation with queuing + retry semantics.
 * Ensures we never fire overlapping cart mutations that can trigger 409 conflicts.
 */
export const cartFetch = async (
  pathOrUrl,
  options = {},
  { retries = 3, retryDelay = 250 } = {}
) => {
  const fetchFn = getShopifyFetch();
  const root = getShopifyRootPath();
  const url = buildCartUrl(pathOrUrl, root);
  const method = options.method || "GET";
  const startTime = performance.now();

  return enqueueCartRequest(async () => {
    let attempt = 0;
    let lastError = null;
    let lastResponse = null;

    while (true) {
      try {
        const response = await fetchFn(url, options);
        lastResponse = response;

        if (!shouldRetry(response.status) || attempt >= retries) {
          const duration = performance.now() - startTime;

          // Try to parse response body for logging (non-blocking)
          let responseData = null;
          try {
            const clonedResponse = response.clone();
            const text = await clonedResponse.text();
            try {
              responseData = JSON.parse(text);
            } catch {
              responseData = { raw: text.substring(0, 200) }; // First 200 chars
            }
          } catch {
            // Ignore parsing errors
          }

          // Log the API call
          logShopifyApiCall(
            url,
            method,
            options.body
              ? typeof options.body === "string"
                ? JSON.parse(options.body)
                : options.body
              : null,
            responseData,
            Math.round(duration),
            response.ok
              ? null
              : new Error(`HTTP ${response.status} ${response.statusText}`),
            {
              status: response.status,
              statusText: response.statusText,
              retries: attempt,
              pathOrUrl,
            }
          );

          return response;
        }

        const delay = retryDelay * (attempt + 1);

        await sleep(delay);
        attempt += 1;
      } catch (error) {
        lastError = error;
        const duration = performance.now() - startTime;

        // Log error
        logShopifyApiCall(
          url,
          method,
          options.body
            ? typeof options.body === "string"
              ? JSON.parse(options.body)
              : options.body
            : null,
          null,
          Math.round(duration),
          error,
          {
            retries: attempt,
            pathOrUrl,
          }
        );

        throw error;
      }
    }
  });
};

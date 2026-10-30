// App Bridge's shopify.idToken() can hang without settling (seen as an endless
// loader inside mobile WebViews). Race it against a timeout so callers always
// get either a token or an error they can handle.
export const ID_TOKEN_TIMEOUT_MS = 5000;

export const getIdToken = (timeoutMs = ID_TOKEN_TIMEOUT_MS) => {
  if (typeof window === "undefined" || !window.shopify || typeof window.shopify.idToken !== "function") {
    return Promise.reject(new Error("App Bridge not available"));
  }
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`shopify.idToken() timed out after ${timeoutMs}ms`)), timeoutMs);
  });
  return Promise.race([window.shopify.idToken(), timeout]).finally(() => clearTimeout(timer));
};

/** Session key: Custom Setup (or others) stash rule JSON before `/features/partial-payment/edit`. */
export const PARTIAL_RULE_EDIT_PAYLOAD_KEY = "cod_king_partial_edit_payload";

const RETURN_PATH_KEY = "cod_king_partial_nav_return_path";

/** Remember where to return after add/edit (e.g. `/custom_setup`). */
export function setPartialPaymentReturnPath(path) {
  if (typeof window === "undefined" || !path || typeof path !== "string") return;
  if (!path.startsWith("/")) return;
  try {
    sessionStorage.setItem(RETURN_PATH_KEY, path);
  } catch (_) {}
}

/** Read and clear return path for partial-payment add/edit flow. */
export function consumePartialPaymentReturnPath() {
  if (typeof window === "undefined") return null;
  try {
    const p = sessionStorage.getItem(RETURN_PATH_KEY);
    sessionStorage.removeItem(RETURN_PATH_KEY);
    if (p && p.startsWith("/")) return p;
  } catch (_) {}
  return null;
}

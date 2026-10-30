import { assignWithFullReload } from "../../utils/navigate";

export const CUSTOM_SETUP_PENDING_KEY = "cod_king_pending_custom_setup";

export function markCustomSetupPendingAfterBilling() {
  try {
    sessionStorage.setItem(CUSTOM_SETUP_PENDING_KEY, "1");
  } catch (_) {}
}

export function clearCustomSetupPending() {
  try {
    sessionStorage.removeItem(CUSTOM_SETUP_PENDING_KEY);
  } catch (_) {}
}

/**
 * After merchant approves charge in Shopify, they return with charge_id.
 * If onboarding sent them to billing with a pending flag, land on custom setup once.
 *
 * Note: the `billing_approved` funnel event is recorded server-side at charge
 * activation (see ChargeActivatedJob), gated on an onboarding `billing_started`
 * event. That is authoritative and survives device/tab/session changes, so we no
 * longer emit it from the client here.
 */
export function redirectIfPendingCustomSetupAndSubscribed(shop) {
  try {
    if (sessionStorage.getItem(CUSTOM_SETUP_PENDING_KEY) !== "1") return;
    const chargeId = shop?.chargeId ?? shop?.charge_id;
    const hasCharge =
      chargeId != null && String(chargeId).trim() !== "";
    if (!hasCharge) return;
    if (window.location.pathname === "/custom_setup") return;
    try {
      sessionStorage.removeItem(CUSTOM_SETUP_PENDING_KEY);
    } catch (_) {}
    assignWithFullReload("/custom_setup");
  } catch (_) {}
}

export function shouldRedirectToCustomSetupAfterUpgrade(confirmationUrl) {
  try {
    if (sessionStorage.getItem(CUSTOM_SETUP_PENDING_KEY) !== "1")
      return false;
    return !confirmationUrl;
  } catch (_) {
    return false;
  }
}

export function consumePendingAndGoCustomSetup() {
  try {
    sessionStorage.removeItem(CUSTOM_SETUP_PENDING_KEY);
  } catch (_) {}
  assignWithFullReload("/custom_setup");
}

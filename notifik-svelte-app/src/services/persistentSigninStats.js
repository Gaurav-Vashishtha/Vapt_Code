import { getRouteUrl } from "./api.js";
import { getSessionValue, setSessionValue } from "./sessionService.js";

const CHECK_KEY = "persistent_hit_check";

export async function recordPersistentSigninStat() {
  return;
  try {
    if (getSessionValue(CHECK_KEY)) return;
    setSessionValue(CHECK_KEY, true);

    await fetch(`${getRouteUrl()}/order_confirmations/persistent_signin_stat`, {
      method: "POST",
      headers: { Accept: "application/json" },
      credentials: "include",
      keepalive: true,
    });
  } catch {
  }
}

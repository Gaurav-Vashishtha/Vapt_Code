import { mount } from "svelte";
import "./app.css";
import App from "./App.svelte";
import { actions, appStore } from "./stores/buttonManager.js";
import otpStore from "./stores/otpStore.js";
import { mapSettingsToCamel } from "./utils/settingsMapper.js";
import {
  // resetCartRevertIsComplete,
  resetOrderSummaryComplete,
  setSessionValue,
  getSessionValue,
} from "./services/sessionService.js";
import { restorePersistentSigninIfEnabled, isPersistentSigninEnabled, loadPersistentData } from "./services/persistentSigninStorage.js";
import { attemptSsoAutoLogin } from "./services/otpService.js";
import { cartRevertService } from "./services/cartRevertService";
import { clearRedirectInProgress, getLocalValue, isRedirectInProgress } from "./utils/helpers.js";
import { loadToastify } from "./utils/toastLoader.js";

/**
 * @typedef {Window & { codkingRouteUrl?: string; codkingSvelteReady?: boolean; codkSvelteAppMounted?: boolean }} CodKingWindow
 */
const parentWindow = /** @type {CodKingWindow} */ (window.parent || window);

// ⚡ GUARD: Prevent duplicate mounting if script module executes multiple times
// This can happen if iframe document is reloaded or script is loaded twice
let app = null;
console.log("[main.js] Notifik bootstrap");

// Force fresh SSO validation on F5/Cmd-R so logouts on other devices and token
try {
  const navEntry = /** @type {PerformanceNavigationTiming | undefined} */ (
    (parentWindow.performance || performance).getEntriesByType("navigation")[0]
  );
  if (navEntry?.type === "reload") {
    [parentWindow.sessionStorage, window.sessionStorage].forEach((store) => {
      try {
        store?.removeItem("ssoAutoLoginAttempted");
        store?.removeItem("ssoValidatedToken");
      } catch (_e) {}
    });
    console.log("[SSO] Page reload detected — cleared per-tab SSO guards");
  }
} catch (_e) {}

if (window.codkSvelteAppMounted || parentWindow.codkSvelteAppMounted) {
  // Always reset flags even if we skip mounting to avoid stale state
  try {
    // resetCartRevertIsComplete();
    resetOrderSummaryComplete();
  } catch (e) {}
  // Exit early - don't mount again, but still export null app
} else {
  // Mark as mounted immediately to prevent race conditions
  window.codkSvelteAppMounted = true;
  if (parentWindow && parentWindow !== window) {
    parentWindow.codkSvelteAppMounted = true;
  }

  app = mount(App, {
    target: document.getElementById("app"),
  });

  /**
   * Replace the live settings without reloading the widget.
   *
   * Takes the same snake_case payload /script/lightweight_settings serves, so
   * the caller never has to know the camelCase names the app uses internally.
   * The admin's live preview drives this as the merchant types; on a storefront
   * nothing calls it.
   *
   * @param {Record<string, any>} rawSettings
   * @returns {Record<string, any>|null} the mapped settings now in effect
   */
  window.codkApplySettings = (rawSettings) => {
    if (!rawSettings || typeof rawSettings !== "object") return null;
    const routeUrl = parentWindow.codkingRouteUrl?.endsWith("/")
      ? parentWindow.codkingRouteUrl.slice(0, -1)
      : parentWindow.codkingRouteUrl;
    const mapped = mapSettingsToCamel({
      ...rawSettings,
      routeUrl,
      shopDomain: parentWindow.Shopify?.shop,
    });
    actions.setSettings(mapped);
    otpStore.setSettings(mapped);
    return mapped;
  };

  // Fetch settings (check sessionStorage first to avoid duplicate API calls)
  async function fetchSettings() {
    try {
      // ⚡ CRITICAL: Check sessionStorage first (Liquid file may have already fetched)
      const existingSettingsStr =
        parentWindow.sessionStorage?.getItem("settingSession");

      if (existingSettingsStr) {
        try {
          const existingSettings = JSON.parse(existingSettingsStr);

          // Map settings (in case they're not mapped yet)
          const mappedSettings = mapSettingsToCamel({
            ...existingSettings,
            routeUrl: parentWindow.codkingRouteUrl?.endsWith("/")
              ? parentWindow.codkingRouteUrl.slice(0, -1)
              : parentWindow.codkingRouteUrl,
            shopDomain: parentWindow.Shopify?.shop,
          });

          // Store settings in app store
          actions.setSettings(mappedSettings);
          otpStore.setSettings(mappedSettings);

          // Re-store in session storage (in case mapping changed anything)
          parentWindow.sessionStorage.setItem(
            "settingSession",
            JSON.stringify(mappedSettings),
          );

          // Restore OTP + addresses from localStorage when persistent_signin is on
          const shopDomain = parentWindow.Shopify?.shop;
          if (shopDomain) {
            restorePersistentSigninIfEnabled(mappedSettings, shopDomain, {
              setSessionValue,
              appStore,
              actions,
            }).then(async (restored) => {
              if (restored) {
                // Validate SSO session is still active (single-logout support)
                const storedResponse = getSessionValue("preOrderOtpResponse");
                const ssoToken = storedResponse?.sso_session_token;
                if (ssoToken && isPersistentSigninEnabled(mappedSettings)) {
                  if (getSessionValue("ssoValidatedToken") === ssoToken) {
                    console.log("[SSO] Already validated in this tab, skipping sso_check");
                  } else {
                    console.log("[SSO] Persistent session restored, validating SSO token against backend...");
                    const { ssoCheck } = await import("./services/api.js");
                    const validation = await ssoCheck(shopDomain, ssoToken);
                    if (!validation.valid) {
                      console.log("[SSO] Backend session destroyed (logged out on another store), clearing local session");
                      const { clearPersistentData } = await import("./services/persistentSigninStorage.js");
                      const { clearOTPVerified } = await import("./services/sessionService.js");
                      clearPersistentData(shopDomain);
                      clearOTPVerified();
                      setSessionValue("shipping_addresses", []);
                      setSessionValue("preOrderOtpResponse", null);
                      setSessionValue("verifiedNumberData", null);
                      actions.setScreen("phone");
                      console.log("[SSO] Local session cleared, showing OTP form");
                    } else {
                      setSessionValue("ssoValidatedToken", ssoToken);
                      if (Array.isArray(validation.shippingAddress)) {
                        setSessionValue("shipping_addresses", validation.shippingAddress);
                      }
                      if (validation.customerLogin) {
                        setSessionValue("preOrderOtpResponse", { ...storedResponse, customerLogin: validation.customerLogin });
                      }
                      try {
                        const { savePersistentData, buildPersistentPayload } = await import("./services/persistentSigninStorage.js");
                        await savePersistentData(shopDomain, mappedSettings, buildPersistentPayload({
                          verifiedNumberData: getSessionValue("verifiedNumberData"),
                          preOrderOtpResponse: getSessionValue("preOrderOtpResponse"),
                          shipping_addresses: getSessionValue("shipping_addresses"),
                          customer_email: getSessionValue("customer-email"),
                          customer_id: getSessionValue("customer-id"),
                          cod_king_selected_address: getSessionValue("cod_king_selected_address"),
                        }));
                        console.log("[SSO] Backend session still valid, refreshed local cache");
                      } catch (_e) {
                        console.log("[SSO] Backend session still valid, keeping local session");
                      }
                    }
                  }
                } else {
                  console.log("[SSO] Persistent session restored, no SSO token to validate");
                }
              } else if (isPersistentSigninEnabled(mappedSettings)) {
                if (getSessionValue("ssoAutoLoginAttempted")) {
                  console.log("[SSO] Cross-merchant auto-login already attempted in this tab, skipping");
                } else {
                  console.log("[SSO] No local session, checking SSO cookie for cross-merchant login...");
                  const widgetState = {
                    setIsLoading: () => {},
                    setStep: (step) => otpStore.setStep(step),
                    setError: (err) => otpStore.setError(err),
                    setShowServerErrorText: (val) => otpStore.setShowServerErrorText(val),
                  };
                  const ssoResult = await attemptSsoAutoLogin(widgetState);
                  setSessionValue("ssoAutoLoginAttempted", "true");
                  if (ssoResult.success) {
                    const newToken = getSessionValue("preOrderOtpResponse")?.sso_session_token;
                    if (newToken) setSessionValue("ssoValidatedToken", newToken);
                    console.log("[SSO] Cross-merchant auto-login successful! Phone:", ssoResult.phone);
                    otpStore.setOtpData({ phoneNumber: ssoResult.phone });
                    const addresses = getSessionValue("shipping_addresses") || [];
                    if (addresses.length > 0) {
                      otpStore.setShippingAddressCount(addresses.length);
                      console.log("[SSO] Set shipping address count:", addresses.length);
                    }
                  } else {
                    console.log("[SSO] No SSO session found, showing OTP form");
                  }
                }
              } else {
                console.log("[SSO] persistent_signin is off for this store, skipping SSO check");
              }
            }).catch(() => {});
          }

          return mappedSettings;
        } catch (parseError) {
          // Fall through to fetch from API
        }
      } else {
      }

      const shopDomain = parentWindow.Shopify?.shop;
      if (!shopDomain) {
        throw new Error("Shopify shop domain not found");
      }

      // Get ROUTE_URL from parent window (exposed by notifik_svelte.liquid)
      const ROUTE_URL = parentWindow.codkingRouteUrl;
      if (!ROUTE_URL) {
        throw new Error(
          "ROUTE_URL not found - notifik_svelte.liquid not loaded correctly",
        );
      }

      // Remove trailing slash if present
      const baseUrl = ROUTE_URL.endsWith("/")
        ? ROUTE_URL.slice(0, -1)
        : ROUTE_URL;
      const apiUrl = `${baseUrl}/script/lightweight_settings?domain=${shopDomain}`;

      const response = await fetch(apiUrl, {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      });

      if (!response.ok) {
        throw new Error(`Settings fetch failed: ${response.status}`);
      }

      const rawSettings = await response.json();

      // Map settings (mirroring notifik.liquid.backup mapSettings function)
      // Handle both rawSettings.settings (nested) and rawSettings (flat) structures
      const settingsData = rawSettings.settings || rawSettings;
      const mappedSettings = mapSettingsToCamel({
        ...settingsData,
        routeUrl: baseUrl, // Use baseUrl (no trailing slash) for consistency
        shopDomain: shopDomain,
      });

      // Store settings
      actions.setSettings(mappedSettings);
      otpStore.setSettings(mappedSettings);

      // Store in session storage (for compatibility with notifik.js flow)
      parentWindow.sessionStorage.setItem(
        "settingSession",
        JSON.stringify(mappedSettings),
      );

      // Restore OTP + addresses from localStorage when persistent_signin is on
      if (shopDomain) {
        restorePersistentSigninIfEnabled(mappedSettings, shopDomain, {
          setSessionValue,
          appStore,
          actions,
        }).then(async (restored) => {
          if (restored) {
            // Validate SSO session is still active (single-logout support)
            const storedResponse = getSessionValue("preOrderOtpResponse");
            const ssoToken = storedResponse?.sso_session_token;
            if (ssoToken && isPersistentSigninEnabled(mappedSettings)) {
              if (getSessionValue("ssoValidatedToken") === ssoToken) {
                console.log("[SSO] Already validated in this tab, skipping sso_check");
              } else {
                console.log("[SSO] Persistent session restored, validating SSO token against backend...");
                const { ssoCheck } = await import("./services/api.js");
                const validation = await ssoCheck(shopDomain, ssoToken);
                if (!validation.valid) {
                  console.log("[SSO] Backend session destroyed (logged out on another store), clearing local session");
                  const { clearPersistentData } = await import("./services/persistentSigninStorage.js");
                  const { performLogout } = await import("./stores/otpStore.js");
                  clearPersistentData(shopDomain);
                  await performLogout("SSO_single_logout");
                } else {
                  setSessionValue("ssoValidatedToken", ssoToken);
                  if (Array.isArray(validation.shippingAddress)) {
                    setSessionValue("shipping_addresses", validation.shippingAddress);
                  }
                  if (validation.customerLogin) {
                    setSessionValue("preOrderOtpResponse", { ...storedResponse, customerLogin: validation.customerLogin });
                  }
                  try {
                    const { savePersistentData, buildPersistentPayload } = await import("./services/persistentSigninStorage.js");
                    await savePersistentData(shopDomain, mappedSettings, buildPersistentPayload({
                      verifiedNumberData: getSessionValue("verifiedNumberData"),
                      preOrderOtpResponse: getSessionValue("preOrderOtpResponse"),
                      shipping_addresses: getSessionValue("shipping_addresses"),
                      customer_email: getSessionValue("customer-email"),
                      customer_id: getSessionValue("customer-id"),
                      cod_king_selected_address: getSessionValue("cod_king_selected_address"),
                    }));
                    console.log("[SSO] Backend session still valid, refreshed local cache");
                  } catch (_e) {
                    console.log("[SSO] Backend session still valid, keeping local session");
                  }
                }
              }
            } else {
              console.log("[SSO] Persistent session restored, no SSO token to validate");
            }
          } else if (isPersistentSigninEnabled(mappedSettings)) {
            if (getSessionValue("ssoAutoLoginAttempted")) {
              console.log("[SSO] Cross-merchant auto-login already attempted in this tab, skipping");
            } else {
              console.log("[SSO] No local session, checking SSO cookie for cross-merchant login...");
              const widgetState = {
                setIsLoading: () => {},
                setStep: (step) => otpStore.setStep(step),
                setError: (err) => otpStore.setError(err),
                setShowServerErrorText: (val) => otpStore.setShowServerErrorText(val),
              };
              const ssoResult = await attemptSsoAutoLogin(widgetState);
              setSessionValue("ssoAutoLoginAttempted", "true");
              if (ssoResult.success) {
                const newToken = getSessionValue("preOrderOtpResponse")?.sso_session_token;
                if (newToken) setSessionValue("ssoValidatedToken", newToken);
                console.log("[SSO] Cross-merchant auto-login successful! Phone:", ssoResult.phone);
                otpStore.setOtpData({ phoneNumber: ssoResult.phone });
                const addresses = getSessionValue("shipping_addresses") || [];
                if (addresses.length > 0) {
                  otpStore.setShippingAddressCount(addresses.length);
                  console.log("[SSO] Set shipping address count:", addresses.length);
                }
              } else {
                console.log("[SSO] No SSO session found, showing OTP form");
              }
            }
          } else {
            console.log("[SSO] persistent_signin is off for this store, skipping SSO check");
          }
        }).catch(() => {});
      }

      return mappedSettings;
    } catch (error) {
      return null;
    }
  }

  // Start fetching settings immediately
  fetchSettings();

  import("./services/persistentSigninStats.js")
    .then(({ recordPersistentSigninStat }) => recordPersistentSigninStat?.())
    .catch(() => {});

  // Ensure OTP cart attributes are present on page load even when popup flow
  // remains muted and no screen calls getCart().
  import("./services/otpService.js")
    .then(({ ensureOtpCartAttributesSyncedOnStartup }) => {
      ensureOtpCartAttributesSyncedOnStartup?.();
    })
    .catch(() => {});

  // When user lands back after checkout redirect (any page), revert cart to original state if it was modified
  const runCartPageRevertIfNeeded = async () => {
    // if (!isCartPage()) return;
    if (isRedirectInProgress()) {
      console.log("[runCartPageRevertIfNeeded] redirect stamped within TTL, skipping revert");
      return;
    }
    const bundler_product_created = getLocalValue("bundler_product_created");
    if (bundler_product_created) {
      try {
          await cartRevertService();
      } catch {}
    }
    // cartRevertService();
  };

  // Run on every pageshow (bfcache restore or normal navigation) so cart revert works when returning to cart
  const win = parentWindow && parentWindow !== window ? parentWindow : window;
  win.addEventListener("pageshow", (e) => {
    const path = win.location?.pathname || "unknown";
    const fullUrl = win.location?.href || "unknown";
    console.log("[pageshow]", { path, fullUrl, persisted: e.persisted });
    setTimeout(runCartPageRevertIfNeeded, 0);
  });

  // Signal to parent ASAP: Svelte is ready. This clears the parent's boot spinner
  // and reveals the widget, so it must NOT wait on background work.
  parentWindow.codkingSvelteReady = true;
  parentWindow.dispatchEvent(
    new CustomEvent("codking-svelte-ready", {
      detail: { message: "Svelte app is now ready" },
    }),
  );

  // Post-checkout-redirect cart revert is cleanup that doesn't affect the widget
  // display — run it in the background so it never delays the ready signal.
  runCartPageRevertIfNeeded().catch(() => {});

  const warmToast = () => loadToastify();
  if (typeof requestIdleCallback === "function") {
    requestIdleCallback(warmToast, { timeout: 3000 });
  } else {
    setTimeout(warmToast, 1500);
  }
}

// Export app (null if already mounted, otherwise the mounted app)
export default app;

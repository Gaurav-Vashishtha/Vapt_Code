// this function will sync the session storage with the seiing
// fist its checked the session . set with setting call or not ..
// if now ,then do setting call and set the session storage with the settings call
// if yes then do nothing

import "./polyfills"; // Import polyfills for older browser compatibility
import { debugLog, getSessionValue } from "./otpUtils";
import { showSpinner } from "./spinner";
import axios from "axios";
import { sendErrorToAPI } from "../services/errorReporter";
import { hideSpinner } from "../utilities/spinner";
import { settingsMap, setSessionValue } from "../utilities/otpUtils";
import useOtpStore from "../stores/otpStore";

const fetchSettings = async () => {
  const otpStoreState = useOtpStore.getState();
  const { setSettings } = otpStoreState;
  showSpinner();
  try {
    const response = await axios.get(
      `https://${process.env.APP_HOST}/script/lightweight_settings?domain=${window.Shopify.shop}`
    );
    const newSettings = Object.fromEntries(
      Object.entries(settingsMap).map(([apiKey, stateKey]) => [
        stateKey,
        response.data[apiKey],
      ])
    );
    debugLog("setting called from api");
    setSessionValue("settingSession", newSettings);
    setSettings(newSettings);
    let countryArray = generateCountryArray(newSettings?.countryCodeList);
    setSessionValue("countryArray", countryArray);
    // const [countries, setCountries] = useState(countryArray || ["in"]);
    hideSpinner();
    const enablePreOrderOtp = !!response?.data?.enable_pre_order_otp; //!! (Double Negation): This is a common JavaScript idiom to convert a value to a boolean.

    enablePreOrderOtp === false ? hideSpinner() : null;
    return newSettings;
  } catch (error) {
    console.error("Error fetching settings:", error);
    hideSpinner();
    sendErrorToAPI(
      error,
      "syncSessionWithSettings.fetchSettings",
      "error",
      {
        operation: "syncSessionWithSettings.fetchSettings",
        domain: window.Shopify.shop,
      },
      {
        trackingId: "CODKING_CLIENT_ERROR",
        severity: "error",
        timestamp: new Date().toISOString(),
        operation: "syncSessionWithSettings.fetchSettings",
        shop: window.Shopify?.shop || "unknown",
        shopInfo: {
          domain: window.Shopify?.shop || "unknown",
          id: window.Shopify?.shopId || null,
          currency: window.Shopify?.currency || null,
          locale: window.Shopify?.locale || null,
          country: window.Shopify?.country || null,
        },
        url: window.location.href,
        error: {
          message: error?.message || String(error),
          name: error?.name || "UnknownError",
          status: error?.status || null,
          statusText: error?.statusText || null,
        },
        context: {
          userAgent: navigator.userAgent,
          platform: navigator.platform,
          language: navigator.language,
          onLine: navigator.onLine,
          stack: error?.stack || null,
          cartToken: null,
          isBuyNowButton: false,
          codkSessionId: getMachineId(),
          params: null,
        },
      }
    );
  }
};

export async function syncSessionWithSettings(setSettings) {
  const settingSession = getSessionValue("settingSession");
  if (settingSession) {
    debugLog("settingSession from session", settingSession);
    setSettings(settingSession);
    const enablePreOrderOtp = !!settingSession.enablePreOrderOtp;
    debugLog("enablePreOrderOtp", enablePreOrderOtp);
    let countryArray = generateCountryArray(settingSession?.countryCodeList);
    setSessionValue("countryArray", countryArray);
    return enablePreOrderOtp;
    // enablePreOrderOtp;  make this from here and return the boolean value
  } else {
    // Try to get settingSession for 5 seconds before falling back to fetchSettings
    const maxRetries = 10; // 10 retries with 500ms interval = 5 seconds
    const retryInterval = 500; // 500ms between retries

    for (let i = 0; i < maxRetries; i++) {
      await new Promise((resolve) => setTimeout(resolve, retryInterval));
      const retrySettingSession = getSessionValue("settingSession");

      if (retrySettingSession) {
        debugLog("settingSession found after retry", retrySettingSession);
        setSettings(retrySettingSession);
        const enablePreOrderOtp = !!retrySettingSession.enablePreOrderOtp;
        debugLog("enablePreOrderOtp from retry", enablePreOrderOtp);
        let countryArray = generateCountryArray(
          retrySettingSession?.countryCodeList
        );
        setSessionValue("countryArray", countryArray);
        return enablePreOrderOtp;
      }
    }

    // Fallback to fetchSettings after 5 seconds of retrying
    debugLog(
      "settingSession not found after 5 seconds, falling back to fetchSettings"
    );
    const settings = await fetchSettings();
    const enablePreOrderOtp =
      settings && settings.enablePreOrderOtp !== undefined
        ? !!settings.enablePreOrderOtp
        : false; //!! (Double Negation): This is a common JavaScript idiom to convert a value to a boolean.
    debugLog("settings from fetch", settings, enablePreOrderOtp);
    setSettings(settings);
    return enablePreOrderOtp;
  }
}
export function generateCountryArray(countryCodeList) {
  return countryCodeList
    ? typeof countryCodeList === "string"
      ? countryCodeList.toLowerCase().split(",")
      : countryCodeList.map((item) => item.toLowerCase())
    : [];
}

import React, { useState, useEffect, useRef, createContext } from "react";
import { camelizeKeys } from "humps";
import CrispChat from "../Components/Ops/CrispChat";
import PlansNewDesign from "../Components/PlansNewDesign";
import Plans from "../Components/Plans";
import Help from "../Components/Help";
import Settings from "../Components/Settings";
import I18n from "../i18n-lang";
import CODShowHide from "../Components/CODShowHide";
import CODFeesSettings from "../Components/CODFeesSettings";
import Summary from "../Components/Summary";
import Clarity from "../Components/Ops/Clarity";
import SettingWrapper from "../Components/SettingWrapper";
import Onboarding from "../Components/Onboarding";
import PrepaidSettings from "../Components/PrepaidSettings";
import CODFeesSettingsNew from "../Components/CODFeesSettingsNew";
import PartialPayments from "../Components/PartialPayment/PartialPayment";
import AnalyticsDashboardTabs from "../Components/AnalyticsDashboardTabs";
import ReportsPage from "../Components/ReportsPage";
import { Frame } from "@shopify/polaris";
import { currentAppPath } from "../Pages/SettingsHub/hubUrl";

// <html dir> for right-to-left app languages (Polaris follows it).
export const RTL_LOCALES = ["ar", "ur"];
export const applyTextDirection = (locale) => {
  if (typeof document === "undefined") return;
  const rtl = RTL_LOCALES.includes(String(locale || "").slice(0, 2));
  document.documentElement.setAttribute("dir", rtl ? "rtl" : "ltr");
  document.documentElement.setAttribute("lang", String(locale || "en"));
};

export const StoreContext = createContext(null);

const defaultSetting = {
  status: false,
  ivrIntroduction: "",
  ivrConfirmMessage: "",
  ivrCancelMessage: "",
};

function addAfter(array, index, newItem) {
  return [...array.slice(0, index), newItem, ...array.slice(index)];
}

const Store = ({
  children,
  shop: initialShop,
  setting: initialSetting,
  plan: initialPlan,
  crisp_url,
  scope_refresh_url,
  visible_plans,
  twilio_pricing,
  billing_snapshot,
}) => {
  // 1. TOP LEVEL STATES
  const [loading, setLoading] = useState(false);
  const [shop, setShop] = useState(initialShop);
  const [setting, setSetting] = useState(
    camelizeKeys(initialSetting) || defaultSetting,
  );
  const [originalSetting, setOriginalSetting] = useState(
    camelizeKeys(initialSetting) || defaultSetting,
  );
  const [plan, setPlan] = useState(initialPlan);
  const [billingSnapshot, setBillingSnapshot] = useState(
    camelizeKeys(billing_snapshot) || {},
  );
  const [analyticsDashboardTab, setAnalyticsDashboardTab] = useState(0);
  const [banner, setBanner] = useState({
    active: false,
    text: "",
    status: "info",
  });
  const [contextualBar, setContextualBar] = useState(false);

  // 2. NAVIGATION LOGIC (Path to Tab Index)
  const isPrepaidEnabled =
    shop.country_code === "IN" && shop.shopify_plan !== "staff";
  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;

  // Map URLs to Tab Indexes
  const getIndexFromPath = (path) => {
    if (path.startsWith("/quick-onboarding") || path === "/custom_setup")
      return 6 + prepaidTabIncrement;
    // New-nav section landing pages resolve to Summary index for legacy tab
    // fallback; the path-based renderContent handles their actual rendering.
    if (
      path === "/checkout" ||
      path.startsWith("/checkout/") ||
      path === "/messaging" ||
      path === "/post-purchase" ||
      path === "/checkout-enhancements" ||
      path.startsWith("/integrations")
    )
      return 0;
    if (path.includes("/features/otp")) return 1;
    if (path.includes("/features/notifications")) return 2;
    if (path.includes("/features/cod-show-hide")) return 3;
    if (path.includes("/features/cod-fees")) return 4 + prepaidTabIncrement;
    if (path.includes("/subscription") || path.includes("/plans") || path.includes("/billing"))
      return 5 + prepaidTabIncrement;
    if (path.includes("/onboarding")) return 6 + prepaidTabIncrement;
    if (path.includes("/features/partial-payment"))
      return 7 + prepaidTabIncrement;
    if (path.includes("/usage-analytics")) return 8 + prepaidTabIncrement;
    if (path === "/features") return 99; // Special case for Features list
    return 0; // Home/Summary
  };

  const [tab, setTab] = useState(() =>
    getIndexFromPath(currentAppPath()),
  );
  const previousPathRef = useRef(currentAppPath());

  // 3. TAB CONFIGURATION
  let tabs = [
    { id: "summary", content: I18n.t("store.home") },
    { id: "settings", content: I18n.t("store.otp_verification") },
    { id: "Notification", content: I18n.t("store.customer_notifications") },
    { id: "codShowHide", content: I18n.t("store.cod_show_hide") },
    { id: "codSettings", content: I18n.t("store.cod_fees") },
    { id: "subscription", content: I18n.t("store.subscription") },
    { id: "onboarding", content: I18n.t("store.onboarding") },
    { id: "PartialPayment", content: I18n.t("store.partial_payment") },
    {
      id: "AnalyticsDashboardTabs",
      content: I18n.t("store.analytics_dashboard"),
    },
    { id: "reports", content: I18n.t("store.scheduled_reports") },
  ];

  let PLANS_NEW_DESIGN_ENABLED =
    process?.env?.PLANS_NEW_DESIGN_ENABLED?.toLowerCase() === "true";

  let tabsList = [
    <Summary />,
    <SettingWrapper />,
    <SettingWrapper />,
    <CODShowHide />,
    initialSetting.cod_fee_enabled === true ? (
      <CODFeesSettings />
    ) : (
      <CODFeesSettingsNew />
    ),
    PLANS_NEW_DESIGN_ENABLED || visible_plans ? <PlansNewDesign /> : <Plans />,
    <Onboarding />,
    <PartialPayments />,
    <AnalyticsDashboardTabs />,
    <ReportsPage />,
  ];

  if (isPrepaidEnabled) {
    tabsList = addAfter(tabsList, 3, <PrepaidSettings />);
    tabs = addAfter(tabs, 3, { id: "prepaid", content: "COD-Prepaid" });
  }

  // 4. BROWSER HISTORY LISTENER
  useEffect(() => {
    const handleLocationChange = () => {
      const currentPath = currentAppPath();
      const previousPath = previousPathRef.current;

      // Shopify-like: when there are unsaved changes, block back entirely (no alert, no navigation)
      if (currentPath !== previousPath && contextualBar) {
        window.history.pushState({}, "", previousPath);
        setTab(getIndexFromPath(previousPath));
        return;
      }

      previousPathRef.current = currentPath;
      const targetTab = getIndexFromPath(currentPath);
      console.log(
        "Navigation detected:",
        currentPath,
        "Setting tab index to:",
        targetTab,
      );
      setTab(targetTab);
    };

    window.addEventListener("popstate", handleLocationChange);
    return () => window.removeEventListener("popstate", handleLocationChange);
  }, [contextualBar]); // setTab is stable, no need for dependency

  useEffect(() => {
    if (!contextualBar) return undefined;

    const handleBeforeUnload = (event) => {
      event.preventDefault();
      event.returnValue = "";
    };

    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, [contextualBar]);

  // 5. SHOPIFY CONFIG
  useEffect(() => {
    if (
      window.shopify &&
      window.shopify.config &&
      typeof window.shopify.config.set === "function"
    ) {
      window.shopify.config.set({ name: "COD King" });
    }
  }, []);

  // 6. CONTEXT PROVIDER VALUE
  const store = {
    loading: [loading, setLoading],
    shop: [shop, setShop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    plan: [plan, setPlan],
    billingSnapshot: [billingSnapshot, setBillingSnapshot],
    tab: [tab, setTab],
    tabs,
    tabsList,
    getIndexFromPath,
    isPrepaidEnabled,
    visiblePlans: visible_plans || [],
    twilioPricing: twilio_pricing,
    analyticsDashboardTab: [analyticsDashboardTab, setAnalyticsDashboardTab],
    banner: [banner, setBanner],
    contextualBar: [contextualBar, setContextualBar],
    // Add other missing states here if needed
  };

  // Locale: use server setting only (no localStorage). Arabic and Urdu read right to left.
  useEffect(() => {
    const locale = setting?.selectedLocale || "en";
    I18n.locale = locale;
    applyTextDirection(locale);
  }, [setting?.selectedLocale]);

  // Apply JSON locale translations to sidebar nav (ui-nav-menu)
  useEffect(() => {
    const navMenu = document.querySelector("ui-nav-menu");
    if (!navMenu) return;
    navMenu.querySelectorAll("a[data-i18n-key]").forEach((link) => {
      const key = link.getAttribute("data-i18n-key");
      if (key) link.textContent = I18n.t(key);
    });
  }, [setting?.selectedLocale]);

  return (
    <StoreContext.Provider value={store}>
      <Frame>
        <CrispChat shop={shop} plan={plan} />
        <Clarity shop={shop} plan={plan} />
        {children}
      </Frame>
    </StoreContext.Provider>
  );
};

export default Store;

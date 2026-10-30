import React, { useCallback, useContext, useEffect, useState } from "react";
import { Frame, Page, Card, Tabs } from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import CheckScopeAndReauth from "../Components/CheckScopeAndReauth";
import SettingWrapper from "../Components/SettingWrapper";
import { useQueryString } from "../Hooks/useQueryString";
import Features from "../Components/Features";
import PartialPayments from "../Components/PartialPayment/PartialPayment";
import CODShowHide from "../Components/CODShowHide";
import PrepaidSettings from "../Components/PrepaidSettings";
import PrepaidDiscount from "../Components/PrepaidDiscount/PrepaidDiscount";
import FreeGiftSettings from "../Components/Upsell/FreeGiftSettings";
import UpsellSettings from "../Components/Upsell/UpsellSettings";
import DiscountsPage from "../Components/Discounts/DiscountsPage";
import CODFeesSettingsNew from "../Components/CODFeesSettingsNew";
import PlansNewDesign from "../Components/PlansNewDesign";
import Plans from "../Components/Plans";
import AnalyticsDashboardTabs from "../Components/AnalyticsDashboardTabs";
import ReportsPage from "../Components/ReportsPage";
import HelpAndSupport from "../Components/HelpAndSupport";
import { navigateTo } from "../../utils/navigate";
import Notification from "../Components/Notification";
import WhatsappHub from "./Whatsapp/WhatsappHub";
import WhatsappAccountPage from "./Whatsapp/WhatsappAccountPage";
import WhatsappTemplatesPage from "./Whatsapp/WhatsappTemplatesPage";
import WhatsappCodVerification from "./Whatsapp/WhatsappCodVerification";
import WhatsappLogsPage from "./Whatsapp/WhatsappLogsPage";
import InboxApp, { isInboxPath, RedirectToInbox } from "./Whatsapp/Inbox/InboxApp";
import InboxNavBadge from "./Whatsapp/Inbox/InboxNavBadge";
import WhatsappCampaignsApp, { isCampaignsPath } from "./Whatsapp/Campaigns/WhatsappCampaignsApp";
import WebhookEndpoints from "./Webhooks/WebhookEndpoints";
import Onboarding from "../Components/Onboarding";
import QuickOnboarding from "../Components/QuickOnboarding";
import QuickOnboardingOtp from "../Components/QuickOnboardingOtp";
import QuickOnboardingBilling from "../Components/QuickOnboardingBilling";
import QuickOnboardingCodFees from "../Components/QuickOnboardingCodFees";
import QuickOnboardingNotifications from "../Components/QuickOnboardingNotifications";
import QuickOnboardingLimitCOD from "../Components/QuickOnboardingLimitCOD";
import CODFeesSettings from "../Components/CODFeesSettings";
import QuickOnboardingPartialPayment from "../Components/QuickOnboardingPartialPayment";
import PlansIndia from "../Components/PlansIndia";
import NetworkSettingTab from "../Components/Tabs/NetworkSettingTab";
import Api from "../Services/Api";
import Billing from "../Components/Billing";
import QuickOnboardingV2 from "../Components/QuickOnboardingV2";
import CustomSetup from "../Components/CustomSetup";
import { redirectIfPendingCustomSetupAndSubscribed } from "../utils/customSetupFlow";
import CheckoutHub from "./Hubs/CheckoutHub";
import MessagingHub from "./Hubs/MessagingHub";
import PostPurchaseHub from "./Hubs/PostPurchaseHub";
import CheckoutEnhancementsHub from "./Hubs/CheckoutEnhancementsHub";
import AddressPrefillSettings from "./Hubs/AddressPrefillSettings";
import IntegrationsHub from "../Components/Integrations/IntegrationsHub";
import GoogleAdsIntegration from "../Components/Integrations/GoogleAdsIntegration";
import PixelIntegration from "../Components/Integrations/PixelIntegration";
import SettingsHub from "./SettingsHub/SettingsHub";
import { isHubWrappedPath } from "./SettingsHub/registry";
import { currentAppPath } from "./SettingsHub/hubUrl";

// COD Form module: loaded on demand so the admin bundle does not grow for
// shops that never open it.
const CodFormApp = React.lazy(() =>
  import(/* webpackChunkName: "cod-form-admin" */ "./CodForm/CodFormApp"),
);
const FormPixelsPage = React.lazy(() =>
  import(
    /* webpackChunkName: "cod-form-admin" */ "./CodForm/Integrations/FormPixelsPage"
  ),
);
const GoogleSheetsPage = React.lazy(() =>
  import(
    /* webpackChunkName: "cod-form-admin" */ "./CodForm/Integrations/GoogleSheetsPage"
  ),
);

const Home = () => {
  const {
    shop: [shop],
    tabs,
    tabsList,
    tab: [tab, setTab],
    getIndexFromPath,
    scopeRefreshUrl,
    setting: [setting, setSetting],
    originalSetting: [originalSetting],
    visiblePlans,
  } = useContext(StoreContext);

  const qTab = useQueryString("qTab", "summary");
  const [location, setLocation] = useState(currentAppPath);
  const normalizedLocation =
    location.length > 1 ? location.replace(/\/+$/, "") : location;

  const handleTabChange = useCallback(
    (selectedTabIndex) => {
      setTab(selectedTabIndex);
    },
    [setTab],
  );

  useEffect(() => {
    const syncLocation = () => {
      setLocation(currentAppPath());
    };

    const emitLocationChange = () => {
      window.dispatchEvent(new Event("locationchange"));
    };

    const originalPushState = window.history.pushState;
    const originalReplaceState = window.history.replaceState;

    window.history.pushState = function (...args) {
      originalPushState.apply(window.history, args);
      emitLocationChange();
    };

    window.history.replaceState = function (...args) {
      originalReplaceState.apply(window.history, args);
      emitLocationChange();
    };

    syncLocation();
    window.addEventListener("popstate", syncLocation);
    window.addEventListener("locationchange", syncLocation);

    return () => {
      window.history.pushState = originalPushState;
      window.history.replaceState = originalReplaceState;
      window.removeEventListener("popstate", syncLocation);
      window.removeEventListener("locationchange", syncLocation);
    };
  }, []);

  /* Mark the nav link for the section the merchant is in as `active`.
     The current App Bridge only sends the admin each link's label and URL, so
     the admin lights Settings from the /settings-hub URL prefix instead (see
     SettingsHub/hubUrl.js). This keeps older App Bridge builds, which still
     read `active`, highlighting the same item. */
  useEffect(() => {
    const menu = document.querySelector("ui-nav-menu, s-app-nav");
    if (!menu) return;

    const links = Array.from(menu.querySelectorAll("a[data-nav-base]"));
    // /subscription is the older URL of the plans page (many in-app links still use it),
    // so it lights the Plans item just like /plans does.
    const path =
      normalizedLocation === "/subscription" || normalizedLocation.startsWith("/subscription/")
        ? "/plans"
        : normalizedLocation;

    const claims = (base) => {
      if (base === "/") return path === "/";
      return path === base || path.startsWith(`${base}/`);
    };

    // An exact base wins over Settings: Plans and Help & Support are their own
    // destinations, and only one item may carry the highlight.
    let winner = links
      .map((link) => link.getAttribute("data-nav-base"))
      .filter((base) => base !== "/" && base !== "/settings-hub" && claims(base))
      .sort((a, b) => b.length - a.length)[0];

    if (!winner && (path === "/settings-hub" || isHubWrappedPath(path))) {
      winner = "/settings-hub";
    }

    links.forEach((link) => {
      const owns = link.getAttribute("data-nav-base") === winner;
      if (owns === link.hasAttribute("active")) return;
      if (owns) link.setAttribute("active", "");
      else link.removeAttribute("active");
    });
  }, [normalizedLocation]);

  // Keep rendered component in sync when nav selection changes quickly.
  // This covers flows where tab/URL changes may happen before Home receives popstate.
  useEffect(() => {
    const nextPath = currentAppPath();
    setLocation((prevPath) => (prevPath === nextPath ? prevPath : nextPath));
  }, [tab]);

  // Function to update quick_onboarding_visited setting
  const markQuickOnboardingAsVisited = useCallback(async () => {
    try {
      // Make API call using the Api service (same as other components)
      console.log("📤 Sending API request via Api service");

      const response = await Api.post("/settings", {
        ...setting,
        quick_onboarding_visited: true,
      });

      // Update with the full response data to ensure context is synced
      setSetting(response.data);

      // Add a small delay to ensure state has updated, then check
      setTimeout(() => {
        console.log(
          "⏰ Setting value after context update:",
          setting?.quick_onboarding_visited,
        );
      }, 100);
    } catch (error) {
      console.error("❌ Error updating quick_onboarding_visited:", error);
    }
  }, [setting?.id, setSetting]); // Add setSetting to dependencies

  // Check if this is a first-time user and redirect to quick-onboarding
  useEffect(() => {
    // Only run this check if we have both shop data and settings, and not already on quick-onboarding
    if (
      !shop ||
      !setting ||
      normalizedLocation.startsWith("/quick-onboarding")
    ) {
      console.log("⏸️ Skipping onboarding check:", {
        hasShop: !!shop,
        hasSetting: !!setting,
        isOnboardingPage: normalizedLocation.startsWith("/quick-onboarding"),
      });
      return;
    }

    try {
      // Check if user has visited before (only from database)
      const hasVisitedBefore = setting?.quickOnboardingVisited === true;

      // Check if shop has no charge_id (blank or null)
      const hasNoChargeId =
        !shop.charge_id || shop.charge_id === null || shop.charge_id === "";

      console.log("🎯 Onboarding decision factors:", {
        hasVisitedBefore,
        hasNoChargeId,
        shouldRedirect: !hasVisitedBefore && hasNoChargeId,
      });

      // Redirect conditions: first visit AND no charge_id
      if (!hasVisitedBefore && hasNoChargeId) {
        console.log(
          "🔀 First-time user without subscription, redirecting to quick-onboarding",
        );

        // Mark as visited to prevent future redirects
        markQuickOnboardingAsVisited();

        // Redirect to quick-onboarding
        navigateTo("/quick-onboarding");
        return;
      }

      // Mark as visited for returning users or subscribed users who haven't been marked yet
      if (!hasVisitedBefore) {
        console.log(
          "✅ Marking existing user as visited (has subscription or returning user)",
        );
        markQuickOnboardingAsVisited();
      }
    } catch (error) {
      console.error("💥 Error checking onboarding status:", error);
    }
  }, [
    shop?.id,
    shop?.charge_id,
    setting?.quick_onboarding_visited,
    normalizedLocation,
  ]); // More stable dependencies

  useEffect(() => {
    if (!shop) return;
    redirectIfPendingCustomSetupAndSubscribed(shop);
  }, [shop]);

  const renderRouteContent = () => {
    if (normalizedLocation === "/checkout") {
      return <CheckoutHub />;
    } else if (normalizedLocation === "/checkout/address-prefill") {
      return <AddressPrefillSettings />;
    } else if (normalizedLocation === "/messaging") {
      return <MessagingHub />;
    } else if (normalizedLocation === "/post-purchase") {
      return <PostPurchaseHub />;
    } else if (normalizedLocation === "/checkout-enhancements") {
      return <CheckoutEnhancementsHub />;
    } else if (normalizedLocation === "/integrations") {
      return <IntegrationsHub />;
    } else if (normalizedLocation === "/integrations/google-ads") {
      return <GoogleAdsIntegration />;
    } else if (normalizedLocation === "/integrations/pixel") {
      return <PixelIntegration />;
    } else if (
      normalizedLocation === "/features/cod-form" ||
      normalizedLocation.startsWith("/features/cod-form/")
    ) {
      return (
        <React.Suspense fallback={null}>
          <CodFormApp path={normalizedLocation} />
        </React.Suspense>
      );
    } else if (
      normalizedLocation === "/integrations/tiktok" ||
      normalizedLocation === "/integrations/form-pixels"
    ) {
      return (
        <React.Suspense fallback={null}>
          <FormPixelsPage path={normalizedLocation} />
        </React.Suspense>
      );
    } else if (normalizedLocation === "/integrations/google-sheets") {
      return (
        <React.Suspense fallback={null}>
          <GoogleSheetsPage />
        </React.Suspense>
      );
    } else if (
      normalizedLocation === "/features/otp" ||
      normalizedLocation === "/features/otp/pre-order" ||
      normalizedLocation === "/features/otp/pre-order/ui" ||
      normalizedLocation === "/features/ui-customization" ||
      normalizedLocation === "/features/otp/post-order" ||
      normalizedLocation === "/features/post-order-otp" ||
      normalizedLocation === "/features/shopify-plus-widget" ||
      normalizedLocation === "/features/otp/checkout-extension"
    ) {
      return <SettingWrapper />;
    } else if (
      normalizedLocation === "/features/partial-payment" ||
      normalizedLocation === "/features/partial-payment/add" ||
      normalizedLocation === "/features/partial-payment/edit"
    ) {
      return <PartialPayments />;
    } else if (
      normalizedLocation === "/features/cod-show-hide" ||
      normalizedLocation === "/features/limit-cod"
    ) {
      return <CODShowHide />;
    } else if (normalizedLocation === "/features/cod-to-prepaid") {
      return <PrepaidSettings />;
    } else if (normalizedLocation === "/features/prepaid-discount") {
      return <PrepaidDiscount />;
    } else if (normalizedLocation === "/features/upsell") {
      return <UpsellSettings />;
    } else if (normalizedLocation === "/features/upsell/free-gift") {
      return <FreeGiftSettings />;
    } else if (normalizedLocation === "/features/cod-fees") {
      // Cod fee enabled
      return originalSetting?.codFeeEnabled ? (
        <CODFeesSettings />
      ) : (
        <CODFeesSettingsNew />
      );
    } else if (normalizedLocation === "/features/notifications") {
      return <Notification />;
    } else if (normalizedLocation === "/features/whatsapp") {
      return <WhatsappHub />;
    } else if (normalizedLocation === "/features/whatsapp/account") {
      return <WhatsappAccountPage />;
    } else if (normalizedLocation === "/features/whatsapp-cod-verification") {
      return <WhatsappCodVerification />;
    } else if (normalizedLocation === "/features/whatsapp/templates") {
      return <WhatsappTemplatesPage />;
    } else if (normalizedLocation === "/features/whatsapp/logs") {
      return <WhatsappLogsPage />;
    } else if (normalizedLocation === "/features/whatsapp/replies") {
      return <RedirectToInbox />;
    } else if (isInboxPath(normalizedLocation)) {
      return <InboxApp path={normalizedLocation} />;
    } else if (isCampaignsPath(normalizedLocation)) {
      return <WhatsappCampaignsApp path={normalizedLocation} />;
    } else if (normalizedLocation === "/integrations/webhooks") {
      return <WebhookEndpoints />;
    } else if (normalizedLocation === "/subscription" || normalizedLocation === "/plans") {
      if (
        visiblePlans &&
        Array.isArray(visiblePlans) &&
        visiblePlans.length > 0
      ) {
        return <PlansNewDesign />;
      } else {
        return <Plans shop={shop} />;
      }
    } else if (normalizedLocation === "/features") {
      return <Features />;
    } else if (
      normalizedLocation === "/usage-analytics" ||
      normalizedLocation === "/usage-analytics/order-logs" ||
      normalizedLocation === "/usage-analytics/message-logs" ||
      normalizedLocation === "/usage-analytics/usage-logs" ||
      normalizedLocation === "/usage-analytics/branded-notifications" ||
      normalizedLocation === "/usage-analytics/cod-king-abandoned-carts" ||
      normalizedLocation === "/usage-analytics/cod-form" ||
      normalizedLocation === "/usage-analytics/orders"
    ) {
      return <AnalyticsDashboardTabs />;
    } else if (normalizedLocation === "/features/reports") {
      return <ReportsPage />;
    } else if (normalizedLocation === "/features/discounts") {
      return <DiscountsPage />;
    } else if (normalizedLocation === "/help-and-support") {
      return <HelpAndSupport />;
    } else if (normalizedLocation === "/onboarding") {
      // return <QuickOnboarding />;
      return <QuickOnboardingV2 />;
    } else if (normalizedLocation === "/networks") {
      return <NetworkSettingTab />;
    } else if (normalizedLocation === "/billing") {
      return <Billing />;
    } else if (normalizedLocation === "/quick-onboarding") {
      // return <QuickOnboarding />;
      return <QuickOnboardingV2 />;
    } else if (
      normalizedLocation === "/quick-onboarding/otp" ||
      normalizedLocation === "/quick-onboarding/otp/pre-order" ||
      normalizedLocation === "/quick-onboarding/otp/post-order"
    ) {
      return <QuickOnboardingOtp />;
    } else if (normalizedLocation === "/quick-onboarding/billing") {
      if (
        visiblePlans &&
        Array.isArray(visiblePlans) &&
        visiblePlans.length > 0
      ) {
        return <PlansNewDesign />;
      } else {
        return <Plans shop={shop} />;
      }
      // return <QuickOnboardingBilling />;
    } else if (normalizedLocation === "/quick-onboarding/fees") {
      return <QuickOnboardingCodFees />;
    } else if (normalizedLocation === "/quick-onboarding/notifications") {
      return <QuickOnboardingNotifications />;
    } else if (normalizedLocation === "/quick-onboarding/limit-cod") {
      return <QuickOnboardingLimitCOD />;
    } else if (normalizedLocation === "/quick-onboarding/partial-payment") {
      return <QuickOnboardingPartialPayment />;
    } else if (normalizedLocation === "/quick-onboarding/all-features") {
      return <QuickOnboarding />;
    } else if (normalizedLocation === "/custom_setup") {
      return <CustomSetup />;
    }

    return (
      <Card>
        {tabsList[tab]}
        {/* <Tabs tabs={tabs} selected={tab} onSelect={handleTabChange} /> */}
      </Card>
    );
  };

  // Billing moved out of Settings into its own nav item: old /settings-hub/billing links
  // (bookmarks, emails) land on /billing.
  useEffect(() => {
    if (normalizedLocation === "/settings-hub/billing") {
      window.history.replaceState(window.history.state, "", `/billing${window.location.search}`);
    }
  }, [normalizedLocation]);

  const renderContent = () => {
    if (normalizedLocation === "/settings-hub/billing") return null;
    if (
      normalizedLocation === "/settings-hub" ||
      normalizedLocation.startsWith("/settings-hub/")
    ) {
      return <SettingsHub currentPath={normalizedLocation} />;
    }

    // There is no Features catalog; land old links in the Settings hub.
    if (normalizedLocation === "/features") {
      return <SettingsHub currentPath="/settings-hub" />;
    }

    const content = renderRouteContent();
    if (isHubWrappedPath(normalizedLocation)) {
      return (
        <SettingsHub currentPath={normalizedLocation}>{content}</SettingsHub>
      );
    }
    return content;
  };

  // Sync tab with URL: path or qTab. When on a sub-page, highlight the parent nav item (Built for Shopify 4.1.4).
  useEffect(() => {
    if (!tabs || !Array.isArray(tabs) || !getIndexFromPath) return;

    const pathname = currentAppPath();
    const isOnQuickOnboarding =
      pathname.startsWith("/quick-onboarding") ||
      pathname === "/onboarding" ||
      pathname === "/custom_setup";

    // When on quick-onboarding, always derive tab from path so we don't switch to Summary
    // (which would make the main content show the wrong view or go blank).
    if (isOnQuickOnboarding) {
      const pathIndex = getIndexFromPath(pathname);
      setTab(pathIndex);
      return;
    }

    const noFeaturesEnabled =
      !shop?.charge_id &&
      !(
        setting?.sms ||
        setting?.cod_fee_enabled ||
        setting?.abandoned_cart_enabled ||
        setting?.enable_pre_order_otp ||
        setting?.enable_shipping_cod_fees
      );

    const hasExplicitQTab =
      typeof window !== "undefined" &&
      window.location.search &&
      window.location.search.includes("qTab=");

    if (noFeaturesEnabled) {
      const index = tabs.findIndex((t) => t.id === "summary");
      if (index >= 0) setTab(index);
    } else if (hasExplicitQTab && qTab) {
      const index = tabs.findIndex((t) => t.id === qTab);
      if (index >= 0) setTab(index);
    } else {
      // No qTab in URL: derive tab from path so parent nav stays highlighted on sub-pages
      const pathIndex = getIndexFromPath(pathname);
      setTab(pathIndex);
    }
  }, [tabs, shop, setting, qTab, setTab, getIndexFromPath]);

  console.log("Home component rendered");

  return (
    <Frame>
      <Page fullWidth>
        <CheckScopeAndReauth scopeRefreshUrl={scopeRefreshUrl} />
        <InboxNavBadge />
        {renderContent()}
      </Page>
    </Frame>
  );
};

export default Home;

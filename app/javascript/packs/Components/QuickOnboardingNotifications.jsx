import React, { useContext, useEffect } from "react";
import {
  Page,
  BlockStack,
  InlineStack,
  Box,
  Button,
  Text,
} from "@shopify/polaris";
import NotificationSettingsTab from "./Tabs/NotificationSettingsTab";
import QuickBilling from "./QuickBilling";
import QuickCurrentStep from "./QuickCurrentStep";
import Notification from "./Notification";
import { StoreContext } from "../Context/Store";
import { hasNoChargeId } from "../utils/shopUtils";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import I18n from "../i18n-lang";

export default function QuickOnboardingNotifications() {
  const {
    setting,
    setSetting,
    shop: [shop],
    tab: [, setTab],
  } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  /**
   * App Bridge v4 Navigation Interceptor
   * Prevents full page reload and syncs with Shopify Admin
   */
  const handleRedirect = (e, path) => {
    if (e) e.preventDefault();

    // 1. Update the address bar without hitting the server
    window.history.pushState({}, '', path);

    // 2. Dispatch event so StoreProvider/Router can update the view
    const navEvent = new PopStateEvent('popstate');
    window.dispatchEvent(navEvent);

    // 3. If your StoreContext uses a setTab function for routing, call it here
    if (typeof setTab === 'function') {
      setTab(path);
    }
  };

  // Track page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: 2,
      feature: "notifications",
    });
  }, []);

  return (
    <Page
      title={I18n.t("quick_onboarding.notification_setup_title")}
      backAction={{
        content: I18n.t("quick_onboarding.quick_onboarding"),
        onAction: (e) => {
          journeyTracker.trackButtonClick("back_to_onboarding", {
            fromStep: 2,
            toStep: 1,
            feature: "notifications",
          });
          handleRedirect(e, "/quick-onboarding");
        },
      }}
    >
      {/* Progress & Instructions */}
      <QuickCurrentStep currentStep={2} />
      <br />
      {/* Proceed Button */}
      {shop && hasNoChargeId(shop) && (
        <QuickBilling navigationSource="onboarding-notifications" />
      )}
      <br />
      {/* Main Feature/Notification Settings */}
      <Box>
        <NotificationSettingsTab />
      </Box>
    </Page>
  );
}

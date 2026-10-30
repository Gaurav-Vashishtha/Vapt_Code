import React, { useContext, useEffect } from "react";
import I18n from "../i18n-lang";
import {
  Page,
  BlockStack,
  InlineStack,
  Box,
  Button,
  Text,
  Card,
} from "@shopify/polaris";
import PartialPayments from "./PartialPayment/PartialPayment";
import { ExternalSmallMinor } from "@shopify/polaris-icons";
import QuickBilling from "./QuickBilling";
import QuickCurrentStep from "./QuickCurrentStep";
import { StoreContext } from "../Context/Store";
import { hasNoChargeId } from "../utils/shopUtils";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

export default function QuickOnboardingPartialPayment() {
  const { setting, setSetting, shop, tab: [, setTab] } = useContext(StoreContext);
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
      feature: "partial-payment",
    });
  }, []);

  return (
    <Page
      backAction={{
        content: I18n.t("quick_onboarding_partial.back_action"),
        onAction: (e) => {
          journeyTracker.trackButtonClick("back_to_onboarding", {
            fromStep: 2,
            toStep: 1,
            feature: "partial-payment",
          });
          handleRedirect(e, "/quick-onboarding");
        },
      }}
      title={I18n.t("quick_onboarding_partial.title")}
      fullWidth={true}
    >
      <PartialPayments isOnboardingFlow={true} />
    </Page>
  );
}

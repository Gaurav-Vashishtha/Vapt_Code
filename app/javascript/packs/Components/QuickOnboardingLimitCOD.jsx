import React, { useContext, useEffect } from "react";
import {
  Page,
  BlockStack,
  InlineStack,
  Box,
  Button,
  Text,
  Card,
} from "@shopify/polaris";
// Removed navigateTo import - CODShowHide handles its own navigation
import CODShowHide from "./CODShowHide";
import QuickCurrentStep from "./QuickCurrentStep";
import QuickBilling from "./QuickBilling";
import { StoreContext } from "../Context/Store";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

export default function QuickOnboardingLimitCOD() {
  const { setting, setSetting } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // Track page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: 2,
      feature: "limit-cod",
    });
  }, []);

  return (
    <Page fullWidth>
      <CODShowHide
        isOnBoardingFlow={true}
        navigationSource="onboarding-codshowhide"
      />
    </Page>
  );
}

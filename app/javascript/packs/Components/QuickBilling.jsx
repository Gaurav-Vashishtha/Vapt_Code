// Billing.js
import React, { useContext } from "react";
import {
  BlockStack,
  Card,
  Button,
  Box,
  Text,
  InlineStack,
  Icon,
  Banner,
} from "@shopify/polaris";
import { navigateTo } from "../../utils/navigate";
import { ExternalSmallMinor } from "@shopify/polaris-icons";
import I18n from "../i18n-lang";
import { StoreContext } from "../Context/Store";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

export default function QuickBilling({
  disableBilling = false,
  navigationSource,
}) {
  const { setting, setSetting } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  return (
    <>
      <Box paddingBlockStart="4">
        {/* Warning Banner */}
        <Banner
          tone="warning"
          title={I18n.t("quick_billing.complete_billing_title")}
        >
          <Text variant="bodyMd">
            {I18n.t("quick_billing.test_mode_message")}
          </Text>
          <BlockStack gap="400">
            {/* Header Section */}
            <BlockStack gap="200">
              {/* <Text variant="bodyMd" tone="subdued">
                {I18n.t("quick_onboarding_billing.final_step_description")}
              </Text> */}
            </BlockStack>

            {/* Action Section */}
            <BlockStack gap="300">
              <Button
                variant="primary"
                size="large"
                fullWidth
                disabled={disableBilling}
                onClick={() => {
                  journeyTracker.trackButtonClick("proceed_to_billing", {
                    step: 2,
                    feature: "billing",
                    disableBilling: disableBilling,
                  });
                  const billingUrl = navigationSource
                    ? `/quick-onboarding/billing?from=${navigationSource}`
                    : "/quick-onboarding/billing";
                  navigateTo(billingUrl);
                }}
                icon={ExternalSmallMinor}
              >
                {I18n.t("quick_onboarding_billing.proceed_to_billing")}
              </Button>

              <Button
                variant="plain"
                size="small"
                onClick={() => {
                  journeyTracker.trackButtonClick("continue_test_mode", {
                    step: 2,
                    feature: "billing",
                  });
                  navigateTo("/");
                }}
                tone="subdued"
              >
                {I18n.t("quick_billing.continue_test_mode")}
              </Button>
            </BlockStack>

            {/* Warning Text */}
            <Box background="bg-surface-warning-subdued" borderRadius="200">
              <InlineStack gap="200" align="start">
                <Text variant="bodySm" tone="warning">
                  {I18n.t("quick_billing.activate_billing_note")}
                </Text>
              </InlineStack>
            </Box>
          </BlockStack>
        </Banner>
      </Box>
    </>
  );
}

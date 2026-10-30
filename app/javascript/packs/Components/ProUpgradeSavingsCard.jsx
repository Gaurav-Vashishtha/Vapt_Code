import React, { useState } from "react";
import { Badge, BlockStack, Box, Button, Card, InlineStack, Text } from "@shopify/polaris";
import Api from "../Services/Api";
import I18n from "../i18n-lang";

const PRO_PLAN_KEY = "Pro";

/**
 * Summary page, top: Indian shops on the Free plan that verify COD orders with OTP pay the
 * Free plan's per-message rates (PricingV3India::FREE_RATES_INR vs RATES_INR — SMS ₹1.00 vs
 * ₹0.30). Takes the place of the Abandoned cart intelligence row for them.
 *
 * "Upgrade to Pro" creates the Pro subscription charge (POST /plans/upgrade, the same call
 * as the Pro card on the plans page) and sends the merchant straight to Shopify's approval
 * screen. If no confirmation URL comes back, `onFallback` opens the plans page instead.
 */
const ProUpgradeSavingsCard = ({ onFallback }) => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const upgrade = () => {
    setLoading(true);
    setError(null);
    Api.post("/plans/upgrade", { name: PRO_PLAN_KEY, orders: 1000 })
      .then((response) => {
        const url = response?.data?.confirmationUrl || response?.data?.confirmation_url;
        if (url) {
          // App Bridge v4: top-level navigation to the Shopify charge screen.
          window.open(url, "_top");
          return;
        }
        setLoading(false);
        if (onFallback) onFallback();
      })
      .catch((err) => {
        setLoading(false);
        setError(
          err?.response?.data?.error ||
            err?.response?.data?.message ||
            I18n.t("summary.pro_upgrade_error", {
              defaultValue: "Couldn't open the upgrade. Please try again.",
            }),
        );
      });
  };

  return (
  <Box paddingBlockEnd="500">
    <Card padding="0">
      <Box padding="400" background="bg-surface-success">
        <InlineStack align="space-between" blockAlign="center" gap="300">
          <div style={{ flex: "1 1 320px", minWidth: 0 }}>
            <BlockStack gap="100">
              <InlineStack>
                <Badge tone="success" size="small">
                  {I18n.t("summary.pro_upgrade_badge", { defaultValue: "Save 70%" })}
                </Badge>
              </InlineStack>
              <Text variant="headingMd" as="h3">
                {I18n.t("summary.pro_upgrade_title", {
                  defaultValue: "Upgrade to Pro plan and slash message charges by 70%",
                })}
              </Text>
              <Text variant="bodySm" as="p" tone="subdued">
                {I18n.t("summary.pro_upgrade_body", {
                  defaultValue:
                    "You're on the Free plan, so every OTP and order message is billed at Free plan rates. On Pro, the same messages cost up to 70% less.",
                })}
              </Text>
              {error && (
                <Text variant="bodySm" as="p" tone="critical">
                  {error}
                </Text>
              )}
            </BlockStack>
          </div>
          <Button variant="primary" onClick={upgrade} loading={loading}>
            {I18n.t("summary.pro_upgrade_cta", { defaultValue: "Upgrade to Pro" })}
          </Button>
        </InlineStack>
      </Box>
    </Card>
  </Box>
  );
};

export default ProUpgradeSavingsCard;

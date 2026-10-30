import React from "react";
import { Badge, BlockStack, Box, Button, Divider, InlineStack, Text } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import useCodFormBootstrap, { patchBootstrap } from "../useCodFormBootstrap";
import { codFormApi } from "../api";
import { PATHS } from "../constants";
import { t } from "../i18n";

/**
 * Summary row for the COD Form (DSH-9): the opt-in card for shops that are
 * not using the form (until they dismiss it). Shops that use the form get no
 * row. Renders nothing for shops without the module. Laid out like OneClickCheckoutCard, which it
 * sits next to.
 */
const CodFormSummaryCard = () => {
  const bootstrap = useCodFormBootstrap();
  if (!bootstrap || !bootstrap.moduleEnabled) return null;

  if (bootstrap.mode !== "cod_form") {
    // The merchant closed the card: it stays closed (setup_state.dismissed_optin_at).
    if (bootstrap.optinDismissed) return null;
    const dismiss = () => {
      patchBootstrap({ optinDismissed: true });
      codFormApi.setup.dismissOptin().catch(() => {});
    };
    return (
      <React.Fragment>
        <Divider />
        <Box paddingBlock="300" paddingInline="400">
          <InlineStack align="space-between" blockAlign="center" gap="300" wrap={false}>
            <BlockStack gap="050">
              <InlineStack gap="150" blockAlign="center">
                <Text variant="headingSm" as="h3">
                  {t("summary.optin_title", "COD Form")}
                </Text>
                <Badge tone="attention" size="small">
                  {t("summary.optin_badge", "New")}
                </Badge>
              </InlineStack>
              <Text variant="bodySm" as="p" tone="subdued">
                {t("summary.optin_body", "Add a Buy with COD button that opens a one-page order form on your store. No redirect to checkout.")}
              </Text>
            </BlockStack>
            <InlineStack gap="200" blockAlign="center" wrap={false}>
              <Button onClick={dismiss} size="slim" variant="tertiary">
                {t("summary.optin_dismiss", "Not now")}
              </Button>
              <Button onClick={() => navigateTo(PATHS.setup)} size="slim">
                {t("summary.optin_cta", "Set up")}
              </Button>
            </InlineStack>
          </InlineStack>
        </Box>
      </React.Fragment>
    );
  }

  // COD Form is on: no row on the Summary page (usage and numbers live in the COD Form
  // screens and Analytics).
  return null;
};

export default CodFormSummaryCard;

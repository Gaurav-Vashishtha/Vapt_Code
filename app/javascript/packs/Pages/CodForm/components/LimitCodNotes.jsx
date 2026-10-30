import React from "react";
import { Banner, BlockStack, Box, Layout, Text } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { PATHS } from "../constants";
import { postalListSummary } from "../utils";
import { t } from "../i18n";

/**
 * Notes the COD Form adds to existing COD screens. Both render nothing for
 * shops without the module.
 */

/**
 * Limit COD and COD fees, Free plan (PM decision Q9): the form applies these
 * settings on every plan; the checkout versions stay Pro.
 * `feature` is "limit_cod" or "cod_fees".
 */
export const FreePlanFormNote = ({ feature, isFreePlan, asLayoutSection }) => {
  const bootstrap = useCodFormBootstrap();
  if (!bootstrap || !bootstrap.moduleEnabled || !isFreePlan) return null;
  const Wrapper = asLayoutSection ? Layout.Section : Box;
  const wrapperProps = asLayoutSection ? {} : { paddingBlockEnd: "400" };
  return (
    <Wrapper {...wrapperProps}>
      <Banner
        tone="info"
        action={{ content: t("common.upgrade_short", "Upgrade"), onAction: () => navigateTo(PATHS.subscription) }}
      >
        <p>
          {feature === "cod_fees"
            ? t("cod_fees.free_plan_note", "On the Free plan this applies to COD Form orders. Upgrade to Pro to apply it at Shopify checkout too.")
            : t("limit_cod.free_plan_note", "On the Free plan this applies to COD Form orders. Upgrade to Pro to apply it at Shopify checkout too.")}
        </p>
      </Banner>
    </Wrapper>
  );
};

/**
 * Limit COD postal lists (PM decision Q7): help text for both fields and the
 * allow-list warnings. Detection uses the PostalMatcher syntax rules.
 * Saving is never blocked. `selectedZips` is the allow list, `excludedZips`
 * the deny list (E.3).
 */
export const LimitCodPostalNotice = ({ visible, selectedZips, excludedZips }) => {
  const bootstrap = useCodFormBootstrap();
  if (!bootstrap || !bootstrap.moduleEnabled || !visible) return null;
  const allow = postalListSummary(selectedZips);
  const deny = postalListSummary(excludedZips);
  const critical = allow.total > 0 && allow.exact === 0;
  const warning = !critical && allow.patterns > 0;

  return (
    <BlockStack gap="300">
      <Text as="p" variant="bodySm" tone="subdued">
        {t("limit_cod.postal_help", "Prefixes (4000*) and ranges (1000-1999) work in the COD Form only. Shopify checkout matches exact codes.")}
      </Text>
      {critical && (
        <Banner tone="critical">
          <p>
            {t(
              "limit_cod.allow_list_critical",
              "This list has no exact postal codes, so Shopify checkout will hide COD for every buyer. Add exact codes, or turn on \"COD only through the form\".",
            )}
          </p>
        </Banner>
      )}
      {warning && (
        <Banner tone="warning">
          <p>
            {t(
              "limit_cod.allow_list_warning",
              "Prefixes and ranges are not read by Shopify checkout yet. With this list, checkout shows COD only for the exact codes in it.",
            )}
          </p>
        </Banner>
      )}
      {!critical && !warning && deny.patterns > 0 && (
        <Text as="p" variant="bodySm" tone="subdued">
          {t("limit_cod.deny_list_note", "The prefixes and ranges in your hide list are applied in the COD Form. Shopify checkout hides COD only for the exact codes.")}
        </Text>
      )}
    </BlockStack>
  );
};

export default LimitCodPostalNotice;

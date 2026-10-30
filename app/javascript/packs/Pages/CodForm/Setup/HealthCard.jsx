import React from "react";
import { Card, BlockStack, InlineStack, Text, Banner, Badge } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { isInternalPath } from "../utils";
import { t } from "../i18n";

/* Copy per health code (D.15 `health[].code`). The legacy-embed, COD-fee
   rule, OTP and postal lines are fixed product copy (H.8). */
const healthText = (item) => {
  const count = item.count == null ? 0 : item.count;
  switch (item.code) {
    case "embed_off":
      return t("setup.health_embed_off", "The COD Form app embed is off, so the COD button is not shown on your storefront.");
    case "legacy_embed_on":
      return t(
        "setup.health_legacy_embed_on",
        "Express checkout is also on, and both can run together. While \"COD King OTP Block\" is on, your theme's Buy now and Checkout buttons open Express checkout, and the Buy with COD button opens the COD Form. Turn that embed off only if you want those buttons to go to Shopify checkout.",
      );
    case "no_shipping_rate":
      return t("setup.health_no_shipping_rate", "No shipping rate is active. Buyers cannot complete the form until a rate matches their address.");
    case "no_country":
      return t("setup.health_no_country", "No country is enabled for the COD Form.");
    case "cap_reached":
      return t("setup.health_cap_reached", "You have reached this month's form order limit. The Buy with COD button is off on your store until next month, or until you upgrade.");
    case "cap_flagged":
      return t("setup.health_cap_flagged", "You have passed your plan's form orders for this month. Your form keeps working.");
    case "otp_unavailable":
      return t(
        "setup.health_otp_unavailable",
        "OTP could not be sent for %{count} orders in the last 24 hours. Those orders were placed without verification. Check your message balance.",
        { count },
      );
    case "rule_cod_fee_ignored":
      return t(
        "setup.health_rule_cod_fee_ignored",
        "Your partial payment rules include a COD fee. The COD Form uses the fee from COD fees settings, which is currently off.",
      );
    case "zip_allow_list_no_exact":
      return t(
        "setup.health_zip_allow_list_no_exact",
        "This list has no exact postal codes, so Shopify checkout will hide COD for every buyer. Add exact codes, or turn on \"COD only through the form\".",
      );
    default:
      return t("setup.health_unknown", "Something needs your attention (%{code}).", { code: item.code });
  }
};

const actionLabel = (item) => {
  switch (item.code) {
    case "embed_off":
    case "legacy_embed_on":
      return t("setup.health_action_theme", "Open theme editor");
    case "no_shipping_rate":
      return t("setup.health_action_shipping", "Add a rate");
    case "cap_reached":
    case "cap_flagged":
      return t("setup.health_action_upgrade", "See plans");
    case "rule_cod_fee_ignored":
      return t("setup.health_action_cod_fees", "Open COD fees");
    case "zip_allow_list_no_exact":
      return t("setup.health_action_limit_cod", "Open Limit COD");
    case "otp_unavailable":
      return t("setup.health_action_billing", "Open Billing");
    default:
      return t("setup.health_action_open", "Open");
  }
};

const TONE = { critical: "critical", warning: "warning", info: "info" };
const ORDER = { critical: 0, warning: 1, info: 2 };

/** Setup health check (DSH-11). Items never block the on/off switch. */
const HealthCard = ({ health }) => {
  const items = (Array.isArray(health) ? health : [])
    .slice()
    .sort((a, b) => (ORDER[a.severity] ?? 3) - (ORDER[b.severity] ?? 3));

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack gap="200" blockAlign="center">
          <Text as="h2" variant="headingMd">
            {t("setup.health_title", "Health check")}
          </Text>
          {items.length === 0 && <Badge tone="success">{t("setup.health_ok_badge", "All good")}</Badge>}
        </InlineStack>
        {items.length === 0 ? (
          <Text as="p" variant="bodyMd" tone="subdued">
            {t("setup.health_ok", "Nothing needs your attention.")}
          </Text>
        ) : (
          items.map((item, index) => {
            const url = item.action_url;
            const action = !url
              ? undefined
              : isInternalPath(url)
              ? { content: actionLabel(item), onAction: () => navigateTo(url) }
              : { content: actionLabel(item), url, external: true, target: "_blank" };
            return (
              <Banner key={`${item.code}-${index}`} tone={TONE[item.severity] || "info"} action={action}>
                <p>{healthText(item)}</p>
              </Banner>
            );
          })
        )}
      </BlockStack>
    </Card>
  );
};

export default HealthCard;

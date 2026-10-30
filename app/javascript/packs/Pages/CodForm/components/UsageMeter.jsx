import React from "react";
import { BlockStack, InlineStack, ProgressBar, Text, Badge } from "@shopify/polaris";
import { t } from "../i18n";

/**
 * Form orders this month against the plan cap (CAP-8).
 * `usage` is the object of GET /cod_form/usage or bootstrap.usage:
 * {period, orders, cap, state, behaviour, percent}. cap null = unlimited.
 */
const UsageMeter = ({ usage, compact }) => {
  if (!usage) return null;
  const orders = Number(usage.orders) || 0;
  const unlimited = usage.cap === null || usage.cap === undefined;
  const percent = unlimited
    ? 0
    : Math.min(100, Math.max(0, usage.percent != null ? Number(usage.percent) : usage.cap > 0 ? (orders / usage.cap) * 100 : 100));
  const tone = usage.state === "fallback" ? "critical" : percent >= 80 ? "highlight" : "primary";

  const stateBadge =
    usage.state === "fallback" ? (
      <Badge tone="critical">{t("setup.usage_state_fallback", "Cap reached")}</Badge>
    ) : usage.state === "grace" ? (
      <Badge tone="warning">{t("setup.usage_state_grace", "Grace orders")}</Badge>
    ) : usage.state === "flagged" ? (
      <Badge tone="attention">{t("setup.usage_state_flagged", "Above plan volume")}</Badge>
    ) : null;

  return (
    <BlockStack gap="200">
      <InlineStack align="space-between" blockAlign="center" gap="200">
        <Text as="p" variant={compact ? "bodySm" : "bodyMd"}>
          {unlimited
            ? t("setup.usage_unlimited", "%{orders} form orders this month · unlimited on your plan", { orders })
            : t("setup.usage_of_cap", "%{orders} of %{cap} form orders this month", { orders, cap: usage.cap })}
        </Text>
        {stateBadge}
      </InlineStack>
      {!unlimited && <ProgressBar progress={percent} size="small" tone={tone} />}
    </BlockStack>
  );
};

export default UsageMeter;

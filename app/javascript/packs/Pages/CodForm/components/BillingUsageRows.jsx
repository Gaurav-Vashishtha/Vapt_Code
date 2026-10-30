import React, { useEffect, useState } from "react";
import { BlockStack, Card, InlineStack, Text } from "@shopify/polaris";
import { codFormApi } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { t } from "../i18n";
import UsageMeter from "./UsageMeter";

/**
 * Billing screen: COD Form order usage and, when an overage rate is set for
 * the shop's plan, the overage line (CAP-8, CAP-9, H.8). Reads
 * GET /cod_form/usage. Renders nothing for shops without the module.
 */
const BillingUsageRows = () => {
  const bootstrap = useCodFormBootstrap();
  const enabled = !!bootstrap && bootstrap.moduleEnabled;
  const [usage, setUsage] = useState(null);

  useEffect(() => {
    if (!enabled) return undefined;
    let cancelled = false;
    codFormApi.usage
      .show()
      .then((response) => {
        if (!cancelled) setUsage(response || null);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [enabled]);

  if (!enabled || !usage) return null;
  const overage = usage.overage || {};
  const rate = overage.rate === null || overage.rate === undefined || overage.rate === "" ? null : Number(overage.rate);
  const hasRate = rate !== null && !Number.isNaN(rate) && rate > 0 && usage.cap != null;

  return (
    <Card padding="600">
      <BlockStack gap="300">
        <Text variant="headingMd" as="h2">
          {t("billing.title", "COD Form orders")}
        </Text>
        <UsageMeter usage={usage} />
        <InlineStack align="space-between" gap="300" wrap>
          <Text as="span" variant="bodySm" tone="subdued">
            {t("billing.usage_line", "Form orders this month: %{orders}", { orders: Number(usage.orders) || 0 })}
            {Number(usage.partial_orders) > 0
              ? ` · ${t("billing.partial_line", "of which partial payment: %{count}", { count: usage.partial_orders })}`
              : ""}
          </Text>
          {usage.period && (
            <Text as="span" variant="bodySm" tone="subdued">
              {usage.period}
            </Text>
          )}
        </InlineStack>
        {hasRate && (
          <BlockStack gap="100">
            <Text as="p" variant="bodyMd">
              {t("billing.overage_line", "After %{cap} form orders: $%{rate} per extra order", { cap: usage.cap, rate: rate.toFixed(2) })}
            </Text>
            {Number(overage.count) > 0 && (
              <Text as="p" variant="bodySm" tone="subdued">
                {t("billing.overage_count", "Extra orders this month: %{count} (%{billed} already billed)", {
                  count: overage.count,
                  billed: overage.billed || 0,
                })}
              </Text>
            )}
          </BlockStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default BillingUsageRows;

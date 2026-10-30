import React, { useEffect, useState } from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  Badge,
  ProgressBar,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import Api from "../../../Services/Api";
import I18n from "../../../i18n-lang";

const BillingPlanCard = () => {
  const [state, setState] = useState({
    loading: true,
    error: false,
    plan: null,
    usage: null,
  });

  useEffect(() => {
    let mounted = true;
    Promise.all([
      Api.get("/plans/opted_plan").then((r) => r.data),
      Api.get("/billing/usage_summary").then((r) => r.data),
    ])
      .then(([plan, usage]) => {
        if (mounted)
          setState({ loading: false, error: false, plan, usage });
      })
      .catch(() => {
        if (mounted)
          setState({ loading: false, error: true, plan: null, usage: null });
      });
    return () => {
      mounted = false;
    };
  }, []);

  const { loading, error, plan, usage } = state;

  const smsUsed = usage?.totals?.sms?.total ?? usage?.totals?.sms ?? 0;
  const smsCap = plan?.maxSms ?? 0;
  const usagePct =
    smsCap > 0 ? Math.min(100, Math.round((smsUsed / smsCap) * 100)) : 0;

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h3" variant="headingSm">
            {I18n.t("summary_v2.billing.title", { defaultValue: "Plan & usage" })}
          </Text>
          {!loading && !error && plan?.name && (
            <Badge tone="info">{plan.name}</Badge>
          )}
        </InlineStack>

        {loading ? (
          <BlockStack gap="200">
            <SkeletonDisplayText size="small" />
            <SkeletonBodyText lines={2} />
          </BlockStack>
        ) : error ? (
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("summary_v2.billing.error", { defaultValue: "Billing details are unavailable right now." })}
          </Text>
        ) : (
          <BlockStack gap="200">
            <Text as="p" variant="headingLg">
              {plan?.name || "—"}
            </Text>
            {plan?.price ? (
              <Text as="p" tone="subdued" variant="bodySm">
                {plan.price}
              </Text>
            ) : null}
            <BlockStack gap="100">
              <Text as="span" variant="bodySm" tone="subdued">
                {(I18n.t("summary_v2.billing.sms_used", { defaultValue: "SMS used" }))}:{" "}
                {smsUsed}
                {smsCap > 0 ? ` / ${smsCap}` : ""}
              </Text>
              {smsCap > 0 && (
                <ProgressBar progress={usagePct} size="small" tone="primary" />
              )}
            </BlockStack>
          </BlockStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default BillingPlanCard;

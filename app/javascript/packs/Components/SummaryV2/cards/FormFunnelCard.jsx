import React from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  ProgressBar,
  SkeletonBodyText,
} from "@shopify/polaris";
import useFastDashboard from "../useFastDashboard";
import I18n from "../../../i18n-lang";

const FunnelStep = ({ label, value, pct, upcoming }) => (
  <BlockStack gap="100">
    <InlineStack align="space-between" blockAlign="center">
      <Text as="span" variant="bodySm" tone={upcoming ? "subdued" : "base"}>
        {label}
      </Text>
      <Text as="span" variant="bodySm" fontWeight="semibold">
        {upcoming ? "—" : (value ?? 0)}
      </Text>
    </InlineStack>
    <ProgressBar
      progress={upcoming ? 0 : pct}
      size="small"
      tone={upcoming ? "highlight" : "primary"}
    />
  </BlockStack>
);

const FormFunnelCard = () => {
  const { data, loading, error } = useFastDashboard(30);
  const funnel = data?.funnel || {};

  const sessions = funnel.sessions;
  const checkoutInitiated = funnel.checkoutInitiated;
  const otpVerified = funnel.otpVerified ?? 0;
  const ordersPlaced = funnel.ordersPlaced ?? 0;

  const instrumentationLive =
    funnel.instrumentationLive != null
      ? !!funnel.instrumentationLive
      : !!(sessions || checkoutInitiated);

  const top = sessions || checkoutInitiated || otpVerified || ordersPlaced || 1;
  const pct = (v) => Math.min(100, Math.round(((v ?? 0) / top) * 100));

  return (
    <Card>
      <BlockStack gap="400">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.funnel.title", { defaultValue: "Checkout form funnel (30d)" })}
        </Text>
        {loading ? (
          <SkeletonBodyText lines={4} />
        ) : error ? (
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("summary_v2.error", { defaultValue: "Could not load data." })}
          </Text>
        ) : instrumentationLive ? (
          <BlockStack gap="300">
            <FunnelStep
              label={I18n.t("summary_v2.funnel.sessions", { defaultValue: "Sessions" })}
              value={sessions}
              pct={pct(sessions)}
            />
            <FunnelStep
              label={
                I18n.t("summary_v2.funnel.checkout_initiated", { defaultValue: "Checkout initiated" })
              }
              value={checkoutInitiated}
              pct={pct(checkoutInitiated)}
            />
            <FunnelStep
              label={I18n.t("summary_v2.funnel.otp_verified", { defaultValue: "OTP verified" })}
              value={otpVerified}
              pct={pct(otpVerified)}
            />
            <FunnelStep
              label={
                I18n.t("summary_v2.funnel.orders_placed", { defaultValue: "Orders placed" })
              }
              value={ordersPlaced}
              pct={pct(ordersPlaced)}
            />
          </BlockStack>
        ) : (
          <BlockStack gap="300">
            <FunnelStep
              label={I18n.t("summary_v2.funnel.sessions", { defaultValue: "Sessions" })}
              upcoming
            />
            <FunnelStep
              label={
                I18n.t("summary_v2.funnel.checkout_initiated", { defaultValue: "Checkout initiated" })
              }
              upcoming
            />
            <FunnelStep
              label={I18n.t("summary_v2.funnel.otp_verified", { defaultValue: "OTP verified" })}
              value={otpVerified}
              pct={pct(otpVerified)}
            />
            <FunnelStep
              label={
                I18n.t("summary_v2.funnel.orders_placed", { defaultValue: "Orders placed" })
              }
              value={ordersPlaced}
              pct={pct(ordersPlaced)}
            />
            <Text as="p" variant="bodySm" tone="subdued">
              {I18n.t("summary_v2.funnel.coming_soon", { defaultValue: "Sessions & checkout tracking coming soon" })}
            </Text>
          </BlockStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default FormFunnelCard;

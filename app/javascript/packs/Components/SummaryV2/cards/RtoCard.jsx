import React from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  SkeletonBodyText,
} from "@shopify/polaris";
import useFastDashboard from "../useFastDashboard";
import I18n from "../../../i18n-lang";

const Stat = ({ label, value }) => (
  <BlockStack gap="050">
    <Text as="span" variant="headingMd">
      {value != null ? `${value}%` : "—"}
    </Text>
    <Text as="span" variant="bodySm" tone="subdued">
      {label}
    </Text>
  </BlockStack>
);

const RtoCard = () => {
  const { data, loading, error } = useFastDashboard(30);
  const rto = data?.rto || {};

  return (
    <Card>
      <BlockStack gap="300">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.rto.title", { defaultValue: "Delivery health (30d)" })}
        </Text>
        {loading ? (
          <SkeletonBodyText lines={2} />
        ) : error ? (
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("summary_v2.error", { defaultValue: "Could not load data." })}
          </Text>
        ) : (
          <InlineStack gap="600" wrap>
            <Stat
              label={I18n.t("summary_v2.rto.delivered", { defaultValue: "Delivered" })}
              value={rto.deliveredPct}
            />
            <Stat
              label={I18n.t("summary_v2.rto.rto", { defaultValue: "RTO" })}
              value={rto.rtoPct}
            />
            <Stat
              label={I18n.t("summary_v2.rto.undelivered", { defaultValue: "Undelivered" })}
              value={rto.undeliveredPct}
            />
          </InlineStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default RtoCard;

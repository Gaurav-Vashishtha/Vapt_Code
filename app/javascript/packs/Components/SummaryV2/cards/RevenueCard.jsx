import React from "react";
import {
  Card,
  BlockStack,
  Text,
  SkeletonBodyText,
} from "@shopify/polaris";
import useFastDashboard from "../useFastDashboard";
import I18n from "../../../i18n-lang";

const RevenueCard = () => {
  const { data, loading, error } = useFastDashboard(30);

  const total = data?.revenue?.total;
  const currency = data?.revenue?.currency || "";

  return (
    <Card>
      <BlockStack gap="200">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.revenue.title", { defaultValue: "Revenue (30d)" })}
        </Text>
        {loading ? (
          <SkeletonBodyText lines={1} />
        ) : error ? (
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("summary_v2.error", { defaultValue: "Could not load data." })}
          </Text>
        ) : (
          <Text as="p" variant="headingLg">
            {total != null ? `${currency} ${total}`.trim() : "—"}
          </Text>
        )}
      </BlockStack>
    </Card>
  );
};

export default RevenueCard;

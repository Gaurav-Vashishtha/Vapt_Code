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
      {value ?? 0}
    </Text>
    <Text as="span" variant="bodySm" tone="subdued">
      {label}
    </Text>
  </BlockStack>
);

const OrdersBreakdownCard = () => {
  const { data, loading, error } = useFastDashboard(30);
  const orders = data?.orders || {};

  return (
    <Card>
      <BlockStack gap="300">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.orders.title", { defaultValue: "Orders (30d)" })}
        </Text>
        {loading ? (
          <SkeletonBodyText lines={2} />
        ) : error ? (
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("summary_v2.error", { defaultValue: "Could not load data." })}
          </Text>
        ) : (
          <BlockStack gap="200">
            <Text as="p" variant="headingLg">
              {orders.total ?? 0}
            </Text>
            <InlineStack gap="600" wrap>
              <Stat
                label={I18n.t("summary_v2.orders.cod", { defaultValue: "COD" })}
                value={orders.cod}
              />
              <Stat
                label={I18n.t("summary_v2.orders.prepaid", { defaultValue: "Prepaid" })}
                value={orders.prepaid}
              />
              <Stat
                label={I18n.t("summary_v2.orders.verified", { defaultValue: "Verified" })}
                value={orders.verified}
              />
            </InlineStack>
          </BlockStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default OrdersBreakdownCard;

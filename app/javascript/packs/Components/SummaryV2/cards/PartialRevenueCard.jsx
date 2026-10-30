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

const PartialRevenueCard = () => {
  const { data, loading, error } = useFastDashboard(30);
  const partial = data?.partialPayment || {};
  const currency = data?.revenue?.currency || "";

  return (
    <Card>
      <BlockStack gap="200">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.partial.title", { defaultValue: "Partial payments (30d)" })}
        </Text>
        {loading ? (
          <SkeletonBodyText lines={2} />
        ) : error ? (
          <Text as="p" tone="subdued" variant="bodySm">
            {I18n.t("summary_v2.error", { defaultValue: "Could not load data." })}
          </Text>
        ) : (
          <InlineStack gap="600" wrap>
            <BlockStack gap="050">
              <Text as="span" variant="headingLg">
                {partial.count ?? 0}
              </Text>
              <Text as="span" variant="bodySm" tone="subdued">
                {I18n.t("summary_v2.partial.orders", { defaultValue: "Orders" })}
              </Text>
            </BlockStack>
            <BlockStack gap="050">
              <Text as="span" variant="headingLg">
                {partial.value != null
                  ? `${currency} ${partial.value}`.trim()
                  : "—"}
              </Text>
              <Text as="span" variant="bodySm" tone="subdued">
                {I18n.t("summary_v2.partial.collected", { defaultValue: "Collected" })}
              </Text>
            </BlockStack>
          </InlineStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default PartialRevenueCard;

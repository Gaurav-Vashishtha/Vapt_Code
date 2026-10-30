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

const MessageSummaryCard = () => {
  const { data, loading, error } = useFastDashboard(30);
  const messages = data?.messages || {};

  return (
    <Card>
      <BlockStack gap="300">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.messages.title", { defaultValue: "Messages sent (30d)" })}
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
              {messages.totalSent ?? 0}
            </Text>
            <InlineStack gap="600" wrap>
              <Stat
                label={I18n.t("summary_v2.messages.sms", { defaultValue: "SMS" })}
                value={messages.sms}
              />
              <Stat
                label={I18n.t("summary_v2.messages.whatsapp", { defaultValue: "WhatsApp" })}
                value={messages.whatsapp}
              />
              <Stat
                label={
                  I18n.t("summary_v2.messages.abandoned_cart", { defaultValue: "Abandoned cart" })
                }
                value={messages.abandonedCartSent}
              />
            </InlineStack>
          </BlockStack>
        )}
      </BlockStack>
    </Card>
  );
};

export default MessageSummaryCard;

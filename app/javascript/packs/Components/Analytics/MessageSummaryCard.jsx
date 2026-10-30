import React, { useEffect, useState } from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Box,
  Text,
  Button,
} from "@shopify/polaris";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import { navigateTo } from "../../../utils/navigate";

/**
 * How many messages went out over the range, and through which channel.
 *
 * Lifted out of the Summary screen, and self-contained for the same reason as
 * the usage card: one line to place, and it owns its own request.
 */
const Row = ({ label, value }) => (
  <InlineStack align="space-between" blockAlign="center">
    <Text variant="bodyMd" tone="subdued">
      {label}
    </Text>
    <Text variant="headingSm" fontWeight="bold">
      {(value || 0).toLocaleString()}
    </Text>
  </InlineStack>
);

const MessageSummaryCard = ({ days = "1" }) => {
  const [messages, setMessages] = useState({});

  useEffect(() => {
    let cancelled = false;
    Api.get("/twilio_logs", { params: { query: "", page: 1, days } })
      .then((response) => {
        if (!cancelled) setMessages(response?.data || {});
      })
      .catch(() => {
        if (!cancelled) setMessages({});
      });
    return () => {
      cancelled = true;
    };
  }, [days]);

  return (
    <Card>
      <Box padding="500">
        <BlockStack gap="400">
          <Text variant="headingMd" as="h2">
            {I18n.t("summary.message_summary")}
          </Text>
          <BlockStack gap="300">
            <Row
              label={I18n.t("summary.total_message")}
              value={messages?.totalMessageCount}
            />
            <Row
              label={I18n.t("summary.abondoned_cart_success_sms")}
              value={messages?.acCountSms}
            />
            <Row
              label={I18n.t("summary.total_success_whatsapp")}
              value={messages?.whatsappMessages}
            />
          </BlockStack>
          <Box paddingBlockStart="200">
            <Button
              variant="plain"
              onClick={() => navigateTo("/usage-analytics/message-logs")}
            >
              {I18n.t("summary.view_message_logs")}
            </Button>
          </Box>
        </BlockStack>
      </Box>
    </Card>
  );
};

export default MessageSummaryCard;

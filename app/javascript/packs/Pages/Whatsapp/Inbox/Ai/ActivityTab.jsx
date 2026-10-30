import React, { useEffect, useState } from "react";
import { Badge, Banner, BlockStack, Box, Button, Card, InlineGrid, InlineStack, SkeletonBodyText, Text } from "@shopify/polaris";
import { navigateTo } from "../../../../../utils/navigate";
import { conversationPath, errorMessage, relativeTime, t } from "../format";
import { aiApi, formatCredits } from "./api";
import { reasonLabel } from "./TestTab";

const OUTCOMES = {
  replied: { tone: "success", label: () => t("ai.outcome_replied", "Replied") },
  drafted: { tone: "info", label: () => t("ai.outcome_drafted", "Draft") },
  handoff: { tone: "warning", label: () => t("ai.outcome_handoff", "Handed over") },
  skipped: { tone: undefined, label: () => t("ai.outcome_skipped", "Skipped") },
  failed: { tone: "critical", label: () => t("ai.outcome_failed", "Failed") },
};

const Stat = ({ label, value }) => (
  <Card>
    <BlockStack gap="100">
      <Text as="p" tone="subdued" variant="bodySm">
        {label}
      </Text>
      <Text as="p" variant="headingLg">
        {formatCredits(value)}
      </Text>
    </BlockStack>
  </Card>
);

const ActivityTab = () => {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    aiApi
      .runs()
      .then(setData)
      .catch(setError);
  }, []);

  if (error) return <Banner tone="critical">{errorMessage(error)}</Banner>;
  if (!data) {
    return (
      <Card>
        <SkeletonBodyText lines={6} />
      </Card>
    );
  }

  const s = data.stats || {};
  return (
    <BlockStack gap="400">
      <Text as="p" tone="subdued">
        {t("ai.last_7_days", "Last 7 days")}
      </Text>
      <InlineGrid columns={{ xs: 2, md: 4, lg: 7 }} gap="300">
        <Stat label={t("ai.stat_replies", "AI replies")} value={s.replies} />
        <Stat label={t("ai.stat_handoffs", "Handed to team")} value={s.handoffs} />
        <Stat label={t("ai.stat_cod", "COD orders confirmed")} value={s.cod_confirmed} />
        <Stat label={t("ai.stat_paylinks", "Payment links sent")} value={s.payment_links} />
        <Stat label={t("ai.stat_discounts", "Discounts given")} value={s.discounts} />
        <Stat label={t("ai.stat_orders", "Orders placed")} value={s.orders_placed} />
        <Stat label={t("ai.stat_credits", "Credits used")} value={s.credits} />
      </InlineGrid>
      <Card padding="0">
        {data.runs.length === 0 ? (
          <Box padding="400">
            <Text as="p" tone="subdued" alignment="center">
              {t("ai.activity_empty", "No AI conversations yet. Turn on Test mode and send a message to see it here.")}
            </Text>
          </Box>
        ) : (
          data.runs.map((run, index) => {
            const outcome = OUTCOMES[run.outcome] || OUTCOMES.skipped;
            return (
              <Box
                key={run.id}
                padding="300"
                borderBlockStartWidth={index === 0 ? undefined : "025"}
                borderColor="border-secondary"
              >
                <InlineStack align="space-between" blockAlign="start" gap="300" wrap={false}>
                  <BlockStack gap="100">
                    <InlineStack gap="200" blockAlign="center">
                      <Text as="span" fontWeight="semibold">
                        {run.customer?.name || run.customer?.phone_display || t("ai.customer", "Customer")}
                      </Text>
                      <Badge tone={outcome.tone}>{outcome.label()}</Badge>
                      {run.mode === "test" && <Badge>{t("ai.mode_test", "Test")}</Badge>}
                      {run.mode === "suggest" && <Badge>{t("ai.mode_suggest", "Suggested")}</Badge>}
                      {run.outcome === "handoff" && run.handoff_reason && (
                        <Text as="span" variant="bodySm" tone="subdued">
                          {reasonLabel(run.handoff_reason)}
                        </Text>
                      )}
                    </InlineStack>
                    {run.reply_text && (
                      <Text as="p" tone="subdued" variant="bodySm">
                        {run.reply_text.length > 160 ? `${run.reply_text.slice(0, 160)}…` : run.reply_text}
                      </Text>
                    )}
                    {run.error && (
                      <Text as="p" tone="critical" variant="bodySm">
                        {run.error}
                      </Text>
                    )}
                  </BlockStack>
                  <BlockStack gap="100" inlineAlign="end">
                    <Text as="span" variant="bodySm" tone="subdued">
                      {relativeTime(run.created_at)}
                    </Text>
                    {run.conversation_id && (
                      <Button variant="plain" onClick={() => navigateTo(conversationPath(run.conversation_id))}>
                        {t("ai.open_chat", "Open chat")}
                      </Button>
                    )}
                  </BlockStack>
                </InlineStack>
              </Box>
            );
          })
        )}
      </Card>
    </BlockStack>
  );
};

export default ActivityTab;

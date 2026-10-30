import React, { useEffect, useState } from "react";
import { BlockStack, Box, Button, Card, Collapsible, InlineGrid, InlineStack, Text } from "@shopify/polaris";
import { ChevronDownMinor, ChevronUpMinor } from "@shopify/polaris-icons";
import { inboxApi } from "./api";
import { formatDuration, t } from "./format";

const STORAGE_KEY = "codking.inbox.report_open";

const readOpen = () => {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "1";
  } catch (e) {
    return false;
  }
};

const Stat = ({ label, value }) => (
  <BlockStack gap="050">
    <Text as="span" variant="bodySm" tone="subdued">
      {label}
    </Text>
    <Text as="span" variant="headingMd">
      {value}
    </Text>
  </BlockStack>
);

const ReportCard = () => {
  const [report, setReport] = useState(null);
  const [open, setOpen] = useState(readOpen);

  useEffect(() => {
    let alive = true;
    inboxApi
      .reports()
      .then((data) => alive && setReport(data))
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, []);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, next ? "1" : "0");
    } catch (e) {
      setOpen(next);
    }
  };

  if (!report) return null;
  const agents = report.replies_by_agent || [];

  return (
    <Card padding="300">
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="center" gap="200">
          <InlineGrid columns={{ xs: 3 }} gap="400">
            <Stat
              label={t("report.first_response", "Median first response")}
              value={formatDuration(report.first_response_median_seconds)}
            />
            <Stat label={t("report.open", "Open")} value={Number(report.open || 0).toLocaleString()} />
            <Stat
              label={t("report.resolved_week", "Resolved this week")}
              value={Number(report.resolved_this_week || 0).toLocaleString()}
            />
          </InlineGrid>
          {agents.length > 0 && (
            <Button
              variant="tertiary"
              icon={open ? ChevronUpMinor : ChevronDownMinor}
              onClick={toggle}
              ariaExpanded={open}
              ariaControls="inbox-report-agents"
            >
              {t("report.replies_by_agent", "Replies by agent")}
            </Button>
          )}
        </InlineStack>
        <Collapsible id="inbox-report-agents" open={open && agents.length > 0}>
          <Box paddingBlockStart="200">
            <BlockStack gap="100">
              {agents.map((row) => (
                <InlineStack key={row.agent_id ?? row.name} align="space-between">
                  <Text as="span">{row.name}</Text>
                  <Text as="span" numeric>
                    {Number(row.replies || 0).toLocaleString()}
                  </Text>
                </InlineStack>
              ))}
            </BlockStack>
          </Box>
        </Collapsible>
      </BlockStack>
    </Card>
  );
};

export default ReportCard;

import React from "react";
import { Badge, BlockStack, Card, DataTable, InlineGrid, Text } from "@shopify/polaris";
import { countryName } from "../constants";
import { formatDateTime } from "../utils";
import { t } from "../i18n";

const SOURCES = {
  product: ["analytics.source_product", "Product page"],
  cart: ["analytics.source_cart", "Cart page"],
  drawer: ["analytics.source_drawer", "Cart drawer"],
  quick_buy: ["analytics.source_quick_buy", "Quick buy"],
  embedded: ["analytics.source_embedded", "Embedded form"],
  recovery: ["analytics.source_recovery", "Recovery link"],
  api: ["analytics.source_api", "Custom button"],
};

const STATUSES = {
  ordered: ["analytics.status_ordered", "Ordered", "success"],
  handoff_partial: ["analytics.status_partial", "Partial payment", "info"],
  handoff_prepaid: ["analytics.status_prepaid", "Paid online", "info"],
  blocked: ["analytics.status_blocked", "Blocked", "critical"],
  recovered: ["analytics.status_recovered", "Recovered", "success"],
  otp_pending: ["analytics.status_otp", "Waiting for OTP", "attention"],
  ordering: ["analytics.status_ordering", "Placing order", "attention"],
  open: ["analytics.status_open", "No order", undefined],
  abandoned: ["analytics.status_abandoned", "Abandoned", undefined],
  expired: ["analytics.status_expired", "No order", undefined],
};

const label = (map, key) => (map[key] ? t(map[key][0], map[key][1]) : key || t("analytics.key_none", "(none)"));
const keyLabel = (dimension, key) => {
  if (!key || key === "unknown") return t("analytics.key_none", "(none)");
  if (dimension === "country") return countryName(key);
  if (dimension === "source") return label(SOURCES, key);
  return key.charAt(0).toUpperCase() + key.slice(1);
};

const Split = ({ title, dimension, rows, number, percent }) => (
  <Card>
    <BlockStack gap="300">
      <Text as="h3" variant="headingSm">
        {title}
      </Text>
      {rows.length === 0 ? (
        <Text as="p" tone="subdued">
          {t("analytics.empty", "No form activity in this period yet.")}
        </Text>
      ) : (
        <DataTable
          columnContentTypes={["text", "numeric", "numeric", "numeric"]}
          headings={[
            "",
            t("analytics.sessions", "Sessions"),
            t("analytics.orders", "Orders"),
            t("analytics.conversion_rate", "Conversion rate"),
          ]}
          rows={rows.map((row) => [keyLabel(dimension, row.key), number(row.sessions), number(row.orders), percent(row.conversion_rate)])}
        />
      )}
    </BlockStack>
  </Card>
);

/**
 * Form sessions, live from the sessions table: where they came from, on what
 * device and country, and the latest sessions with their outcome. No buyer details.
 */
const SessionsPanel = ({ data, number, percent, money }) => {
  const recent = (data && data.recent) || [];
  return (
    <BlockStack gap="400">
      <InlineGrid columns={{ xs: 1, md: 3 }} gap="400">
        <Split title={t("analytics.by_source", "By source")} dimension="source" rows={(data && data.by_source) || []} number={number} percent={percent} />
        <Split title={t("analytics.by_device", "By device")} dimension="device" rows={(data && data.by_device) || []} number={number} percent={percent} />
        <Split title={t("analytics.by_country", "By country")} dimension="country" rows={(data && data.by_country) || []} number={number} percent={percent} />
      </InlineGrid>
      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("analytics.recent_sessions", "Latest sessions")}
          </Text>
          {recent.length === 0 ? (
            <Text as="p" tone="subdued">
              {t("analytics.empty", "No form activity in this period yet.")}
            </Text>
          ) : (
            <DataTable
              columnContentTypes={["text", "text", "text", "text", "text", "text", "numeric"]}
              headings={[
                t("analytics.col_time", "Time"),
                t("analytics.col_source", "Source"),
                t("analytics.col_device", "Device"),
                t("analytics.col_country", "Country"),
                t("analytics.col_outcome", "Outcome"),
                t("analytics.col_order", "Order"),
                t("analytics.col_total", "Total"),
              ]}
              rows={recent.map((row) => [
                formatDateTime(row.created_at),
                label(SOURCES, row.source),
                keyLabel("device", row.device),
                keyLabel("country", row.country),
                <Badge key={row.id} tone={(STATUSES[row.status] || [])[2]}>
                  {label(STATUSES, row.status)}
                </Badge>,
                row.order_name || "—",
                row.total_cents === null || row.total_cents === undefined ? "—" : money(row.total_cents),
              ])}
            />
          )}
        </BlockStack>
      </Card>
    </BlockStack>
  );
};

export default SessionsPanel;

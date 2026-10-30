import React, { useEffect, useState } from "react";
import { Banner, BlockStack, Card, DataTable, InlineStack, Select, SkeletonBodyText, Text } from "@shopify/polaris";
import { codFormApi, parseError } from "../api";
import { countryName } from "../constants";
import { resourceTitle } from "../components/ResourceTargetPicker";
import { t } from "../i18n";

const DIMENSIONS = ["utm_campaign", "offer", "country", "device", "product", "form"];

const dimensionLabel = (dimension) => {
  switch (dimension) {
    case "utm_campaign":
      return t("analytics.by_campaign", "By UTM campaign");
    case "offer":
      return t("analytics.by_offer", "By offer");
    case "country":
      return t("analytics.by_country", "By country");
    case "device":
      return t("analytics.by_device", "By device");
    case "product":
      return t("analytics.by_product", "By product");
    default:
      return t("analytics.by_form", "By form");
  }
};

const keyLabel = (dimension, key) => {
  if (key === null || key === undefined || key === "") return t("analytics.key_none", "(none)");
  if (dimension === "country") return countryName(key);
  if (dimension === "product") return resourceTitle("product", key);
  return String(key);
};

/** Breakdowns by campaign, offer, country, device, product, form (ANL-4). */
const BreakdownTable = ({ from, to, money }) => {
  const [by, setBy] = useState("utm_campaign");
  const [rows, setRows] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    setError(null);
    codFormApi.analytics
      .breakdown({ by, from, to })
      .then((response) => {
        if (!cancelled) setRows((response && response.rows) || []);
      })
      .catch((err) => {
        if (!cancelled) setError(parseError(err));
      });
    return () => {
      cancelled = true;
    };
  }, [by, from, to]);

  return (
    <Card>
      <BlockStack gap="400">
        <InlineStack align="space-between" blockAlign="end" gap="300" wrap>
          <Text as="h2" variant="headingMd">
            {t("analytics.breakdown_title", "Breakdown")}
          </Text>
          <div style={{ minWidth: 200 }}>
            <Select
              label={t("analytics.breakdown_by", "Group by")}
              labelHidden
              options={DIMENSIONS.map((dimension) => ({ value: dimension, label: dimensionLabel(dimension) }))}
              value={by}
              onChange={setBy}
            />
          </div>
        </InlineStack>
        {error ? (
          <Banner tone="critical">
            <p>{t("analytics.breakdown_error", "The breakdown could not be loaded.")}</p>
          </Banner>
        ) : rows === null ? (
          <SkeletonBodyText lines={4} />
        ) : rows.length === 0 ? (
          <Text as="p" tone="subdued">
            {t("analytics.empty", "No form activity in this period yet.")}
          </Text>
        ) : (
          <DataTable
            columnContentTypes={["text", "numeric", "numeric", "numeric", "numeric"]}
            headings={[
              dimensionLabel(by),
              t("analytics.form_opens", "Form opens"),
              t("analytics.orders", "Orders"),
              t("analytics.conversion_rate", "Conversion rate"),
              t("analytics.revenue", "Revenue"),
            ]}
            rows={rows.map((row) => [
              keyLabel(by, row.key),
              (Number(row.form_opens) || 0).toLocaleString(),
              (Number(row.orders) || 0).toLocaleString(),
              `${(Number(row.conversion_rate) || 0).toFixed(1)}%`,
              money(row.revenue_cents || 0),
            ])}
          />
        )}
      </BlockStack>
    </Card>
  );
};

export default BreakdownTable;

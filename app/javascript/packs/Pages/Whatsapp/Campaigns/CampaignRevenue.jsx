import React, { useEffect, useState } from "react";
import {
  Card, BlockStack, InlineStack, InlineGrid, Text, Badge, DataTable, SkeletonBodyText, Box,
} from "@shopify/polaris";
import { api } from "./api";
import { t, formatNumber } from "./copy";

const formatMoney = (amount, currency) => {
  const value = Number(amount || 0);
  if (!currency) return formatNumber(Math.round(value));
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency, maximumFractionDigits: 0 }).format(value);
  } catch (_) {
    return `${currency} ${formatNumber(Math.round(value))}`;
  }
};

export const revenueColumnLabel = () => t("revenue_column", "Orders placed");

export const useCampaignRevenue = (campaignIds) => {
  const [byId, setById] = useState({});
  const key = [...new Set((campaignIds || []).filter(Boolean))].sort((a, b) => a - b).join(",");

  useEffect(() => {
    if (!key) {
      setById({});
      return undefined;
    }
    let cancelled = false;
    const query = key.split(",").map((id) => `ids[]=${encodeURIComponent(id)}`).join("&");
    api(`/api/whatsapp/attribution/campaigns?${query}`)
      .then((data) => {
        if (cancelled) return;
        const next = {};
        (data.campaigns || []).forEach((row) => { next[row.campaign_id] = row; });
        setById(next);
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [key]);

  return byId;
};

export const RevenueCell = ({ data }) => {
  if (!data || !data.orders) {
    return <Text as="span" tone="subdued">—</Text>;
  }
  return (
    <BlockStack gap="050">
      <Text as="span">{formatMoney(data.revenue, data.currency)}</Text>
      <Text as="span" variant="bodySm" tone="subdued">
        {t("revenue_cell_orders", "Orders placed: %{count}", { count: formatNumber(data.orders) })}
      </Text>
    </BlockStack>
  );
};

const Stat = ({ label, value }) => (
  <BlockStack gap="050">
    <Text as="span" variant="bodySm" tone="subdued">{label}</Text>
    <Text as="span" variant="headingLg">{value}</Text>
  </BlockStack>
);

export const CampaignRevenueCard = ({ campaignId }) => {
  const [data, setData] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!campaignId) return undefined;
    let cancelled = false;
    setData(null);
    setFailed(false);
    api(`/api/whatsapp/attribution/campaigns/${campaignId}`)
      .then((res) => { if (!cancelled) setData(res); })
      .catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; };
  }, [campaignId]);

  if (failed) return null;

  const days = data?.window_days || 7;
  const explainer = t(
    "revenue_explainer",
    "Orders placed within %{days} days of someone getting this message. Each order is counted once, for the last WhatsApp message the customer got before ordering. Test and cancelled orders are left out.",
    { days },
  );

  return (
    <Card>
      <BlockStack gap="400">
        <BlockStack gap="100">
          <Text as="h2" variant="headingMd">{t("revenue_title", "Orders placed")}</Text>
          <Text as="p" variant="bodySm" tone="subdued">{explainer}</Text>
        </BlockStack>

        {!data ? (
          <SkeletonBodyText lines={3} />
        ) : data.orders === 0 ? (
          <Text as="p" tone="subdued">
            {t("revenue_empty", "No orders yet. New orders usually show up here within 15 minutes.")}
          </Text>
        ) : (
          <>
            <InlineGrid columns={{ xs: 2, md: 4 }} gap="400">
              <Stat label={t("revenue_orders", "Orders placed")} value={formatNumber(data.orders)} />
              <Stat label={t("revenue_value", "Order value")} value={formatMoney(data.revenue, data.currency)} />
              <Stat label={t("revenue_aov", "Average order")} value={formatMoney(data.avg_order_value, data.currency)} />
              <Stat
                label={t("revenue_split", "Cash on delivery / prepaid")}
                value={`${formatNumber(data.cod_orders)} / ${formatNumber(data.prepaid_orders)}`}
              />
            </InlineGrid>

            {data.recent_orders?.length > 0 && (
              <BlockStack gap="200">
                <Text as="h3" variant="headingSm">{t("revenue_recent", "Latest orders")}</Text>
                <Box>
                  <DataTable
                    columnContentTypes={["text", "text", "text", "numeric", "text"]}
                    headings={[
                      t("revenue_col_order", "Order"),
                      t("revenue_col_customer", "Customer phone"),
                      t("revenue_col_payment", "Payment"),
                      t("revenue_col_total", "Total"),
                      t("revenue_col_date", "Placed on"),
                    ]}
                    rows={data.recent_orders.map((o) => [
                      o.order_name || "—",
                      o.phone_masked || "—",
                      <InlineStack key="payment">
                        <Badge tone={o.is_cod ? "attention" : "success"}>
                          {o.is_cod ? t("revenue_cod", "Cash on delivery") : t("revenue_prepaid", "Prepaid")}
                        </Badge>
                      </InlineStack>,
                      formatMoney(o.total, o.currency),
                      o.ordered_at ? new Date(o.ordered_at).toLocaleString() : "",
                    ])}
                  />
                </Box>
              </BlockStack>
            )}
          </>
        )}
      </BlockStack>
    </Card>
  );
};

export default CampaignRevenueCard;

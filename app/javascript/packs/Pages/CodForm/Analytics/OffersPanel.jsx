import React from "react";
import { Badge, BlockStack, Box, Card, DataTable, InlineGrid, InlineStack, Text } from "@shopify/polaris";
import { t } from "../i18n";

const typeLabel = (type) => {
  switch (type) {
    case "quantity":
      return t("analytics.offer_type_quantity", "Quantity offer");
    case "bump":
      return t("analytics.offer_type_bump", "Order bump");
    case "upsell":
      return t("analytics.offer_type_upsell", "Upsell after the order");
    case "downsell":
      return t("analytics.offer_type_downsell", "Downsell");
    case "threshold":
      return t("analytics.offer_type_threshold", "Free gift or shipping goal");
    default:
      return "—";
  }
};

const Group = ({ title, shown, accepted, rate, number, percent }) => (
  <Box padding="300" borderWidth="025" borderColor="border" borderRadius="200">
    <BlockStack gap="100">
      <Text as="span" variant="bodySm" tone="subdued">
        {title}
      </Text>
      <Text as="span" variant="headingLg">
        {percent(rate)}
      </Text>
      <Text as="span" variant="bodySm" tone="subdued">
        {t("analytics.offers_accepted_of", "%{accepted} accepted of %{shown} shown", { accepted: number(accepted), shown: number(shown) })}
      </Text>
    </BlockStack>
  </Box>
);

/** Offer results (ANL-3): accept rate per kind of offer, then one row per offer. */
const OffersPanel = ({ offers, rows, number, percent, money, filtered }) => {
  const totals = offers || {};
  const list = Array.isArray(rows) ? rows : [];
  const any =
    list.length > 0 || Number(totals.offer_views) > 0 || Number(totals.downsell_shown) > 0 || Number(totals.upsell_views) > 0;

  return (
    <Card>
      <BlockStack gap="400">
        <Text as="h2" variant="headingMd">
          {t("analytics.offers_title", "Offers")}
        </Text>
        {!any ? (
          <Text as="p" tone="subdued">
            {t("analytics.offers_empty", "No offer was shown to buyers in this period.")}
          </Text>
        ) : (
          <>
            <InlineGrid columns={{ xs: 1, md: 3 }} gap="300">
              <Group
                title={t("analytics.offers_group_form", "Quantity offers and order bumps")}
                shown={totals.offer_views}
                accepted={totals.offer_accepts}
                rate={totals.offer_accept_rate}
                number={number}
                percent={percent}
              />
              <Group
                title={t("analytics.offers_group_downsell", "Downsell (shown when the buyer leaves)")}
                shown={totals.downsell_shown}
                accepted={totals.downsell_accepts}
                rate={totals.downsell_accept_rate}
                number={number}
                percent={percent}
              />
              <Group
                title={t("analytics.offers_group_upsell", "Upsell after the order")}
                shown={totals.upsell_views}
                accepted={totals.upsell_accepts}
                rate={totals.upsell_accept_rate}
                number={number}
                percent={percent}
              />
            </InlineGrid>
            {list.length > 0 && (
              <DataTable
                columnContentTypes={["text", "text", "numeric", "numeric", "numeric", "numeric", "numeric"]}
                headings={[
                  t("analytics.offers_col_offer", "Offer"),
                  t("analytics.offers_col_type", "Type"),
                  t("analytics.offers_col_shown", "Shown"),
                  t("analytics.offers_col_accepted", "Accepted"),
                  t("analytics.offers_col_rate", "Accept rate"),
                  t("analytics.offers_col_orders", "Orders with it"),
                  t("analytics.offers_col_revenue", "Revenue of those orders"),
                ]}
                rows={list.map((row) => [
                  <InlineStack key={row.id} gap="200" blockAlign="center" wrap={false}>
                    <Text as="span">{row.name || t("analytics.offers_deleted", "Deleted offer #%{id}", { id: row.id })}</Text>
                    {row.name && row.status && row.status !== "active" && <Badge>{t("analytics.offers_inactive", "Not active")}</Badge>}
                  </InlineStack>,
                  typeLabel(row.offer_type),
                  number(row.views),
                  number(row.accepts),
                  Number(row.views) > 0 ? percent(row.accept_rate) : "—",
                  number(row.orders),
                  money(row.revenue_cents || 0),
                ])}
              />
            )}
            <Text as="p" variant="bodySm" tone="subdued">
              {filtered
                ? t("analytics.offers_note_filtered", "Counted about once an hour. The per-offer rows cover all countries, devices and products; the filters above apply to the three totals only.")
                : t("analytics.offers_note", "Counted about once an hour. \"Orders with it\" counts orders that included the offer, and the revenue is the full value of those orders.")}
            </Text>
          </>
        )}
      </BlockStack>
    </Card>
  );
};

export default OffersPanel;

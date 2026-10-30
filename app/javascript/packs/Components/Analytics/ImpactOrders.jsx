import React, { useContext, useEffect, useState } from "react";
import {
  Page,
  Card,
  IndexTable,
  Text,
  Badge,
  Select,
  InlineStack,
  BlockStack,
  Link,
  EmptyState,
} from "@shopify/polaris";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import { StoreContext } from "../../Context/Store";
import { navigateToPreservingParams } from "../../../utils/navigate";
import { formatDay, rangeNote, useCurrencyFormatter } from "./ImpactStats";
import { DEFAULT_DAYS, dayOptions } from "./dateRange";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`impact_orders.${key}`, { defaultValue, ...opts });

const filterOptions = () => [
  { value: "all", label: t("filter_all", "All orders") },
  { value: "converted_prepaid", label: t("filter_converted_prepaid", "COD converted to prepaid") },
  { value: "ac_recovered", label: t("filter_ac_recovered", "Abandoned carts recovered") },
  { value: "partial", label: t("filter_partial", "Partial payment") },
  { value: "cod_fee", label: t("filter_cod_fee", "COD fee collected") },
  { value: "otp_verified", label: t("filter_otp_verified", "OTP verified") },
  { value: "cod_form", label: t("filter_cod_form", "COD Form") },
  { value: "upsell", label: t("filter_upsell", "Upsell") },
  { value: "free_gift", label: t("filter_free_gift", "Free gift") },
];

const DELIVERY_TONES = {
  delivered: "success",
  in_transit: "info",
  rto: "critical",
  returned: "critical",
  refunded: "warning",
};

const readParams = () => {
  const p = new URLSearchParams(window.location.search);
  return {
    filter: p.get("filter") || "all",
    from: p.get("from") || "",
    to: p.get("to") || "",
    days: p.get("days") || DEFAULT_DAYS,
  };
};

const ImpactOrders = () => {
  const storeContext = useContext(StoreContext);
  const shop = storeContext?.shop?.[0] || null;
  const [params, setParams] = useState(readParams);
  const [cursors, setCursors] = useState([null]);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const money = useCurrencyFormatter(data?.currency);
  const cursor = cursors[cursors.length - 1];

  useEffect(() => {
    const sync = () => {
      setParams(readParams());
      setCursors([null]);
    };
    window.addEventListener("popstate", sync);
    return () => window.removeEventListener("popstate", sync);
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    Api.get("/order_stats/orders", {
      params: {
        filter: params.filter,
        from: params.from || undefined,
        to: params.to || undefined,
        days: params.from && params.to ? undefined : params.days,
        cursor: cursor || undefined,
      },
    })
      .then((resp) => !cancelled && setData(resp.data))
      .catch(() => !cancelled && setData({ orders: [] }))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [params, cursor]);

  const customRange = Boolean(params.from && params.to);
  const rangeOptions = customRange
    ? [...dayOptions(), { label: `${formatDay(params.from)} – ${formatDay(params.to)}`, value: "custom" }]
    : dayOptions();
  const changeRange = (days) => {
    if (days === "custom") return;
    navigateToPreservingParams("/usage-analytics/orders", { days, from: "", to: "" }, ["cursor"]);
  };

  const changeFilter = (filter) =>
    navigateToPreservingParams("/usage-analytics/orders", { filter }, ["cursor", "code"]);

  const highlights = (o) => {
    const items = [];
    if (o.isConvertedPrepaid) items.push(t("badge_converted", "Converted to prepaid"));
    if (o.isAcRecovered) items.push(t("badge_recovered", "Recovered cart"));
    if (o.isPartial) items.push(t("badge_partial", "Partial · %{amount} upfront", { amount: money(o.partialUpfront) }));
    if (o.codFee > 0) items.push(t("badge_cod_fee", "COD fee %{amount}", { amount: money(o.codFee) }));
    if (o.prepaidDiscount > 0) items.push(t("badge_prepaid_discount", "Prepaid discount %{amount}", { amount: money(o.prepaidDiscount) }));
    (o.discounts || []).forEach((d) => items.push(`${d.code} −${money(d.amount)}`));
    if (o.isOtpVerified) items.push(t("badge_otp", "OTP verified"));
    if (o.isCodForm) items.push(t("badge_cod_form", "COD Form"));
    if (o.upsellItems > 0) items.push(t("badge_upsell", "Upsell · %{amount}", { amount: money(o.upsellRevenue) }));
    if (o.freeGiftItems > 0) items.push(t("badge_free_gift", "Free gift · %{amount} value", { amount: money(o.freeGiftValue) }));
    return items;
  };

  const range = data?.range;
  const note = rangeNote(range);
  const orders = data?.orders || [];

  return (
    <Page fullWidth title={t("title", "Orders by feature")}>
      <BlockStack gap="400">
        <Card>
          <InlineStack gap="400" blockAlign="end" wrap>
            <Select
              label={t("filter_label", "Show")}
              options={filterOptions()}
              value={params.filter}
              onChange={changeFilter}
            />
            <Select
              label={t("range_label", "Date range")}
              options={rangeOptions}
              value={customRange ? "custom" : params.days}
              onChange={changeRange}
            />
            {range && (
              <Text variant="bodyMd" tone="subdued" as="span">
                {formatDay(range.from)} – {formatDay(range.to)} {note}
              </Text>
            )}
          </InlineStack>
        </Card>

        <Card padding="0">
          {!loading && orders.length === 0 ? (
            <EmptyState heading={t("empty", "No orders for this filter yet")} image="">
              <p>{note || t("empty_body", "Try a different filter or date range.")}</p>
            </EmptyState>
          ) : (
            <IndexTable
              resourceName={{ singular: "order", plural: "orders" }}
              itemCount={orders.length}
              selectable={false}
              loading={loading}
              headings={[
                { title: t("col_order", "Order") },
                { title: t("col_date", "Date") },
                { title: t("col_customer", "Customer") },
                { title: t("col_total", "Total"), alignment: "end" },
                { title: t("col_payment", "Payment") },
                { title: t("col_details", "Details") },
                { title: t("col_delivery", "Delivery") },
              ]}
              pagination={{
                hasPrevious: cursors.length > 1,
                onPrevious: () => setCursors((c) => c.slice(0, -1)),
                hasNext: Boolean(data?.nextCursor),
                onNext: () => setCursors((c) => [...c, data.nextCursor]),
              }}
            >
              {orders.map((o, index) => (
                <IndexTable.Row id={o.orderId} key={o.orderId} position={index}>
                  <IndexTable.Cell>
                    {o.kind === "cart" ? (
                      <Text variant="bodyMd" fontWeight="semibold" as="span">
                        {t("recovered_cart", "Recovered cart")}
                      </Text>
                    ) : (
                      <Link url={`https://${shop?.shopify_domain}/admin/orders/${o.orderId}`} external removeUnderline>
                        <Text variant="bodyMd" fontWeight="semibold" as="span">
                          {o.orderName || o.orderId}
                        </Text>
                      </Link>
                    )}
                  </IndexTable.Cell>
                  <IndexTable.Cell>{new Date(o.orderedAt).toLocaleString()}</IndexTable.Cell>
                  <IndexTable.Cell>{o.customerName || "—"}</IndexTable.Cell>
                  <IndexTable.Cell>
                    <Text as="span" alignment="end" numeric>
                      {money(o.totalPrice)}
                    </Text>
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    {o.kind === "cart" ? (
                      "—"
                    ) : (
                      <Badge tone={o.isCod ? "attention" : "success"}>
                        {o.isCod ? t("cod", "COD") : t("prepaid", "Prepaid")}
                      </Badge>
                    )}
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <InlineStack gap="100" wrap>
                      {highlights(o).map((h, i) => (
                        <Badge key={`${i}-${h}`}>{h}</Badge>
                      ))}
                    </InlineStack>
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    {o.deliveryStatus ? (
                      <Badge tone={DELIVERY_TONES[o.deliveryStatus]}>
                        {t(`delivery_${o.deliveryStatus}`, o.deliveryStatus.replace("_", " "))}
                      </Badge>
                    ) : (
                      "—"
                    )}
                  </IndexTable.Cell>
                </IndexTable.Row>
              ))}
            </IndexTable>
          )}
        </Card>
      </BlockStack>
    </Page>
  );
};

export default ImpactOrders;

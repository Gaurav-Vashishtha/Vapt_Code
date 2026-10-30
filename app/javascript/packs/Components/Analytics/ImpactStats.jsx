import React, { useEffect, useState, useCallback } from "react";
import {
  Badge,
  Card,
  Text,
  InlineGrid,
  InlineStack,
  BlockStack,
  Button,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import { ArrowUpMinor, CircleTickMinor } from "@shopify/polaris-icons";
import styled from "styled-components";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import { navigateToPreservingParams } from "../../../utils/navigate";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`impact_stats.${key}`, { defaultValue, ...opts });

const toDate = (iso) => {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
};

export const formatDay = (iso, withYear = true) =>
  iso
    ? toDate(iso).toLocaleDateString(undefined, {
        day: "numeric",
        month: "short",
        ...(withYear ? { year: "numeric" } : {}),
      })
    : "";

export const rangeNote = (range) => {
  if (!range) return null;
  if (!range.trackingSince) {
    return t("no_data_yet", "(No data yet, tracking starts with your next order)");
  }
  if (range.partial) {
    return t("data_since", "(Data since %{date})", { date: formatDay(range.trackingSince) });
  }
  return null;
};

const cardNote = (range, field) => {
  if (!range?.partialFields?.includes(field)) return null;
  if (!range.trackingSince) return t("card_no_data", "(no data yet)");
  return t("card_since", "(since %{date})", { date: formatDay(range.trackingSince, false) });
};

export const useCurrencyFormatter = (currency, maxDigits = 0) =>
  useCallback(
    (value) => {
      try {
        return new Intl.NumberFormat(undefined, {
          style: "currency",
          currency: currency || "USD",
          maximumFractionDigits: maxDigits,
        }).format(Number(value) || 0);
      } catch (e) {
        return Number(value || 0).toLocaleString();
      }
    },
    [currency, maxDigits],
  );

const COD_FEE_SOURCES = {
  widget: () => t("source_widget", "Widget"),
  order_edit: () => t("source_order_edit", "Checkout"),
  shipping_rate: () => t("source_shipping_rate", "Checkout shipping rate"),
  cod_form: () => t("source_cod_form", "COD Form"),
};

const FullHeight = styled.div`
  height: 100%;

  > .Polaris-ShadowBevel,
  > .Polaris-ShadowBevel > .Polaris-Box {
    height: 100%;
  }

  .impact-card-body {
    display: flex;
    flex-direction: column;
    height: 100%;
    gap: var(--p-space-200);
  }

  .impact-card-footer {
    margin-top: auto;
  }

  .impact-unit-list {
    display: flex;
    flex-direction: column;
    gap: var(--p-space-100);
    padding-top: var(--p-space-200);
    border-top: 1px solid var(--p-color-border-secondary);
  }

`;

const ReturnBadge = ({ multiple, size }) =>
  multiple ? (
    <Badge tone="success" icon={ArrowUpMinor} size={size}>
      {t("return_multiple", "%{multiple}x return", { multiple: multiple.toLocaleString() })}
    </Badge>
  ) : null;

const OtpBadge = ({ count, size }) =>
  count > 0 ? (
    <Badge tone="info" icon={CircleTickMinor} size={size}>
      {count === 1
        ? t("otp_badge_one", "1 order OTP verified")
        : t("otp_badge", "%{count} orders OTP verified", { count: count.toLocaleString() })}
    </Badge>
  ) : null;

const StatCard = ({ title, note, value, caption, badge, units = [], children, onView }) => (
  <FullHeight>
    <Card>
      <div className="impact-card-body">
        <InlineStack align="space-between" blockAlign="start" gap="200" wrap={false}>
          <InlineStack gap="100" blockAlign="baseline" wrap>
            <Text variant="bodyMd" tone="subdued" as="h3">
              {title}
            </Text>
            {note && (
              <Text variant="bodySm" tone="subdued" as="span">
                {note}
              </Text>
            )}
          </InlineStack>
          {badge}
        </InlineStack>
        <Text variant="heading2xl" as="p">
          {value}
        </Text>
        {caption && (
          <Text variant="bodySm" tone="subdued" as="p">
            {caption}
          </Text>
        )}
        {units.some((u) => u.value) && (
          <div className="impact-unit-list">
            {units
              .filter((u) => u.value)
              .map((u) => (
                <InlineStack key={u.label} align="space-between" gap="200">
                  <Text variant="bodySm" tone="subdued" as="span">
                    {u.label}
                  </Text>
                  <Text variant="bodySm" fontWeight="semibold" as="span">
                    {u.value}
                  </Text>
                </InlineStack>
              ))}
          </div>
        )}
        {children}
        {onView && (
          <div className="impact-card-footer">
            <Button variant="plain" onClick={onView}>
              {t("view_orders", "View orders")}
            </Button>
          </div>
        )}
      </div>
    </Card>
  </FullHeight>
);

const GRID = { xs: 1, sm: 2, lg: 3 };

const LoadingGrid = () => (
  <InlineGrid columns={GRID} gap="400">
    {[...Array(3)].map((_, i) => (
      <Card key={i}>
        <BlockStack gap="300">
          <SkeletonBodyText lines={1} />
          <SkeletonDisplayText size="medium" />
        </BlockStack>
      </Card>
    ))}
  </InlineGrid>
);

const ImpactStats = ({ days }) => {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const money = useCurrencyFormatter(data?.currency);
  const chargeMoney = useCurrencyFormatter(data?.currency, 2);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    Api.get("/order_stats/summary", { params: { days } })
      .then((resp) => {
        if (cancelled) return;
        setData(resp.data);
        setFailed(false);
      })
      .catch(() => !cancelled && setFailed(true))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [days]);

  if (loading && !data) return <LoadingGrid />;
  if (failed || !data) return null;

  const viewOrders = (filter) => () =>
    navigateToPreservingParams(
      "/usage-analytics/orders",
      { filter, days, from: "", to: "" },
      ["cursor", "code"],
    );

  const ordersCaption = (count) =>
    count === 1
      ? t("orders_count_one", "1 order")
      : t("orders_count", "%{count} orders", { count: (count || 0).toLocaleString() });

  const joinParts = (...parts) => parts.filter(Boolean).join(" · ");

  const per = (total, count, format = money) => (count > 0 && total > 0 ? format(total / count) : null);

  const noteFor = (field) => cardNote(data.range, field);
  const withNote = (text, field) => [text, noteFor(field)].filter(Boolean).join(" ");
  const { roi, store, features = {}, convertedPrepaid, acRecovered, codFee, partial, otpVerified, codForm, upsell = {}, freeGift = {} } = data;
  const counts = {
    converted_prepaid: convertedPrepaid.count,
    ac_recovered: acRecovered.count,
    partial: partial.count,
    cod_fee: codFee.count,
    cod_form: codForm.count,
    otp_verified: otpVerified.count,
    upsell: upsell.count,
    free_gift: freeGift.count,
  };
  const anyActive = Object.keys(counts).some((key) => features[key] || counts[key] > 0);
  const show = (key) => !anyActive || Boolean(features[key]) || counts[key] > 0;

  const charge = (key) => roi.breakdown?.[key] || 0;
  const generatedRows = [
    { key: "converted_prepaid", label: t("converted_prepaid", "COD converted to prepaid"), value: convertedPrepaid.value },
    { key: "ac_recovered", label: t("ac_recovered", "Abandoned carts recovered"), value: acRecovered.value },
    { key: "partial", label: t("partial", "Orders secured by partial payment"), value: partial.orderValue },
    { key: "cod_fee", label: t("cod_fee", "COD fees collected"), value: codFee.value },
    { key: "cod_form", label: t("cod_form", "Orders from COD Form"), value: codForm.value },
    { key: "upsell", label: t("upsell", "Revenue from upsells"), value: upsell.value },
    { key: "free_gift", label: t("free_gift", "Revenue from free gift orders"), value: freeGift.value },
  ].filter((row) => show(row.key));
  const chargeRows = [
    { key: "verification", label: t("charge_verification", "Order verification & notifications") },
    { key: "preOrderOtp", label: t("charge_pre_order_otp", "Pre-order OTP") },
    { key: "abandonedCart", label: t("charge_abandoned_cart", "Abandoned cart reminders") },
    { key: "prepaidFee", label: t("charge_prepaid_fee", "COD to prepaid conversion fee") },
    { key: "partialFee", label: t("charge_partial_fee", "Partial payment fee") },
  ].filter((row) => charge(row.key) > 0);
  const youPaid = t("unit_you_paid", "You paid");
  const generatedLabel = t("unit_generated", "Generated");
  const paidAndGenerated = (paid, generated) => [
    { label: youPaid, value: paid },
    { label: generatedLabel, value: generated },
  ];

  return (
    <BlockStack gap="400">
      <InlineGrid columns={GRID} gap="400">
        {show("converted_prepaid") && (
          <StatCard
            title={t("converted_prepaid", "COD converted to prepaid")}
            note={noteFor("converted_prepaid")}
            value={money(convertedPrepaid.value)}
            caption={ordersCaption(convertedPrepaid.count)}
            badge={<ReturnBadge multiple={convertedPrepaid.multiple} />}
            units={[
              { label: youPaid, value: chargeMoney(convertedPrepaid.charges || 0) },
              { label: t("unit_conversion_fee", "Conversion fee"), value: chargeMoney(convertedPrepaid.fee || 0) },
              {
                label: t("unit_prepaid_messages", "WhatsApp messages"),
                value: chargeMoney(convertedPrepaid.messageCharges || 0),
              },
              { label: generatedLabel, value: money(convertedPrepaid.value) },
            ]}
            onView={convertedPrepaid.count > 0 ? viewOrders("converted_prepaid") : null}
          />
        )}
        {show("ac_recovered") && (
          <StatCard
            title={t("ac_recovered", "Abandoned carts recovered")}
            value={money(acRecovered.value)}
            caption={joinParts(
              ordersCaption(acRecovered.count),
              t("ac_messages_sent", "%{count} reminders sent", {
                count: (acRecovered.messagesSent || 0).toLocaleString(),
              }),
            )}
            badge={<ReturnBadge multiple={acRecovered.multiple} />}
            units={paidAndGenerated(chargeMoney(charge("abandonedCart")), money(acRecovered.value))}
            onView={acRecovered.count > 0 ? viewOrders("ac_recovered") : null}
          />
        )}
        {show("partial") && (
          <StatCard
            title={t("partial", "Orders secured by partial payment")}
            value={money(partial.orderValue)}
            caption={joinParts(
              ordersCaption(partial.count),
              t("partial_upfront", "%{upfront} collected upfront", {
                upfront: withNote(money(partial.upfront), "partial_upfront"),
              }),
            )}
            badge={<ReturnBadge multiple={partial.multiple} />}
            units={[
              { label: youPaid, value: chargeMoney(charge("partialFee")) },
              {
                label: t("unit_collected_upfront", "Collected upfront"),
                value: withNote(money(partial.upfront), "partial_upfront"),
              },
              { label: generatedLabel, value: money(partial.orderValue) },
            ]}
            onView={partial.count > 0 ? viewOrders("partial") : null}
          />
        )}
        {show("cod_fee") && (
          <StatCard
            title={t("cod_fee", "COD fees collected")}
            note={noteFor("cod_fee")}
            value={money(codFee.value)}
            caption={ordersCaption(codFee.count)}
            badge={<Badge tone="success">{t("cod_fee_free", "Free feature")}</Badge>}
            units={paidAndGenerated(chargeMoney(0), money(codFee.value))}
            onView={codFee.count > 0 ? viewOrders("cod_fee") : null}
          >
            {codFee.bySource?.map((s) => (
              <InlineStack key={s.source || "other"} align="space-between">
                <Text variant="bodySm" as="span">
                  {(COD_FEE_SOURCES[s.source] || (() => s.source))()}
                </Text>
                <Text variant="bodySm" as="span">
                  {money(s.value)} · {s.count}
                </Text>
              </InlineStack>
            ))}
          </StatCard>
        )}
        {show("otp_verified") && (
          <StatCard
            title={t("otp_verified", "OTP verified orders")}
            value={(otpVerified.count || 0).toLocaleString()}
            caption={t("otp_caption", "Customers who verified their phone number before ordering")}
            units={[
              { label: youPaid, value: chargeMoney(charge("preOrderOtp")) },
              {
                label: t("unit_cost_per_verified", "Cost per verified order"),
                value: per(charge("preOrderOtp"), otpVerified.count, chargeMoney),
              },
            ]}
            onView={otpVerified.count > 0 ? viewOrders("otp_verified") : null}
          />
        )}
        {show("cod_form") && (
          <StatCard
            title={t("cod_form", "Orders from COD Form")}
            value={money(codForm.value)}
            caption={ordersCaption(codForm.count)}
            badge={<Badge tone="success">{t("cod_form_included", "Included in your plan")}</Badge>}
            units={paidAndGenerated(t("included_in_plan", "Included in plan"), money(codForm.value))}
            onView={viewOrders("cod_form")}
          />
        )}
        {show("upsell") && (
          <StatCard
            title={t("upsell", "Revenue from upsells")}
            value={money(upsell.value || 0)}
            caption={joinParts(
              ordersCaption(upsell.count),
              t("upsell_items", "%{count} items added", { count: (upsell.items || 0).toLocaleString() }),
            )}
            badge={<Badge tone="success">{t("upsell_included", "Included in your plan")}</Badge>}
            units={paidAndGenerated(t("included_in_plan", "Included in plan"), money(upsell.value || 0))}
            onView={upsell.count > 0 ? viewOrders("upsell") : null}
          />
        )}
        {show("free_gift") && (
          <StatCard
            title={t("free_gift", "Revenue from free gift orders")}
            value={money(freeGift.value || 0)}
            caption={joinParts(
              ordersCaption(freeGift.count),
              t("free_gift_items", "%{count} gifts given · %{value} gift value", {
                count: (freeGift.items || 0).toLocaleString(),
                value: money(freeGift.giftValue || 0),
              }),
            )}
            badge={<Badge tone="success">{t("free_gift_included", "Included in your plan")}</Badge>}
            units={(freeGift.byRule || []).map((rule) => ({
              label: t("free_gift_rule_unit", "%{title} · %{count} orders", { title: rule.title || rule.ruleId, count: rule.count }),
              value: money(rule.value),
            }))}
            onView={freeGift.count > 0 ? viewOrders("free_gift") : null}
          />
        )}
      </InlineGrid>

      <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="400">
        <StatCard
          title={I18n.t("summary.total_revenue")}
          value={money(store.revenue)}
          onView={store.orders > 0 ? viewOrders("all") : null}
        />
        <StatCard title={I18n.t("summary.total_orders")} value={(store.orders || 0).toLocaleString()} />
        <StatCard title={t("cod_orders", "COD orders")} value={(store.codOrders || 0).toLocaleString()} />
        <StatCard title={t("prepaid_orders", "Prepaid orders")} value={(store.prepaidOrders || 0).toLocaleString()} />
      </InlineGrid>
    </BlockStack>
  );
};

export default ImpactStats;

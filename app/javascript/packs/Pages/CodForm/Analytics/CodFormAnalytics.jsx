import React, { useCallback, useEffect, useState } from "react";
import { Banner, BlockStack, Box, Button, Card, InlineGrid, InlineStack, Page, SkeletonBodyText, Text } from "@shopify/polaris";
import { LineChart, Line, XAxis, YAxis, Tooltip as RechartsTooltip, ResponsiveContainer } from "recharts";
import { navigateTo } from "../../../../utils/navigate";
import { codFormApi, parseError } from "../api";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { FEATURES, PATHS } from "../constants";
import { formatMoney } from "../money";
import { t } from "../i18n";
import Gate, { useGate } from "../components/Gate";
import EmptyState from "../components/EmptyState";
import Filters, { defaultFilters } from "./Filters";
import FunnelChart from "./FunnelChart";
import BreakdownTable from "./BreakdownTable";
import SessionsPanel from "./SessionsPanel";
import OffersPanel from "./OffersPanel";

const Kpi = ({ label, value, previous, format }) => {
  let delta = null;
  if (previous !== undefined && previous !== null) {
    const now = Number(value) || 0;
    const before = Number(previous) || 0;
    if (before > 0) delta = ((now - before) / before) * 100;
    else if (now > 0) delta = 100;
    else delta = 0;
  }
  return (
    <Card>
      <BlockStack gap="100">
        <Text as="span" variant="bodySm" tone="subdued">
          {label}
        </Text>
        <Text as="span" variant="headingLg">
          {format(value)}
        </Text>
        {delta !== null && (
          <Text as="span" variant="bodySm" tone={delta > 0 ? "success" : delta < 0 ? "critical" : "subdued"}>
            {`${delta > 0 ? "+" : ""}${delta.toFixed(0)}% `}
            {t("analytics.vs_previous", "vs previous period")}
          </Text>
        )}
      </BlockStack>
    </Card>
  );
};

/** The "COD Form" tab of Analytics (ANL-2, ANL-4, DSH-10). */
const CodFormAnalytics = () => {
  const bootstrap = useCodFormBootstrap();
  const advanced = useGate(FEATURES.ADVANCED_ANALYTICS);
  const [filters, setFilters] = useState(defaultFilters);
  const [data, setData] = useState(null);
  const [sessions, setSessions] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState(false);

  const validRange = filters.from && filters.to && filters.from <= filters.to;

  const load = useCallback(() => {
    if (!validRange) return;
    setLoading(true);
    setError(null);
    // Sessions are read live; the funnel steps come from the hourly roll-up.
    codFormApi.analytics
      .sessions(filters)
      .then((response) => setSessions(response || {}))
      .catch(() => setSessions({}));
    codFormApi.analytics
      .show({ ...filters, compare: filters.compare && advanced.allowed })
      .then((response) => setData(response || {}))
      .catch((err) => setError(parseError(err)))
      .then(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters.from, filters.to, filters.country, filters.device, filters.product_id, filters.compare, advanced.allowed, validRange]);

  useEffect(() => {
    if (!bootstrap || !bootstrap.moduleEnabled) return undefined;
    const timer = setTimeout(load, 200);
    return () => clearTimeout(timer);
  }, [load, bootstrap]);

  const exportCsv = () => {
    setExporting(true);
    setExportError(false);
    codFormApi.analytics
      .exportCsv(filters)
      .then((blob) => {
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = `cod-form-analytics-${filters.from}-${filters.to}.csv`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(() => window.URL.revokeObjectURL(url), 1000);
      })
      .catch(() => setExportError(true))
      .then(() => setExporting(false));
  };

  if (!bootstrap) {
    return (
      <Card>
        <Box padding="400">
          <SkeletonBodyText lines={6} />
        </Box>
      </Card>
    );
  }

  if (!bootstrap.moduleEnabled) {
    return (
      <EmptyState heading={t("analytics.unavailable_title", "COD Form is not available for this store yet")}>
        <p>{t("analytics.unavailable_body", "Form analytics appear here once COD Form is available for your store.")}</p>
      </EmptyState>
    );
  }

  const currency = (data && data.currency) || bootstrap.currency;
  const money = (cents) => formatMoney(cents, data && data.currency && data.currency !== bootstrap.currency ? "" : bootstrap.moneyFormat, currency);
  const number = (value) => (Number(value) || 0).toLocaleString();
  const percent = (value) => `${(Number(value) || 0).toFixed(1)}%`;
  const previous = filters.compare && advanced.allowed && data && data.previous ? data.previous : null;
  const live = (sessions && sessions.totals) || {};
  const series = (sessions && sessions.series) || [];
  const combined = [filters.country, filters.device, filters.product_id].filter(Boolean).length > 1;

  return (
    <Page
      fullWidth
      title={t("analytics.title", "COD Form analytics")}
      primaryAction={
        advanced.allowed
          ? { content: t("analytics.export_csv", "Export CSV"), onAction: exportCsv, loading: exporting, disabled: !validRange }
          : undefined
      }
      secondaryActions={[{ content: t("analytics.open_setup", "COD Form setup"), onAction: () => navigateTo(PATHS.setup) }]}
    >
      <BlockStack gap="400">
        <Filters filters={filters} onChange={setFilters} canCompare={advanced.allowed} />
        {bootstrap.mode !== "cod_form" && (
          <Banner tone="info" action={{ content: t("analytics.open_setup", "COD Form setup"), onAction: () => navigateTo(PATHS.setup) }}>
            <p>{t("analytics.mode_off", "COD Form is off, so no new data is being collected.")}</p>
          </Banner>
        )}
        {combined && (
          <Banner tone="info">
            <p>{t("analytics.combined_note", "With more than one filter, data is available for the last 90 days only.")}</p>
          </Banner>
        )}
        {exportError && (
          <Banner tone="critical" onDismiss={() => setExportError(false)}>
            <p>{t("analytics.export_error", "The export could not be created. Try again.")}</p>
          </Banner>
        )}
        {error ? (
          <Banner tone="critical" action={{ content: t("common.retry", "Try again"), onAction: load }}>
            <p>{t("analytics.load_error", "Analytics could not be loaded.")}</p>
          </Banner>
        ) : loading && !data ? (
          <Card>
            <Box padding="400">
              <SkeletonBodyText lines={8} />
            </Box>
          </Card>
        ) : (
          <>
            <InlineGrid columns={{ xs: 2, md: 4 }} gap="400">
              <Kpi label={t("analytics.sessions", "Sessions")} value={live.sessions} previous={previous && previous.form_opens} format={number} />
              <Kpi label={t("analytics.orders", "Orders")} value={live.orders} previous={previous && previous.orders} format={number} />
              <Kpi label={t("analytics.conversion_rate", "Conversion rate")} value={live.conversion_rate} previous={previous && previous.conversion_rate} format={percent} />
              <Kpi label={t("analytics.revenue", "Revenue")} value={live.revenue_cents} previous={previous && previous.revenue_cents} format={money} />
              <Kpi label={t("analytics.aov", "Average order value")} value={live.aov_cents} previous={previous && previous.aov_cents} format={money} />
              <Kpi label={t("analytics.abandoned", "Left without ordering")} value={live.abandoned} format={number} />
              <Kpi label={t("analytics.abandonment_rate", "Abandonment rate")} value={live.abandonment_rate} format={percent} />
              <Kpi label={t("analytics.handoffs", "Sent to pay online")} value={live.handoffs} format={number} />
            </InlineGrid>

            <InlineGrid columns={{ xs: 1, lg: 2 }} gap="400">
              <Card>
                <BlockStack gap="400">
                  <Text as="h2" variant="headingMd">
                    {t("analytics.funnel", "Funnel")}
                  </Text>
                  <FunnelChart funnel={data && data.funnel} />
                  <Text as="p" variant="bodySm" tone="subdued">
                    {t("analytics.funnel_note", "Funnel steps are counted about once an hour; sessions and orders above are live.")}
                  </Text>
                </BlockStack>
              </Card>
              <Card>
                <BlockStack gap="400">
                  <Text as="h2" variant="headingMd">
                    {t("analytics.trend_sessions", "Sessions and orders per day")}
                  </Text>
                  {!series.some((day) => day.sessions > 0) ? (
                    <Text as="p" tone="subdued">
                      {t("analytics.empty", "No form activity in this period yet.")}
                    </Text>
                  ) : (
                    <div style={{ height: 260 }}>
                      <ResponsiveContainer width="100%" height="100%">
                        <LineChart data={series} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
                          <XAxis dataKey="date" tick={{ fontSize: 11 }} minTickGap={24} />
                          <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
                          <RechartsTooltip />
                          <Line type="monotone" dataKey="sessions" name={t("analytics.sessions", "Sessions")} stroke="#8c9196" dot={false} />
                          <Line type="monotone" dataKey="orders" name={t("analytics.orders", "Orders")} stroke="#007ace" strokeWidth={2} dot={false} />
                        </LineChart>
                      </ResponsiveContainer>
                    </div>
                  )}
                </BlockStack>
              </Card>
            </InlineGrid>

            <SessionsPanel data={sessions} number={number} percent={percent} money={money} />

            <OffersPanel
              offers={data && data.offers}
              rows={data && data.offer_rows}
              number={number}
              percent={percent}
              money={money}
              filtered={!!(filters.country || filters.device || filters.product_id)}
            />

            <Gate
              feature={FEATURES.ADVANCED_ANALYTICS}
              title={t("analytics.advanced_title", "Breakdowns, comparison and CSV export")}
            >
              {validRange && <BreakdownTable from={filters.from} to={filters.to} money={money} />}
            </Gate>
          </>
        )}
        <InlineStack align="end">
          <Button variant="plain" onClick={load} disabled={loading || !validRange}>
            {t("analytics.refresh", "Refresh")}
          </Button>
        </InlineStack>
      </BlockStack>
    </Page>
  );
};

export default CodFormAnalytics;

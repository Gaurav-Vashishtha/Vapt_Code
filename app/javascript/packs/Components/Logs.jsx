import React, { useContext, useState, useEffect } from "react";
import useApi from "../Hooks/useApi";
import { StoreContext } from "../Context/Store";
import {
  Card,
  Banner,
  Link,
  Text,
  Filters,
  Badge,
  Button,
  Icon,
  Tooltip,
  Pagination,
  BlockStack,
  InlineStack,
  Layout,
  Select,
  DataTable,
  Box,
  Page,
  SkeletonPage,
  SkeletonBodyText,
} from "@shopify/polaris";
import { useDebounce } from "use-debounce";
import I18n from "../i18n-lang";
import { DateTime } from "luxon";
import useAxios from "axios-hooks";

const Logs = () => {
  const {
    plan: [plan, setPlan],
    shop: [shop, setShop],
    setting: [setting, setSetting],
    tab: [tab, setTab],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;

  const [confirmingOrders, setConfirmingOrders] = useState({});
  const [resendingOrders, setResendingOrders] = useState({});

  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [days, setDays] = useState("30");
  const [debouncedQuery] = useDebounce(query, 1000);
  const [currentOrderId, setCurrentOrderId] = useState(null);

  const daysOptions = [
    { label: I18n.t("logs.days_options.1_day"), value: "1" },
    { label: I18n.t("logs.days_options.7_days"), value: "7" },
    { label: I18n.t("logs.days_options.15_days"), value: "15" },
    { label: I18n.t("logs.days_options.28_days"), value: "28" },
    { label: I18n.t("logs.days_options.29_days"), value: "29" },
    { label: I18n.t("logs.days_options.30_days"), value: "30" },
    { label: I18n.t("logs.days_options.60_days"), value: "60" },
    { label: I18n.t("logs.days_options.90_days"), value: "90" },
  ];

  const onSearch = (query) => {
    setPage(1);
    setQuery(query);
    setDays(days);
  };

  const onDaysChange = (days) => {
    setPage(1);
    setQuery(query);
    setDays(days);
  };

  const [{ data: apiData, loading: logsLoading, error }, refetchLogs] = useApi({
    url: "/twilio_logs",
    params: {
      query: debouncedQuery,
      page,
      days,
    },
  });

  const [{ data, loading: exportingCsv }, exportCsv] = useApi(
    {
      url: "/settings/export",
      method: "post",
    },
    { manual: true },
  );
  const logs = apiData?.data || [];

  const [exportBanner, setExportBanner] = useState(false);
  const [confirmBanner, setConfirmBanner] = useState(false);
  const [resendBanner, setResendBanner] = useState(false);

  const onExportCsv = () => {
    exportCsv().then((resp) => {
      if (resp.status === 200) {
        setExportBanner(true);
      }
    });
  };

  const [{ loading: confirmLoading }, onConfirm] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/confirm_order_manually`,
      method: "POST",
      data: {
        orderId: currentOrderId,
      },
    },
    { manual: true },
  );

  const [{ loading: resendLoading }, onResend] = useAxios(
    {
      url: `https://${process.env.APP_HOST}/order_confirmations/resend_message`,
      method: "POST",
      data: {
        orderId: currentOrderId,
      },
    },
    { manual: true },
  );

  // DataTable rows
  const rows = logs.map((log) => {
    const sms = log.twilioLogs;
    const errorSms = sms.filter((log) => log.status !== "SUCCESS");
    const errorStatus = errorSms.map((m) => m.status).join("\n");
    const maxRetries = setting.maxRetries == undefined ? 3 : setting.maxRetries;
    const orderId = `${log.orderId}`;

    // const onOrderConfirm = (id) => {
    //   setCurrentOrderId(id);
    //   onConfirm()
    //     .then((resp) => {
    //       if (resp.status === 200) {
    //         setConfirmBanner(true);
    //         refetchLogs();
    //       }
    //     })
    //     .catch((e) => console.error(e));
    // };

    // const onOrderResend = (id) => {
    //   setCurrentOrderId(id);
    //   onResend()
    //     .then((resp) => {
    //       if (resp.status === 200) {
    //         setResendBanner(true);
    //         refetchLogs();
    //       }
    //     })
    //     .catch((e) => console.error(e));
    // };

    const onOrderConfirm = async (id) => {
      setConfirmingOrders((prev) => ({ ...prev, [id]: true }));
      try {
        const resp = await onConfirm({ data: { orderId: id } });
        if (resp.status === 200) {
          setConfirmBanner(true);
          refetchLogs();
        }
      } catch (e) {
        console.error(e);
      } finally {
        setConfirmingOrders((prev) => ({ ...prev, [id]: false }));
      }
    };

    const onOrderResend = async (id) => {
      setResendingOrders((prev) => ({ ...prev, [id]: true }));
      try {
        const resp = await onResend({ data: { orderId: id } });
        if (resp.status === 200) {
          setResendBanner(true);
          refetchLogs();
        }
      } catch (e) {
        console.error(e);
      } finally {
        setResendingOrders((prev) => ({ ...prev, [id]: false }));
      }
    };

    const TEST_ORDER_IDS = ["1234567890", "8888888888", "9999999999"];
    const isTestOrder = log.orderId && TEST_ORDER_IDS.includes(String(log.orderId));

    return [
      // Order Number
      isTestOrder ? (
        <span key={`order-${log.id}`}>{log.orderNumber}</span>
      ) : (
        <Link
          monochrome
          external
          url={`https://${shop.shopify_domain}/admin/orders/${log.orderId}`}
          key={`order-${log.id}`}
        >
          {log.orderNumber}
        </Link>
      ),

      // Date
      DateTime.fromISO(log.createdAt).toFormat("MMM dd, h:mm a"),

      // Customer Name
      log.customerName,

      // Order Amount
      log.orderAmount,

      // Network (SMS)
      <Box key={`network-${log.id}`}>
        <Tooltip
          content={I18n.t("logs.messages_tried_tooltip", { total: sms.length, failed: errorSms.length })}
        >
          <Badge progress="complete" status="success">
            {sms.length + " " + I18n.t("logs.messages_label")}
          </Badge>
        </Tooltip>
        {errorSms.length > 0 && (
          <Tooltip content={errorStatus}>
            <Badge progress="partiallyComplete" status="critical">
              {errorSms.length + " " + I18n.t("logs.failed_label")}
            </Badge>
          </Tooltip>
        )}
      </Box>,

      // Status
      <Box key={`status-${log.id}`}>
        {log.status !== "COD-Prepaid" && (
          <Badge>
            {log.status === "COD-Verified" && "✅ COD-Verified"}
            {log.status === "Pending" && "⚠ COD-Pending"}
            {log.status === "COD-Auto-Cancelled" && "❌ COD-Auto-Cancelled"}
            {log.status === "COD-Manual-Verified" && "✅ COD-Manual-Verified"}
            {log.status === "COD-Fee-Applied" && "✅ COD-Fee-Applied"}
            {log.status === "COD-Auto-Deleted" && "❌ COD-Auto-Deleted"}
            {log.status === "COD-SKIP-CANCELLATION" &&
              "⛔ COD-Skip-Cancellation"}
            {log.status === "COD-SKIP-VERIFICATION" &&
              "⛔ COD-Skip-Verification"}
          </Badge>
        )}
        {log.status === "COD-Prepaid" && (
          <Badge>
            <span>&#9829;</span> {I18n.t("logs.cod_prepaid")}
          </Badge>
        )}
      </Box>,

      // Confirm Order Button
      <Tooltip
        key={`confirm-${log.id}`}
        content={I18n.t("logs.confirm_order_tooltip")}
      >
        <Button
          variant="secondary"
          disabled={log.status !== "Pending"}
          onClick={() => onOrderConfirm(log.orderId)}
          loading={!!confirmingOrders[log.orderId]}
        >
          {I18n.t("logs.confirm_order")}
        </Button>
      </Tooltip>,

      // Resend Message Button
      <Tooltip
        key={`resend-${log.id}`}
        content={I18n.t("logs.resend_message_tooltip")}
      >
        <Button
          variant="secondary"
          disabled={
            sms.length - errorSms.length >= maxRetries
          }
          onClick={() => onOrderResend(log.orderId)}
          loading={!!resendingOrders[log.orderId]}
        >
          {I18n.t("logs.resend_verification_message")}
        </Button>
      </Tooltip>,

      // Additional Info
      <Box key={`info-${log.id}`}>
        {log.status === "COD-SKIP-VERIFICATION" && (
          <Text as="span" variant="bodySm" tone="subdued">
            {I18n.t("logs.skip_verification_reason")}
          </Text>
        )}
        {log.isMaxTried === true && (
          <Text as="span" variant="bodySm" tone="subdued">
            {I18n.t("logs.max_retries_reached")}
          </Text>
        )}
        {log.isRetried === true && log.status === "COD-Verified" && (
          <Text as="span" variant="bodySm" tone="subdued">
            {I18n.t("logs.verified_via_retry")}
          </Text>
        )}
        {log.codFee > 0.0 && (
          <Text as="span" variant="bodySm" tone="subdued">
            {I18n.t("logs.cod_fee_applied", { fee: log.codFee, currency: shop.currency })}
          </Text>
        )}
      </Box>,
    ];
  });

  function buildMetrics(apiData, shop) {
    const safe = (n) => (n ?? 0).toLocaleString();
    const currency = shop?.currency || "";
    const currencyDisplay = currency === "INR" ? "INR" : "USD";

    return [
      {
        label: I18n.t("logs_detail.total_orders"),
        value: safe(apiData?.total),
      },
      {
        label: I18n.t("logs_detail.verified_orders"),
        value: safe(apiData?.verified),
      },
      {
        label: I18n.t("logs_detail.cod_manual_verified"),
        value: safe(apiData?.manual),
      },
      {
        label: I18n.t("logs_detail.pending_orders"),
        value: safe(apiData?.pending),
      },
      {
        label: I18n.t("logs_detail.prepaid_orders"),
        value: safe(apiData?.prepaid),
      },
      {
        label: I18n.t("logs_detail.cancelled_orders"),
        value: safe(apiData?.cancelled),
      },
    ];
  }

  function Metric({ label, value, showDivider = true }) {
    return (
      <div
        style={{
          flex: 1,
          padding: "0 1rem",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          textAlign: "center",
          minWidth: 0,
          borderLeft: showDivider ? "1px solid #00000040" : "none",
        }}
      >
        <span
          style={{
            margin: 0,
            color: "var(--p-text-subdued)",
            lineHeight: 1.25,
            wordBreak: "break-word",
          }}
        >
          {label}
        </span>
        <span style={{ fontWeight: 600, marginTop: "0.25rem" }}>{value}</span>
      </div>
    );
  }

  /**

  // function Metric({ label, value, showDivider = true }) {
  //   return (
  //     <div
  //       style={{
  //         padding: "0 1rem",
  //         display: "flex",
  //         flexDirection: "column",
  //         borderLeft: showDivider ? "1px solid #00000040" : "none",
  //       }}
  //     >
  //       <Text variant="bodySm" as="h2">
  //         {label}
  //       </Text>
  //       <Text variant="headingSm" as="span">
  //         {value}
  //       </Text>
  //     </div>
  //   );
  // }

  /*
   * Inner strip replicating Shopify Admin’s email‑metrics bar.
   */

  function EmailMetricsBarContent() {
    const metrics = buildMetrics(apiData, shop);

    return (
      <Card padding="0">
        <div
          style={{
            overflowX: "auto", // enables horizontal scroll
            padding: "0.75rem 1rem",
          }}
        >
          <div
            style={{
              display: "flex",
              flexWrap: "nowrap", // prevents wrapping
              minWidth: "600px", // or dynamically calculate if needed
              gap: "1rem",
            }}
          >
            {metrics.map((metric, index) => (
              <div key={metric.label} style={{ flexShrink: 0 }}>
                <Metric
                  label={metric.label}
                  value={metric.value}
                  showDivider={index !== 0}
                />
              </div>
            ))}
          </div>
        </div>
      </Card>
    );
  }

  // Loading skeleton – matches Order Logs: filter row + data table rows
  if (logsLoading) {
    return (
      <SkeletonPage title={I18n.t("logs.order_logs_title")} primaryAction>
        <Box paddingBlockStart="400">
          <BlockStack gap="400">
            <SkeletonBodyText lines={1} />
            <Card>
              <Box padding="400">
                <BlockStack gap="200">
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                </BlockStack>
              </Box>
            </Card>
          </BlockStack>
        </Box>
      </SkeletonPage>
    );
  }

  return (
    <>
      <Page
        title={I18n.t("logs.order_logs_title")}
        // subtitle="Statement period: May 3, 2019 to June 2, 2019"
        secondaryActions={[
          {
            content: I18n.t("admin.refresh"),
            onAction: refetchLogs,
            disabled: logsLoading,
          },
          {
            content: I18n.t("admin.export"),
            onAction: onExportCsv,
            disabled: exportingCsv,
            loading: exportingCsv,
          },
        ]}
        primaryAction={
          <Select
            label={I18n.t("logs.since_last")}
            labelHidden
            options={daysOptions}
            value={days}
            onChange={onDaysChange}
          />
        }
        // secondaryActions={[{ content: "Download", icon: ArrowDownIcon }]}
      >
        {exportBanner && (
          <Layout.Section>
            <Banner
              title={I18n.t("admin.emailed_orders")}
              status="success"
              onDismiss={() => setExportBanner(false)}
            />
          </Layout.Section>
        )}
        {confirmBanner && (
          <Banner
            title={I18n.t("logs.order_confirmed")}
            status="success"
            onDismiss={() => setConfirmBanner(false)}
          >
            <Text as="p" variant="bodyMd">
              {I18n.t("logs.refresh_data_hint")}
            </Text>
          </Banner>
        )}
        {resendBanner && (
          <Banner
            title={I18n.t("logs.sms_sent")}
            status="success"
            onDismiss={() => setResendBanner(false)}
          />
        )}

        <Box paddingBlockStart="400" style={{ overflowX: "auto" }}>
          <EmailMetricsBarContent />
          <Filters
            queryPlaceholder={I18n.t("logs.search_placeholder")}
            queryValue={query}
            filters={[]}
            appliedFilters={[]}
            onQueryChange={onSearch}
            onQueryClear={() => onSearch("")}
            onClearAll={() => onSearch("")}
          />

          <DataTable
            columnContentTypes={[
              "text", // order
              "text", // date
              "text", // customer
              "text", // total
              "text", // network
              "text", // status
              "text", // Confirm Order
              "text", // Resend Message
              "text", // Additional Info
            ]}
            headings={[
              I18n.t("admin.order"),
              I18n.t("admin.date"),
              I18n.t("admin.customer"),
              I18n.t("admin.total"),
              I18n.t("admin.network"),
              I18n.t("admin.status"),
              I18n.t("logs_detail.confirm_order"),
              I18n.t("logs_detail.resend_message"),
              I18n.t("logs_detail.additional_info"),
            ]}
            rows={rows}
            footerContent={
              logs?.length > 0 && (
                <BlockStack align="center" gap="200">
                  <Pagination
                    hasPrevious={apiData?.pagy?.page > 1}
                    previousTooltip={I18n.t("admin.prev")}
                    onPrevious={() => setPage((p) => p - 1)}
                    hasNext={apiData?.pagy?.page < apiData?.pagy?.last}
                    nextTooltip={I18n.t("admin.next")}
                    onNext={() => setPage((p) => p + 1)}
                  />
                </BlockStack>
              )
            }
          />
        </Box>
      </Page>
    </>
  );
};

export default Logs;

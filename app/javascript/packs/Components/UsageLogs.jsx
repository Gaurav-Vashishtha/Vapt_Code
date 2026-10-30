import React, { useState, useEffect, useContext, useMemo } from "react";
import { StoreContext } from "../Context/Store";
import useApi from "../Hooks/useApi";
import { useDebounce } from "use-debounce";
import { DateTime } from "luxon";
import {
  Badge,
  BlockStack,
  Box,
  Button,
  Card,
  DataTable,
  EmptyState,
  Filters,
  InlineGrid,
  InlineStack,
  Page,
  Pagination,
  Select,
  SkeletonBodyText,
  SkeletonPage,
  Text,
  Tooltip,
} from "@shopify/polaris";
import I18n from "../i18n-lang";
import { navigateTo } from "../../utils/navigate";

const UsageLogs = () => {
  const {
    shop: [shop],
  } = useContext(StoreContext);

  const [query, setQuery] = useState("");
  const [logType, setLogType] = useState("twilio_log");
  const [days, setDays] = useState("30");
  const [page, setPage] = useState(1);
  const [paymentType, setPaymentType] = useState("all"); // For COD payment logs
  const [exporting, setExporting] = useState(false);
  const [debouncedQuery] = useDebounce(query, 500);

  // Memoize API config to ensure axios-hooks detects changes properly
  const apiConfig = useMemo(() => {
    if (logType === "cod_payment_logs") {
      return {
        url: "/twilio_logs/cod_payment_logs",
        params: {
          query: debouncedQuery,
          days,
          page,
          payment_type: paymentType,
          shopId: shop?.id,
        },
      };
    }

    return {
      url: "/logs",
      params: {
        query: debouncedQuery,
        days,
        page,
        type: logType,
        shopId: shop?.id,
      },
    };
  }, [logType, debouncedQuery, days, page, paymentType, shop?.id]);

  const [{ data, loading }, refetch] = useApi(apiConfig);

  const logs = data?.data || [];
  const pagy = data?.pagy || {};
  const pagination = data?.pagy || {};
  const totalCharge = data?.totalActualCharge || 0;
  //  const totalCodFee = data?.totalCodFee || 0;
  const totalCodFee = data?.total_cod_fee || data?.totalCodFee || 0; // Add this line

  useEffect(() => {
    console.log("Full Logs API Response:", logs);
  }, [logs]);

  const handleQueryChange = (value) => {
    setQuery(value);
    setPage(1);
  };

  const handleClearAll = () => {
    setQuery("");
    setLogType("twilio_log");
    setDays("30");
    setPaymentType("all");
    setPage(1);
  };

  const handleLogTypeChange = (value) => {
    setLogType(value);
    setPage(1);
  };

  const handlePaymentTypeChange = (value) => {
    setPaymentType(value);
    setPage(1);
  };

  const renderLogTypeValue = (log) => {
    if (logType === "twilio_log") return log.verType || I18n.t("usage_logs.log_type_sms");
    if (logType === "pre_order_otp") return I18n.t("usage_logs.log_type_pre_otp");
    if (logType === "abandoned_cart") return log.notifType || I18n.t("usage_logs.log_type_ac");
    if (logType === "cod_payment_logs")
      return I18n.t("usage_logs_detail.cod_payment");
    return "-";
  };

  const renderIdentifier = (log) => {
    if (logType === "twilio_log")
      return log.orderConfirmation?.orderNumber || "-";
    if (logType === "pre_order_otp") return log.deviceId || "-";
    if (logType === "abandoned_cart") return log.checkoutId || "-";
    if (logType === "cod_payment_logs") return log.order_number || "-";
    return "-";
  };

  const renderDate = (createdAt) => {
    if (!createdAt || typeof createdAt !== "string")
      return I18n.t("usage_logs_detail.not_found");
    const dt = DateTime.fromISO(createdAt);
    return dt.isValid
      ? dt.setZone("Asia/Kolkata").toFormat("dd MMM, hh:mm a")
      : I18n.t("usage_logs_detail.invalid_date");
  };

  const renderStatus = (status) => {
    const isSuccess =
      status === true ||
      status === "true" ||
      status === "SUCCESS" ||
      status === "success";
    const color = isSuccess ? "green" : "red";
    const text = isSuccess
      ? I18n.t("usage_logs_detail.success")
      : I18n.t("usage_logs_detail.failed");
    return <span style={{ color }}>{text}</span>;
  };

  const VALID_TONES = [
    "success",
    "info",
    "warning",
    "critical",
    "attention",
    "caution",
    "neutral",
    "subdued",
    "new",
  ];

  const StatusBadge = ({ status }) => {
    console.log("status", status);

    const key = (() => {
      if (status === true) return "success";
      if (status === false) return "failed";
      return String(status).toLowerCase();
    })();

    const statusMap = {
      success: { tone: "success", label: I18n.t("usage_logs_detail.success") },
      failed: { tone: "critical", label: I18n.t("usage_logs_detail.failed") },
      pending: { tone: "warning", label: I18n.t("usage_logs.pending") },
      "cod-verified": {
        tone: "success",
        label: I18n.t("usage_logs_detail.cod_verified"),
      },
      "cod-prepaid": {
        tone: "info",
        label: I18n.t("usage_logs_detail.cod_prepaid"),
      },
      "cod-partial-payment-received": {
        tone: "attention",
        label: I18n.t("usage_logs_detail.partial_payment"),
      },
    };

    const { tone, label } = statusMap[key] || {
      tone: VALID_TONES.includes(key) ? key : "attention",
      label: status,
    };

    // Truncate long labels to prevent overflow
    const maxLength = 30;
    const displayLabel =
      typeof label === "string" && label.length > maxLength
        ? label.substring(0, maxLength) + "..."
        : label;

    const badgeContent =
      label !== displayLabel ? (
        <Tooltip content={String(label)}>
          <span>{displayLabel}</span>
        </Tooltip>
      ) : (
        label
      );

    return <Badge tone={tone}>{badgeContent}</Badge>;
  };

  function LogsDataTable({ logs }) {
    // Different column configurations based on log type
    const getTableConfig = () => {
      if (logType === "cod_payment_logs") {
        return {
          headings: [
            I18n.t("usage_logs_detail.date"),
            I18n.t("usage_logs_detail.order_number"),
            I18n.t("usage_logs_detail.customer_name"),
            I18n.t("usage_logs_detail.order_total"),
            I18n.t("usage_logs_detail.cod_fee"),
            I18n.t("usage_logs_detail.status"),
          ],
          rows: logs.map((log) => [
            renderDate(log.createdAt),
            log.orderNumber || "-",
            log.customerName || "-",
            <Text variation="subdued" key={`total-${log.id}`}>
              {parseFloat(log.orderTotal || 0).toFixed(2)}
            </Text>,
            <Text variation="subdued" key={`cod-${log.id}`}>
              ${parseFloat(log.codFee || 0).toFixed(2)}
            </Text>,
            <StatusBadge status={log.status} key={log.id} />,
          ]),
          columnContentTypes: [
            "text",
            "text",
            "text",
            "numeric",
            "numeric",
            "text",
          ],
        };
      }

      // Default configuration for other log types
      return {
        headings: [
          I18n.t("usage_logs.headings.date"),
          I18n.t("usage_logs.headings.identifier"),
          I18n.t("usage_logs.headings.phone"),
          I18n.t("usage_logs.headings.type"),
          I18n.t("usage_logs.headings.status"),
          I18n.t("usage_logs.headings.charge"),
        ],
        rows: logs.map((log) => [
          renderDate(log.createdAt),
          renderIdentifier(log),
          log.phone || log.customerNumber || "-",
          renderLogTypeValue(log),
          <StatusBadge status={log.status} key={log.id} />,
          <Text variation="subdued" key={`charge-${log.id}`}>
            ${parseFloat(log.actualChargeApplied || 0).toFixed(4)}
          </Text>,
        ]),
        columnContentTypes: ["text", "text", "text", "text", "text", "numeric"],
      };
    };

    const { headings, rows, columnContentTypes } = getTableConfig();

    return (
      <DataTable
        columnContentTypes={columnContentTypes}
        headings={headings}
        rows={rows}
      />
    );
  }

  const handleDaysChange = (value) => {
    setDays(value);
    setPage(1);
  };

  const handleExport = async () => {
    if (exporting) return;

    const params = new URLSearchParams();
    if (debouncedQuery) params.set("query", debouncedQuery);
    if (days) params.set("days", days);
    if (shop?.id) params.set("shopId", shop.id);

    let path;
    if (logType === "cod_payment_logs") {
      params.set("payment_type", paymentType);
      path = "/twilio_logs/cod_payment_logs_export";
    } else {
      params.set("type", logType);
      path = "/logs/export";
    }

    setExporting(true);
    try {
      const token = await shopify.idToken();
      const response = await fetch(
        `https://${process.env.APP_HOST}${path}?${params.toString()}`,
        {
          method: "GET",
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
      );
      if (!response.ok) throw new Error("Export failed");

      const blob = await response.blob();
      const cd = response.headers.get("content-disposition") || "";
      const filenameMatch = cd.match(/filename="?([^"]+)"?/i);
      const filename =
        filenameMatch?.[1] ||
        `usage-logs-${logType}-${DateTime.now().toFormat("yyyyLLdd-HHmmss")}.csv`;

      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error("Usage logs export failed:", e);
      shopify?.toast?.show(I18n.t("admin.something_went_wrong"), {
        isError: true,
      });
    } finally {
      setExporting(false);
    }
  };

  const getPrimaryActionOptions = () => {
    const baseOptions = [
      {
        label: I18n.t("usage_logs.order_notification_charges"),
        value: "twilio_log",
      },
      {
        label: I18n.t("usage_logs.pre_order_otp_charges"),
        value: "pre_order_otp",
      },
      {
        label: I18n.t("usage_logs.abandoned_cart_charges"),
        value: "abandoned_cart",
      },
      {
        label: I18n.t("usage_logs.transaction_charges"),
        value: "cod_payment_logs",
      },
    ];

    return baseOptions;
  };

  const renderPaymentTypeFilter = () => {
    if (logType === "cod_payment_logs") {
      return (
        <Select
          label={I18n.t("usage_logs.order_type")}
          options={[
            { label: I18n.t("usage_logs.all_payments"), value: "all" },
            {
              label: I18n.t("usage_logs.partial_payments"),
              value: "partial",
            },
            { label: I18n.t("usage_logs.cod_to_prepaid"), value: "prepaid" },
          ]}
          value={paymentType}
          onChange={handlePaymentTypeChange}
        />
      );
    }
    return null;
  };

  // Loading skeleton – matches Usage Logs: filter card (selects + filter) + table card
  if (loading) {
    return (
      <SkeletonPage title={I18n.t("usage_logs.usage_charges_title")} primaryAction>
        <BlockStack gap="300">
          <Card>
            <Box padding="300">
              <BlockStack gap="200">
                <InlineGrid columns={{ xs: "1fr", sm: "1fr 1fr" }} gap="200">
                  <SkeletonBodyText lines={1} />
                  <SkeletonBodyText lines={1} />
                </InlineGrid>
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
              </BlockStack>
            </Box>
          </Card>
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
              </BlockStack>
            </Box>
          </Card>
        </BlockStack>
      </SkeletonPage>
    );
  }

  return (
    <Page
      backAction={{
        content: I18n.t("usage_logs.back_to_summary"),
        onAction: () => navigateTo("/"),
      }}
      title={I18n.t("usage_logs.usage_charges_title")}
      secondaryActions={
        <InlineStack gap="200" wrap={false} blockAlign="center">
          <Button
            variant="plain"
            onClick={handleExport}
            loading={exporting}
            disabled={loading || exporting || logs.length === 0}
          >
            {I18n.t("admin.export")}
          </Button>
        </InlineStack>
      }
      // subtitle={
      //   logType === "cod_payment_logs"
      //     ? `Showing COD payment records`
      //     : `Total Charge: $${totalCharge.toFixed(4)}`
      // }
    >
      <BlockStack gap="300">
        <Card>
          <Box padding="300">
            <BlockStack gap="200">
              <InlineGrid
                columns={{
                  xs: "1fr",
                  sm: "1fr 1fr",
                  md:
                    logType === "cod_payment_logs" ? "1fr 1fr 1fr" : "1fr 1fr",
                }}
                gap="200"
              >
                <Select
                  label={I18n.t("message_logs.days_label")}
                  options={[
                    { label: I18n.t("usage_logs.days_options.1_day"), value: "1" },
                    { label: I18n.t("usage_logs.days_options.7_days"), value: "7" },
                    { label: I18n.t("usage_logs.days_options.15_days"), value: "15" },
                    { label: I18n.t("usage_logs.days_options.30_days"), value: "30" },
                    { label: I18n.t("usage_logs.days_options.60_days"), value: "60" },
                    { label: I18n.t("usage_logs.days_options.180_days"), value: "180" },
                    { label: I18n.t("usage_logs.days_options.365_days"), value: "365" },
                  ]}
                  value={days}
                  onChange={handleDaysChange}
                />
                <Select
                  label={I18n.t("message_logs.type_label")}
                  options={getPrimaryActionOptions()}
                  value={logType}
                  onChange={handleLogTypeChange}
                />
                {renderPaymentTypeFilter()}
              </InlineGrid>

              {logType !== "cod_payment_logs" && (
                <Text tone="subdued" variant="bodySm" as="p">
                  {I18n.t("usage_logs.charge_data_available")}
                </Text>
              )}

              {logType !== "cod_payment_logs" && (
                <Text as="p" variant="headingSm" fontWeight="semibold">
                  {I18n.t("usage_logs.total_charge", {
                    amount: totalCharge.toFixed(4),
                  })}
                </Text>
              )}

              {logType === "cod_payment_logs" && (
                <Text as="p" variant="headingSm" fontWeight="semibold">
                  {I18n.t("usage_logs.total_transaction_fees", {
                    amount: totalCodFee,
                  })}
                </Text>
              )}

              <Box>
                <Filters
                  queryPlaceholder={
                    logType === "cod_payment_logs"
                      ? I18n.t("usage_logs.search_by_order_details")
                      : I18n.t("usage_logs.search_by_number_or_id")
                  }
                  queryValue={query}
                  filters={[]}
                  appliedFilters={[]}
                  onQueryChange={handleQueryChange}
                  onQueryClear={() => handleQueryChange("")}
                  onClearAll={() => handleQueryChange("")}
                />
              </Box>
            </BlockStack>
          </Box>
        </Card>

        {/* Table */}
        <Card>
          {logs.length === 0 ? (
            <EmptyState
              heading={I18n.t("message_logs.no_results_title")}
              children={
                <Text as="p">
                  {I18n.t("message_logs.no_results_description")}
                </Text>
              }
            />
          ) : (
            <div style={{ overflowX: "auto" }}>
              <LogsDataTable logs={logs} />
            </div>
          )}
        </Card>

        {/* Pagination */}
        {logs.length > 0 && (
          <BlockStack gap="200" align="center">
            <Pagination
              hasPrevious={pagination.page > 1}
              onPrevious={() => setPage((prev) => prev - 1)}
              hasNext={pagination.page < pagination.pages}
              onNext={() => setPage((prev) => prev + 1)}
            />
          </BlockStack>
        )}
      </BlockStack>
    </Page>
  );
};

export default UsageLogs;

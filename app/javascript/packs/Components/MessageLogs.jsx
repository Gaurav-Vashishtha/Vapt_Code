import React, { useContext, useState } from "react";
import {
  Card,
  TextField,
  Button,
  Select,
  Pagination,
  Banner,
  InlineStack,
  InlineGrid,
  BlockStack,
  Box,
  EmptyState,
  Text,
  DataTable,
  Page,
  AppProvider,
  Link,
  Filters,
  Icon,
  SkeletonBodyText,
  SkeletonPage,
} from "@shopify/polaris";
import { RefreshMajor, ExportMinor } from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import { useDebounce } from "use-debounce";
import I18n from "../i18n-lang";
import { DateTime } from "luxon";
import useApi from "../Hooks/useApi";
import enTranslations from "@shopify/polaris/locales/en.json";
import { navigateTo } from "../../utils/navigate";

const daysOptions = [
  { get label() {
      return I18n.t("message_logs.days_options.1_day");
    }, value: "1" },
  { get label() {
      return I18n.t("message_logs.days_options.7_days");
    }, value: "7" },
  { get label() {
      return I18n.t("message_logs.days_options.15_days");
    }, value: "15" },
  { get label() {
      return I18n.t("message_logs.days_options.30_days");
    }, value: "30" },
  { get label() {
      return I18n.t("message_logs.days_options.60_days");
    }, value: "60" },
  { get label() {
      return I18n.t("message_logs.days_options.90_days");
    }, value: "90" },
];

const typeOptions = [
  { get label() {
      return `${I18n.t("message_logs.type_options.all")} (Type)`;
    }, value: "all" },
  { get label() {
      return I18n.t("message_logs.type_options.otp");
    }, value: "otp" },
  { get label() {
      return I18n.t("message_logs.type_options.conf_sms");
    }, value: "conf_sms" },
  {
    get label() {
      return I18n.t("message_logs.type_options.fulfill_sms");
    },
    value: "fulfill_sms",
  },
  {
    get label() {
      return I18n.t("message_logs.type_options.pre_order_otp");
    },
    value: "pre_order_otp",
  },
  {
    get label() {
      return I18n.t("message_logs.type_options.abandoned_checkout");
    },
    value: "abandoned_checkout",
  },
];

const checkoutStatusOptions = [
  { get label() {
      return I18n.t("message_logs_missing.all_checkout_status");
    }, value: "all" },
  { get label() {
      return I18n.t("message_logs.in_progress");
    }, value: "IN_PROGRESS" },
  { get label() {
      return I18n.t("message_logs.order_placed");
    }, value: "ORDER_PLACED" },
  { get label() {
      return I18n.t("message_logs.abandonedcheckout");
    }, value: "AbandonedCheckout" },
];

const MessageLogs = () => {
  const {
    plan: [plan, setPlan],
    shop: [shop, setShop],
    setting: [setting, setSetting],
    tab: [tab, setTab],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [days, setDays] = useState("1");
  const [type, setType] = useState("all");
  const [checkoutStatus, setCheckoutStatus] = useState("all");
  const [debouncedQuery] = useDebounce(query, 500);

  const [{ data: apiData, loading }, refetch] = useApi({
    url: "/twilio_logs/message_logs",
    params: {
      query: debouncedQuery,
      page,
      days,
      type,
      order_status: checkoutStatus,
    },
  });

  // Fix: Initialize useApi for export without auto-triggering
  const [{ loading: exportingCsv }, exportCsv] = useApi(
    {
      url: "/settings/export_message_logs_csv",
      method: "post",
      data: {
        setting: setting,
        days: days,
      },
    },
    { manual: true }, // This prevents auto-execution on component mount
  );

  const [exportBanner, setExportBanner] = useState(false);
  const [activeBanner, setActiveBanner] = useState(false);

  const openShopifyAdminOrder = (orderId) => {
    if (!orderId) return;
    try {
      const pathname = window.location.pathname || "";
      const match = pathname.match(/\/store\/([^/]+)\//);
      const storeHandleFromPath = match?.[1];
      const storeHandleFromDomain = shop?.shopify_domain
        ? String(shop.shopify_domain).split(".")[0]
        : null;
      const storeHandle = storeHandleFromPath || storeHandleFromDomain;
      if (!storeHandle) return;
      const url = `https://admin.shopify.com/store/${storeHandle}/orders/${orderId}`;
      window.open(url, "_top");
    } catch (_e) {}
  };

  const onExportCsv = () => {
    exportCsv().then((resp) => {
      if (resp.status === 200) {
        setExportBanner(true);
      }
    });
  };

  const logs = apiData?.data || [];
  const pagination = apiData?.pagy || {};
  const emptyValue = I18n.t("message_logs.empty_value");

  const handleSearchChange = (value) => {
    setQuery(value);
    setPage(1);
  };

  const handleTypeChange = (value) => {
    setType(value);
    setPage(1);
  };

  const handleCheckoutStatusChange = (value) => {
    setCheckoutStatus(value);
    setPage(1);
  };

  const handleDaysChange = (value) => {
    setDays(value);
    setPage(1);
  };

  const TEST_ORDER_IDS = ["1234567890", "8888888888", "9999999999"];

  function MessageLogsTable({ logs = [], navigateTo }) {
    const rows = logs.map((log) => {
      const isTestOrder = log?.orderId && TEST_ORDER_IDS.includes(String(log.orderId));
      const orderIdCell = log?.orderId ? (
        isTestOrder ? (
          <span>{log.orderId}</span>
        ) : (
          <Link
            monochrome
            url="#"
            onClick={(e) => {
              e.preventDefault();
              openShopifyAdminOrder(log.orderId);
            }}
          >
            {log.orderId}
          </Link>
        )
      ) : (
        <span style={{ color: "rgba(0,0,0,0.4)" }}>—</span>
      );

      const statusCell = log.verType
        ? `${log.status} (${log.verType})`
        : `${
            log.status === true
              ? I18n.t("message_logs.status_success")
              : log.status
          } ${
            log.status === true
              ? I18n.t("message_logs.status_pre_order")
              : I18n.t("message_logs.status_abandoned")
          }`;

      const fullProductText = Array.isArray(log.cartDetails)
        ? log.cartDetails
            .map((item) => {
              if (typeof item === "string" && item.includes("=>")) {
                const parts = item.split("=>");
                return parts[1]?.trim();
              } else if (typeof item === "object" && item.title) {
                const qty = item.quantity || 1;
                const price = item.price ? Math.round(item.price / 100) : null;
                return `${qty} × ${item.title}${price ? ` – ₹${price}` : ""}`;
              }
              return null;
            })
            .filter(Boolean)
            .join(", ")
        : "";

      const shortProductText =
        fullProductText.split(", ").slice(0, 2).join(", ") +
        (fullProductText.split(", ").length > 2 ? "..." : "");

      return [
        orderIdCell,
        DateTime.fromISO(log.createdAt).toFormat("MMM dd, h:mm a"),
        log.customerNumber,
        log.countryCode,
        fullProductText ? (
          <span title={fullProductText}>{shortProductText}</span>
        ) : (
          <span style={{ color: "rgba(0,0,0,0.4)" }}>{emptyValue}</span>
        ),
        log.orderStatus || emptyValue,
        log.verificationStatus || emptyValue,
        statusCell,
      ];
    });

    return (
      <AppProvider i18n={enTranslations}>
        <DataTable
          columnContentTypes={[
            "text",
            "text",
            "text",
            "text",
            "text",
            "text",
            "text",
            "text",
          ]}
          headings={[
            I18n.t("message_logs_missing.shopify_order_id"),
            I18n.t("message_logs_missing.sent_date_time"),
            I18n.t("admin.phone_number"),
            I18n.t("admin.country_header"),
            I18n.t("admin.product_details"),
            I18n.t("message_logs.checkout_status"),
            I18n.t("message_logs_missing.verification_status"),
            I18n.t("admin.status"),
          ]}
          rows={rows}
        />
      </AppProvider>
    );
  }

  // Applied filters for display
  const appliedFilters = [];
  if (type !== "all") {
    appliedFilters.push({
      key: "type",
      label: I18n.t("message_logs.type_label"),
      value: typeOptions.find((opt) => opt.value === type)?.label || type,
      onRemove: () => setType("all"),
    });
  }
  if (
    checkoutStatus !== "all" &&
    (type === "all" || type === "pre_order_otp")
  ) {
    appliedFilters.push({
      key: "checkout_status",
      label: I18n.t("message_logs.checkout_status"),
      value:
        checkoutStatusOptions.find((opt) => opt.value === checkoutStatus)
          ?.label || checkoutStatus,
      onRemove: () => setCheckoutStatus("all"),
    });
  }

  // Loading skeleton – show only on initial load.
  // During searching/filtering/pagination keep the UI mounted so the search box
  // doesn't jump/disappear while requests are in-flight.
  const isInitialLoad = loading && !apiData;
  if (isInitialLoad) {
    return (
      <SkeletonPage title={I18n.t("message_logs.message_logs_title")} primaryAction>
        <BlockStack gap="400">
          <Card>
            <Box padding="400">
              <InlineGrid columns={{ xs: "1fr", sm: "1fr 1fr", md: "1fr 1fr 1fr" }} gap="300">
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
              </InlineGrid>
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
      title={I18n.t("message_logs.message_logs_title")}
      secondaryActions={[
        {
          content: I18n.t("message_logs.refresh_button"),
          onAction: refetch,
          disabled: loading,
        },
        {
          content: I18n.t("message_logs.export_button"),
          onAction: onExportCsv,
          disabled: exportingCsv,
          loading: exportingCsv,
        },
      ]}
    >
      <BlockStack gap="400">
        {activeBanner && (
          <Banner
            title={I18n.t("admin.message_sent")}
            status="success"
            onDismiss={() => setActiveBanner(false)}
          />
        )}
        {exportBanner && (
          <Banner
            title={I18n.t("admin.emailed_orders")}
            status="success"
            onDismiss={() => setExportBanner(false)}
          />
        )}

        <Card>
          <Box padding="400">
            <InlineGrid
              columns={{
                xs: "1fr",
                sm: "1fr 1fr",
                md: "1fr 1fr 1fr",
              }}
              gap="300"
            >
              <Select
                label={I18n.t("message_logs.type_label")}
                options={typeOptions}
                value={type}
                onChange={handleTypeChange}
              />
              <Select
                label={I18n.t("message_logs.checkout_status")}
                options={checkoutStatusOptions}
                value={checkoutStatus}
                onChange={handleCheckoutStatusChange}
                disabled={!(type === "all" || type === "pre_order_otp")}
              />
              <Select
                label={I18n.t("message_logs.days_label")}
                options={daysOptions}
                value={days}
                onChange={handleDaysChange}
              />
            </InlineGrid>
          </Box>
        </Card>

        <Card>
          <Box padding="400">
            <Filters
              queryPlaceholder={I18n.t("message_logs.search_label")}
              queryValue={query}
              filters={[]}
              appliedFilters={appliedFilters}
              onQueryChange={handleSearchChange}
              onQueryClear={() => handleSearchChange("")}
              onClearAll={() => {
                handleSearchChange("");
                setType("all");
                setCheckoutStatus("all");
              }}
            />
          </Box>

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
            <MessageLogsTable logs={logs} navigateTo={navigateTo} />
          )}

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
        </Card>
      </BlockStack>
    </Page>
  );
};

export default MessageLogs;

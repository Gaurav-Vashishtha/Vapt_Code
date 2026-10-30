import React, { useContext, useMemo, useState } from "react";
import {
  BlockStack,
  Box,
  Button,
  Card,
  DataTable,
  EmptyState,
  Icon,
  InlineGrid,
  InlineStack,
  Link,
  Modal,
  Page,
  Pagination,
  Select,
  TextField,
  Text,
  Tooltip,
} from "@shopify/polaris";
import { SearchMinor } from "@shopify/polaris-icons";
import { DateTime } from "luxon";
import { useDebounce } from "use-debounce";
import { useAppBridge } from "@shopify/app-bridge-react";
import useApi from "../Hooks/useApi";
import I18n from "../i18n-lang";
import { navigateTo } from "../../utils/navigate";
import { StoreContext } from "../Context/Store";
import { hasNoChargeId } from "../utils/shopUtils";

const dayOptions = [
  { get label() {
      return I18n.t("cod_king_abandoned_carts.1_day");
    }, value: "1" },
  { get label() {
      return I18n.t("cod_king_abandoned_carts.7_days");
    }, value: "7" },
  { get label() {
      return I18n.t("cod_king_abandoned_carts.15_days");
    }, value: "15" },
  { get label() {
      return I18n.t("cod_king_abandoned_carts.30_days");
    }, value: "30" },
  { get label() {
      return I18n.t("cod_king_abandoned_carts.60_days");
    }, value: "60" },
  { get label() {
      return I18n.t("cod_king_abandoned_carts.90_days");
    }, value: "90" },
  { get label() {
      return I18n.t("cod_king_abandoned_carts.custom");
    }, value: "custom" },
];

function formatCartDetails(cartDetails) {
  if (!Array.isArray(cartDetails) || cartDetails.length === 0) return "-";

  const items = cartDetails
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const qty = Number(item.quantity || 1);
      const title = String(item.title || "").trim();
      const price = Number(item.price || 0);
      const priceLabel = Number.isFinite(price) && price > 0 ? ` - ${price}` : "";
      if (!title) return null;
      return `${qty} x ${title}${priceLabel}`;
    })
    .filter(Boolean);

  return items.length > 0 ? items.join(" | ") : "-";
}

function CartDetailsCell({ cartDetails }) {
  const full = formatCartDetails(cartDetails);
  if (full === "-") {
    return <span>-</span>;
  }

  const truncated = (
    <div
      style={{
        display: "block",
        maxWidth: 280,
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
      }}
    >
      {full}
    </div>
  );

  return (
    <Tooltip
      content={full}
      preferredPosition="below"
      width="wide"
      activatorWrapper="div"
      hoverDelay={200}
    >
      {truncated}
    </Tooltip>
  );
}

function buildShopifyPermalink(cartDetails, shopDomain) {
  if (!shopDomain || !Array.isArray(cartDetails)) return "";
  const lineItemsString = cartDetails
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const variantId = item.variant_id || item.variantId;
      const qty = Number(item.quantity || 1);
      if (!variantId) return null;
      return `${variantId}:${qty > 0 ? qty : 1}`;
    })
    .filter(Boolean);

  if (lineItemsString.length === 0) return "";
  return `https://${shopDomain}/cart/${lineItemsString.join(",")}?storefront=true`;
}

const CodKingAbandonedCarts = () => {
  const shopify = useAppBridge();
  const {
    shop: [shop],
    plan: [plan],
    setting: [setting],
  } = useContext(StoreContext);
  const [query, setQuery] = useState("");
  const [days, setDays] = useState("7");
  const [page, setPage] = useState(1);
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [detailLog, setDetailLog] = useState(null);
  const [copiedId, setCopiedId] = useState(null);
  const [debouncedQuery] = useDebounce(query, 500);

  const isPaidPlan =
    plan?.name?.toLowerCase() !== "free" && !hasNoChargeId(shop);

  const isPreOrderOtpEnabled =
    setting?.enablePreOrderOtp === true || setting?.enable_pre_order_otp === true;

  const [{ data, loading }, refetch] = useApi({
    url: "/twilio_logs/cod_king_abandoned_carts",
    params: {
      query: debouncedQuery,
      days,
      start_date: days === "custom" ? startDate : undefined,
      end_date: days === "custom" ? endDate : undefined,
      page,
    },
  });

  const logs = data?.data || [];
  const currentDetailLog = useMemo(() => {
    if (!detailLog) return null;
    return logs.find((l) => l.id === detailLog.id) || detailLog;
  }, [logs, detailLog]);

  const handleCopyLink = async (log) => {
    if (!isPaidPlan) return;
    const permalink = buildShopifyPermalink(log.cartDetails, shop?.shopify_domain);
    if (!permalink) return;
    try {
      await navigator.clipboard.writeText(permalink);
      setCopiedId(log.id);
      setTimeout(() => {
        setCopiedId((prev) => (prev === log.id ? null : prev));
      }, 1500);
    } catch (_e) {
      // noop
    }
  };

  const rows = logs.map((log) => [
    log.customerNumber || "-",
    log.countryCode || "-",
    log.createdAt ? DateTime.fromISO(log.createdAt).toFormat("MMM dd, h:mm a") : "-",
    log.verificationStatus || "-",
    <CartDetailsCell key={`cart-${log.id}`} cartDetails={log.cartDetails} />,
    <div
      key={`actions-${log.id}`}
      style={{
        display: "flex",
        flexDirection: "row",
        flexWrap: "nowrap",
        gap: "8px",
        justifyContent: "flex-end",
        alignItems: "center",
        whiteSpace: "nowrap",
        minWidth: "max-content",
      }}
    >
      <Button
        size="slim"
        variant="secondary"
        onClick={() => handleCopyLink(log)}
        disabled={!isPaidPlan}
      >
        {copiedId === log.id ? "Copied" : "Copy link"}
      </Button>
      <Button
        size="slim"
        variant="secondary"
        onClick={() => setDetailLog(log)}
        disabled={!isPaidPlan}
      >
        {I18n.t("cod_king_abandoned_carts.view_details")}
      </Button>
    </div>,
  ]);

  const pagination = data?.pagy || {};
  const handleExport = async () => {
    if (!isPaidPlan) return;
    const params = new URLSearchParams();
    if (debouncedQuery) params.set("query", debouncedQuery);
    if (days) params.set("days", days);
    if (days === "custom" && startDate && endDate) {
      params.set("start_date", startDate);
      params.set("end_date", endDate);
    }
    try {
      const token = await shopify.idToken();
      const response = await fetch(
        `https://${process.env.APP_HOST}/twilio_logs/cod_king_abandoned_carts_export?${params.toString()}`,
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
        `cod-king-abandoned-carts-${DateTime.now().toFormat("yyyyLLdd-HHmmss")}.csv`;

      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (_e) {
      // noop
    }
  };

  return (
    <Page
      title={I18n.t("cod_king_abandoned_carts.cod_king_abandoned_carts")}
      subtitle={I18n.t("cod_king_abandoned_carts.captured_from_the_cod_king_widget")}
      backAction={{
        content: I18n.t("message_logs.back_to_summary"),
        onAction: () => navigateTo("/"),
      }}
      secondaryActions={
        <InlineStack gap="200" wrap={false} blockAlign="center">
          <Button variant="plain" onClick={refetch} disabled={loading}>
            {I18n.t("message_logs.refresh_button")}
          </Button>
          <Button
            variant="plain"
            onClick={handleExport}
            disabled={
              !isPaidPlan ||
              loading ||
              (days === "custom" && (!startDate || !endDate))
            }
          >
            {I18n.t("admin.export")}
          </Button>
        </InlineStack>
      }
    >
      <BlockStack gap="400">
        <div style={{ position: "relative" }}>
          <Card>
            <Box padding="400">
              <InlineGrid
                columns={{ xs: "1fr", md: "minmax(220px, 1fr) auto" }}
                gap="400"
                alignItems="start"
              >
                <Box minWidth="0">
                  <TextField
                    label={I18n.t("message_logs.search_label")}
                    placeholder={I18n.t("message_logs.search_by_phone_placeholder")}
                    value={query}
                    onChange={(value) => {
                      setQuery(value);
                      setPage(1);
                    }}
                    prefix={<Icon source={SearchMinor} tone="base" />}
                    clearButton
                    onClearButtonClick={() => {
                      setQuery("");
                      setPage(1);
                    }}
                    autoComplete="off"
                    disabled={!isPaidPlan}
                  />
                </Box>
                <BlockStack gap="200">
                  <InlineStack gap="300" wrap blockAlign="start">
                    <Select
                      label={I18n.t("message_logs.days_label")}
                      options={dayOptions}
                      value={days}
                      onChange={(value) => {
                        setDays(value);
                        setPage(1);
                      }}
                      disabled={!isPaidPlan}
                    />
                    {days === "custom" ? (
                      <InlineStack gap="300" wrap>
                        <TextField
                          label={I18n.t("cod_king_abandoned_carts.start_date")}
                          type="date"
                          value={startDate}
                          onChange={(value) => {
                            setStartDate(value);
                            setPage(1);
                          }}
                          autoComplete="off"
                          disabled={!isPaidPlan}
                        />
                        <TextField
                          label={I18n.t("cod_king_abandoned_carts.end_date")}
                          type="date"
                          value={endDate}
                          onChange={(value) => {
                            setEndDate(value);
                            setPage(1);
                          }}
                          autoComplete="off"
                          disabled={!isPaidPlan}
                        />
                      </InlineStack>
                    ) : null}
                  </InlineStack>
                  {days === "custom" && (!startDate || !endDate) ? (
                    <Text as="p" variant="bodySm" tone="subdued">
                      {I18n.t("cod_king_abandoned_carts.select_start_and_end_date_to")}
                    </Text>
                  ) : null}
                </BlockStack>
              </InlineGrid>
            </Box>

            <div
              style={{
                filter: isPaidPlan ? "none" : "blur(6px)",
                opacity: isPaidPlan ? 1 : 0.9,
                pointerEvents: isPaidPlan ? "auto" : "none",
              }}
            >
              {rows.length === 0 ? (
                <EmptyState heading={I18n.t("cod_king_abandoned_carts.no_abandoned_carts_found")}>
                  <Text as="p" variant="bodyMd">
                    {I18n.t("cod_king_abandoned_carts.try_changing_day_range_or_search")}
                  </Text>
                </EmptyState>
              ) : (
                <div style={{ overflowX: "auto" }}>
                  <DataTable
                    columnContentTypes={[
                      "text",
                      "text",
                      "text",
                      "text",
                      "text",
                      "text",
                    ]}
                    headings={[
                      "Phone",
                      "Country",
                      "Timestamp",
                      "Verification Status",
                      "Cart Details",
                      "Actions",
                    ]}
                    rows={rows}
                  />
                </div>
              )}

              {rows.length > 0 && (
                <BlockStack gap="200" align="center">
                  <Pagination
                    hasPrevious={pagination.page > 1}
                    onPrevious={() => setPage((prev) => prev - 1)}
                    hasNext={pagination.page < pagination.pages}
                    onNext={() => setPage((prev) => prev + 1)}
                  />
                </BlockStack>
              )}
            </div>
          </Card>

          {!isPaidPlan && (
            <div
              style={{
                position: "absolute",
                inset: 0,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                padding: 16,
              }}
            >
              <Card>
                <Box padding="400">
                  <BlockStack gap="200" inlineAlign="center">
                    <Text as="p" variant="headingSm">
                      {I18n.t("cod_king_abandoned_carts.available_on_paid_plans_only")}
                    </Text>
                    <Text as="p" tone="subdued" alignment="center">
                      {I18n.t("cod_king_abandoned_carts.upgrade_to_unlock_search_export_and")}
                    </Text>
                    <Link
                      url="#"
                      onClick={(e) => {
                        e.preventDefault();
                        window.history.pushState({}, "", "/subscription");
                        window.dispatchEvent(new PopStateEvent("popstate"));
                      }}
                    >
                      {I18n.t("prepaid_discount.upgrade_cta")}
                    </Link>
                  </BlockStack>
                </Box>
              </Card>
            </div>
          )}
        </div>
      </BlockStack>

      <Modal
        open={!!currentDetailLog}
        onClose={() => setDetailLog(null)}
        title={I18n.t("cod_king_abandoned_carts.view_details")}
        primaryAction={{
          content: I18n.t("cod_king_abandoned_carts.close"),
          onAction: () => setDetailLog(null),
        }}
        secondaryActions={
          currentDetailLog
            ? [
                {
                  content: copiedId === currentDetailLog.id ? "Copied" : "Copy link",
                  onAction: () => handleCopyLink(currentDetailLog),
                },
              ]
            : []
        }
      >
        <Modal.Section>
          {currentDetailLog && (
            <BlockStack gap="300">
              <InlineGrid columns={{ xs: "1fr", md: "120px 1fr" }} gap="150">
                <Text as="p" variant="bodySm" tone="subdued">
                  {I18n.t("cod_king_abandoned_carts.phone")}
                </Text>
                <Text as="p" variant="bodySm">
                  {currentDetailLog.customerNumber || "-"}
                </Text>

                <Text as="p" variant="bodySm" tone="subdued">
                  {I18n.t("cod_king_abandoned_carts.country")}
                </Text>
                <Text as="p" variant="bodySm">
                  {currentDetailLog.countryCode || "-"}
                </Text>

                <Text as="p" variant="bodySm" tone="subdued">
                  {I18n.t("cod_king_abandoned_carts.timestamp")}
                </Text>
                <Text as="p" variant="bodySm">
                  {currentDetailLog.createdAt
                    ? DateTime.fromISO(currentDetailLog.createdAt).toFormat(
                        "MMM dd, yyyy h:mm a",
                      )
                    : "-"}
                </Text>

                <Text as="p" variant="bodySm" tone="subdued">
                  {I18n.t("cod_king_abandoned_carts.verification")}
                </Text>
                <Text as="p" variant="bodySm">
                  {currentDetailLog.verificationStatus || "-"}
                </Text>

                <Text as="p" variant="bodySm" tone="subdued">
                  {I18n.t("cod_king_abandoned_carts.permalink")}
                </Text>
                <Text as="p" variant="bodySm" breakWord>
                  {buildShopifyPermalink(
                    currentDetailLog.cartDetails,
                    shop?.shopify_domain,
                  ) || "-"}
                </Text>
              </InlineGrid>

              <Text as="h3" variant="headingSm">
                {I18n.t("cod_king_abandoned_carts.cart_details")}
              </Text>
              {Array.isArray(currentDetailLog.cartDetails) &&
                currentDetailLog.cartDetails.map((item, idx) => (
                  <InlineStack
                    key={`item-${currentDetailLog.id}-${idx}`}
                    gap="300"
                    blockAlign="start"
                  >
                    {item?.featured_image ? (
                      <img
                        src={item.featured_image}
                        alt={item?.title || "Product image"}
                        style={{
                          width: 64,
                          height: 64,
                          objectFit: "cover",
                          borderRadius: 6,
                          border: "1px solid #e1e3e5",
                        }}
                      />
                    ) : null}
                    <BlockStack gap="050">
                      <Text as="p" variant="bodySm" fontWeight="semibold">
                        {idx + 1}. {item?.title || "Untitled"}
                      </Text>
                      <Text as="p" variant="bodySm" tone="subdued">
                        {I18n.t("cod_king_abandoned_carts.item_meta", {
                          qty: item?.quantity || 1,
                          variant: item?.variant_id || "-",
                          price: item?.price || "-",
                        })}
                      </Text>
                    </BlockStack>
                  </InlineStack>
                ))}

              <Text as="h3" variant="headingSm">
                {I18n.t("cod_king_abandoned_carts.customer")}
              </Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {(currentDetailLog.customer?.firstName || currentDetailLog.customer?.first_name || "-")}{" "}
                {(currentDetailLog.customer?.lastName || currentDetailLog.customer?.last_name || "")} |{" "}
                {currentDetailLog.customer?.phone || "-"} |{" "}
                {currentDetailLog.customer?.email || "-"}
              </Text>

              <Text as="h3" variant="headingSm">
                {I18n.t("cod_king_abandoned_carts.recent_shipping_address_auto_fetched_from")}
              </Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {currentDetailLog.recentShippingAddress?.address1 ||
                currentDetailLog.recent_shipping_address?.address1
                  ? `${currentDetailLog.recentShippingAddress?.address1 || currentDetailLog.recent_shipping_address?.address1}, ${currentDetailLog.recentShippingAddress?.address2 || currentDetailLog.recent_shipping_address?.address2 || ""} ${currentDetailLog.recentShippingAddress?.city || currentDetailLog.recent_shipping_address?.city || ""}, ${currentDetailLog.recentShippingAddress?.province || currentDetailLog.recent_shipping_address?.province || ""}, ${currentDetailLog.recentShippingAddress?.country || currentDetailLog.recent_shipping_address?.country || ""} ${currentDetailLog.recentShippingAddress?.zip || currentDetailLog.recent_shipping_address?.zip || ""}`
                  : "-"}
              </Text>
            </BlockStack>
          )}
        </Modal.Section>
      </Modal>
    </Page>
  );
};

export default CodKingAbandonedCarts;

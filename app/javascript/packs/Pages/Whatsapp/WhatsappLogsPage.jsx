import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Box,
  Text,
  Badge,
  Button,
  Select,
  Spinner,
  Banner,
  DataTable,
  EmptyState,
  Modal,
  Divider,
} from "@shopify/polaris";
import { RefreshMinor } from "@shopify/polaris-icons";
import { camelizeKeys } from "humps";
import useApi from "../../Hooks/useApi";
import WhatsappLayout from "./WhatsappLayout";
import WhatsappErrorBanner from "../../Components/WhatsappErrorBanner";
import translateWhatsappError from "../../utils/whatsappErrorMessages";
import I18n from "../../i18n-lang";

// Same-message resend. Server rebuilds the send from what the log row
// captured and returns the NEW attempt's row (or the failed attempt + error).
const retryLog = async (logId) => {
  const token = await shopify.idToken();
  const res = await fetch(
    `https://${process.env.APP_HOST}/api/whatsapp/message_logs/${logId}/retry`,
    { method: "POST", headers: { Authorization: `Bearer ${token}` } }
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data?.error || `Retry failed (${res.status})`);
    err.log = data?.log || null;
    throw err;
  }
  return data?.log || null;
};

// Color tokens per status — used for the left accent bar on each stat tile.
const STATUS_COLORS = {
  queued: "#FACC15",
  sent: "#3B82F6",
  delivered: "#10B981",
  read: "#059669",
  failed: "#EF4444",
  retry_pending: "#F59E0B",
  dropped: "#6B7280",
};

const STATUS_EMOJI = {
  queued: "⏳",
  sent: "📤",
  delivered: "✅",
  read: "👀",
  failed: "⚠️",
  retry_pending: "🔁",
  dropped: "🚫",
};

const statusBadge = (status) => {
  switch (status) {
    case "delivered":
      return <Badge tone="success">{I18n.t("whatsapp_logs_page.delivered")}</Badge>;
    case "read":
      return <Badge tone="success">{I18n.t("whatsapp_logs_page.read")}</Badge>;
    case "sent":
      return <Badge tone="info">{I18n.t("whatsapp_logs_page.sent")}</Badge>;
    case "queued":
      return <Badge tone="attention">{I18n.t("whatsapp_logs_page.queued")}</Badge>;
    case "failed":
      return <Badge tone="critical">{I18n.t("whatsapp_logs_page.failed")}</Badge>;
    case "retry_pending":
      return <Badge tone="warning">{I18n.t("whatsapp_logs_page.retry_pending", { defaultValue: "Retry scheduled" })}</Badge>;
    case "dropped":
      return <Badge>{I18n.t("whatsapp_logs_page.dropped", { defaultValue: "Not delivered" })}</Badge>;
    default:
      return <Badge>{status}</Badge>;
  }
};

const formatTime = (iso) => {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
};

// Date-range options shown on the Logs filter row. "0" = no constraint (all
// time). Matches the convention used on the Summary page so merchants get
// the same pickers everywhere.
const DAYS_OPTIONS = [
  { label: "All time", value: "0" },
  { label: "Last 1 day", value: "1" },
  { label: "Last 3 days", value: "3" },
  { label: "Last 7 days", value: "7" },
  { label: "Last 30 days", value: "30" },
  { label: "Last 90 days", value: "90" },
];

// Order shown in the stats row. We render a tile per status the backend
// returns; the order here is what feels natural in the message lifecycle.
const STATS_ORDER = ["queued", "sent", "delivered", "read", "failed", "retry_pending", "dropped"];

const STAT_BADGE = {
  queued: { label: "Queued", tone: "attention" },
  sent: { label: "Sent", tone: "info" },
  delivered: { label: "Delivered", tone: "success" },
  read: { label: "Read", tone: "success" },
  failed: { label: "Failed", tone: "critical" },
  retry_pending: { label: "Retry scheduled", tone: "warning" },
  dropped: { label: "Not delivered", tone: undefined },
};

const WhatsappLogsPage = () => {
  const initialQuery = useMemo(() => new URLSearchParams(window.location.search), []);
  const [eventFilter, setEventFilter] = useState(() => initialQuery.get("event") || "");
  const [statusFilter, setStatusFilter] = useState(() => initialQuery.get("status") || "");
  const [phoneFilter, setPhoneFilter] = useState(() => initialQuery.get("q") || "");
  const [daysFilter, setDaysFilter] = useState("7");
  const [page, setPage] = useState(1);
  const [openLog, setOpenLog] = useState(null);
  const [retryingId, setRetryingId] = useState(null);
  const [retryNotice, setRetryNotice] = useState(null);


  const buildUrl = useCallback(
    () => {
      const qs = new URLSearchParams();
      qs.set("page", String(page));
      qs.set("per_page", "50");
      if (eventFilter) qs.set("event_type_key", eventFilter);
      if (statusFilter) qs.set("status", statusFilter);
      if (daysFilter && daysFilter !== "0") qs.set("days", daysFilter);
      if (phoneFilter) qs.set("q", phoneFilter);
      return `/api/whatsapp/message_logs?${qs.toString()}`;
    },
    [eventFilter, statusFilter, daysFilter, phoneFilter, page]
  );

  const [{ data, loading, error }, refetch] = useApi(
    { url: buildUrl(), method: "GET" },
    { manual: false }
  );

  // Re-fetch whenever a filter changes — useApi keys on the URL string.
  useEffect(() => {
    refetch({ url: buildUrl() });
  }, [buildUrl, refetch]);

  const [{ data: eventsData }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );

  const handleRetry = useCallback(
    async (log) => {
      if (!log || retryingId) return;
      setRetryingId(log.id);
      setRetryNotice(null);
      try {
        const created = await retryLog(log.id);
        setRetryNotice({
          tone: created?.status === "failed" ? "critical" : "success",
          message:
            created?.status === "failed"
              ? `Retry to ${log.recipient} was rejected by Meta: ${
                  translateWhatsappError({ code: created.errorCode, rawMessage: created.errorMessage }).title
                }`
              : `Message re-sent to ${log.recipient} (new log #${created?.id ?? "?"}).`,
        });
      } catch (e) {
        setRetryNotice({ tone: "critical", message: `Retry failed: ${e.message}` });
      } finally {
        setRetryingId(null);
        setOpenLog(null);
        refetch({ url: buildUrl() });
      }
    },
    [retryingId, refetch, buildUrl]
  );

  const events = eventsData?.events || [];
  const logs = data?.logs || [];
  const total = data?.total || 0;
  const perPage = data?.perPage || 50;
  const lastPage = Math.max(1, Math.ceil(total / perPage));

  const eventOptions = useMemo(
    () => [
      { label: "All events", value: "" },
      ...events.map((e) => ({ label: e.label, value: e.key })),
    ],
    [events]
  );

  const statusOptions = [
    { label: "All statuses", value: "" },
    { label: "Queued", value: "queued" },
    { label: "Sent", value: "sent" },
    { label: "Delivered", value: "delivered" },
    { label: "Read", value: "read" },
    { label: "Failed", value: "failed" },
    { label: "Retry scheduled", value: "retry_pending" },
    { label: "Not delivered", value: "dropped" },
  ];

  const rows = logs.map((l) => [
    formatTime(l.createdAt),
    l.eventTypeKey || "—",
    l.templateName || "—",
    l.recipient || "—",
    statusBadge(l.status),
    l.status === "failed"
      ? translateWhatsappError({ code: l.errorCode, rawMessage: l.errorMessage }).title
      : l.deliveredAt
      ? `delivered ${formatTime(l.deliveredAt)}`
      : l.sentAt
      ? `sent ${formatTime(l.sentAt)}`
      : "—",
    // Reply column — surfaces quick-reply taps without forcing the merchant
    // into the detail modal.
    (l.replyCount || 0) > 0 ? (
      <Button
        key={`reply-${l.id}`}
        variant="plain"
        onClick={() => setOpenLog(l)}
      >
        {l.replyCount} {l.replyCount === 1 ? "reply" : "replies"}
      </Button>
    ) : (
      <Text key={`reply-${l.id}`} as="span" tone="subdued">—</Text>
    ),
    <InlineStack key={`actions-${l.id}`} gap="300" wrap={false}>
      <Button variant="plain" onClick={() => setOpenLog(l)}>
        {I18n.t("whatsapp_logs_page.preview")}
      </Button>
      <Button
        variant="plain"
        tone={l.status === "failed" ? "critical" : undefined}
        loading={retryingId === l.id}
        disabled={!!retryingId && retryingId !== l.id}
        onClick={() => handleRetry(l)}
      >
        {I18n.t("whatsapp_logs_page.retry")}
      </Button>
    </InlineStack>,
  ]);

  return (
    <WhatsappLayout title={I18n.t("whatsapp_logs_page.logs")}>
      <BlockStack gap="400">
        {phoneFilter && (
          <Banner
            tone="info"
            onDismiss={() => {
              setPhoneFilter("");
              setPage(1);
            }}
          >
            {I18n.t("whatsapp_logs_page.showing_for_phone", {
              defaultValue: "Showing messages for %{phone}. Close this to see all messages.",
              phone: phoneFilter,
            })}
          </Banner>
        )}
        {error && <Banner tone="critical">{error?.message || "Failed to load logs"}</Banner>}
        {retryNotice && (
          <Banner tone={retryNotice.tone} onDismiss={() => setRetryNotice(null)}>
            {retryNotice.message}
          </Banner>
        )}

        <Card>
          <Box padding="400">
            <BlockStack gap="300">
              <InlineStack gap="200" blockAlign="end" wrap>
                <Box minWidth="160px">
                  <Select
                    label={I18n.t("whatsapp_logs_page.date_range")}
                    options={DAYS_OPTIONS}
                    value={daysFilter}
                    onChange={(v) => {
                      setDaysFilter(v);
                      setPage(1);
                    }}
                  />
                </Box>
                <Box minWidth="200px">
                  <Select
                    label={I18n.t("whatsapp_logs_page.event")}
                    options={eventOptions}
                    value={eventFilter}
                    onChange={(v) => {
                      setEventFilter(v);
                      setPage(1);
                    }}
                  />
                </Box>
                <Box minWidth="180px">
                  <Select
                    label={I18n.t("whatsapp_logs_page.status")}
                    options={statusOptions}
                    value={statusFilter}
                    onChange={(v) => {
                      setStatusFilter(v);
                      setPage(1);
                    }}
                  />
                </Box>
                <Button
                  icon={RefreshMinor}
                  onClick={() => refetch({ url: buildUrl() })}
                  loading={loading}
                >
                  {I18n.t("whatsapp_logs_page.refresh")}
                </Button>
                <Box>
                  <Text as="span" tone="subdued" variant="bodySm">
                    {total} {total === 1 ? "log" : "logs"}
                  </Text>
                </Box>
              </InlineStack>

              <StatsRow stats={data?.stats} />
            </BlockStack>
          </Box>
        </Card>

        {loading && logs.length === 0 ? (
          <Card>
            <Box padding="500">
              <InlineStack gap="200" align="center">
                <Spinner size="small" />
                <Text as="span">{I18n.t("whatsapp_logs_page.loading_logs")}</Text>
              </InlineStack>
            </Box>
          </Card>
        ) : logs.length === 0 ? (
          <Card>
            <Box padding="500">
              <EmptyState
                heading={I18n.t("whatsapp_logs_page.no_messages_yet")}
                image="https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png"
              >
                <Text as="p" tone="subdued">
                  {I18n.t("whatsapp_logs_page.messages_sent_via_event_triggers_or_2")}
                </Text>
              </EmptyState>
            </Box>
          </Card>
        ) : (
          <Card>
            <DataTable
              columnContentTypes={["text", "text", "text", "text", "text", "text", "text", "text"]}
              headings={["Time", "Event", "Template", "Recipient", "Status", "Detail", "Replies", ""]}
              rows={rows}
            />
            {lastPage > 1 && (
              <Box padding="300">
                <InlineStack gap="200" align="end">
                  <Button disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                    {I18n.t("whatsapp_logs_page.previous")}
                  </Button>
                  <Text as="span" variant="bodySm">
                    Page {page} of {lastPage}
                  </Text>
                  <Button disabled={page >= lastPage} onClick={() => setPage((p) => p + 1)}>
                    {I18n.t("whatsapp_logs_page.next")}
                  </Button>
                </InlineStack>
              </Box>
            )}
          </Card>
        )}
      </BlockStack>

      <LogPreviewModal
        log={openLog}
        onClose={() => setOpenLog(null)}
        onRetry={handleRetry}
        retrying={!!openLog && retryingId === openLog.id}
      />
    </WhatsappLayout>
  );
};

// Stats tiles + at-a-glance delivery/read rates. Each tile gets a color
// accent bar matching the WhatsApp lifecycle. Zero-count statuses are
// hidden so the row stays scannable.
const StatsRow = ({ stats }) => {
  if (!stats || Object.keys(stats).length === 0) return null;

  // The DB enum is monotonic — a row with status='read' was also delivered
  // (and sent). The tiles surface a more intuitive cumulative count rather
  // than the raw enum bucket: 'delivered' counts everything that reached the
  // device, 'sent' counts everything Meta accepted, etc.
  const valueFor = (s) => {
    switch (s) {
      case "sent":
        return (stats.sent || 0) + (stats.delivered || 0) + (stats.read || 0);
      case "delivered":
        return (stats.delivered || 0) + (stats.read || 0);
      default:
        return stats[s] || 0;
    }
  };

  const visible = STATS_ORDER.filter((s) => valueFor(s) > 0);
  if (visible.length === 0) return null;

  // Total = number of distinct rows. Each row is in exactly one enum bucket,
  // so we sum raw counts (not the cumulative valueFor).
  const total = STATS_ORDER.reduce((acc, k) => acc + (stats[k] || 0), 0);

  // Messages that actually reached (or failed at) the device.
  const deliveredish = (stats.delivered || 0) + (stats.read || 0);
  // Delivery-rate denominator = everything that left the queue: still-sent
  // (pending delivery), delivered, read, AND failed. `failed` belongs here —
  // those messages were sent to Meta but never delivered, so excluding them
  // overstated the rate (e.g. 4 failed yet "100% delivered"). `queued` is
  // excluded since those haven't been sent yet.
  const attempted = (stats.sent || 0) + deliveredish + (stats.failed || 0);
  const deliveryRate =
    attempted > 0 ? Math.round((deliveredish / attempted) * 100) : null;
  // Read rate stays relative to delivered messages (of those that reached the
  // device, how many were read).
  const readRate =
    deliveredish > 0 ? Math.round(((stats.read || 0) / deliveredish) * 100) : null;

  return (
    <BlockStack gap="300">
      <div
        style={{
          display: "grid",
          gridTemplateColumns: `repeat(${visible.length}, minmax(140px, 1fr))`,
          gap: 12,
        }}
      >
        {visible.map((s) => {
          const count = valueFor(s);
          const pct = total > 0 ? Math.round((count / total) * 100) : 0;
          return (
            <div
              key={s}
              style={{
                position: "relative",
                background: "#ffffff",
                borderRadius: 10,
                padding: "14px 16px",
                boxShadow:
                  "0 0 0 1px rgba(15,23,42,0.06), 0 1px 2px rgba(15,23,42,0.04)",
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  left: 0,
                  bottom: 0,
                  width: 4,
                  background: STATUS_COLORS[s],
                }}
              />
              <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{ fontSize: 16 }}>{STATUS_EMOJI[s]}</span>
                <Text as="span" tone="subdued" variant="bodySm">
                  {STAT_BADGE[s]?.label || s}
                </Text>
              </div>
              <div style={{ marginTop: 4 }}>
                <Text as="span" variant="heading2xl" fontWeight="bold">
                  {count.toLocaleString()}
                </Text>
              </div>
              <Text as="span" tone="subdued" variant="bodySm">
                {pct}% of total
              </Text>
            </div>
          );
        })}
      </div>

      {(deliveryRate != null || readRate != null) && (
        <InlineStack gap="400" blockAlign="center">
          {deliveryRate != null && (
            <RateChip
              label={I18n.t("whatsapp_logs_page.delivery_rate")}
              value={`${deliveryRate}%`}
              tone={deliveryRate >= 90 ? "success" : deliveryRate >= 70 ? "warning" : "critical"}
            />
          )}
          {readRate != null && (
            <RateChip label={I18n.t("whatsapp_logs_page.read_rate")} value={`${readRate}%`} tone="info" />
          )}
        </InlineStack>
      )}
    </BlockStack>
  );
};

const RateChip = ({ label, value, tone }) => {
  const colorByTone = {
    success: "#10B981",
    warning: "#F59E0B",
    critical: "#EF4444",
    info: "#3B82F6",
  };
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        padding: "6px 12px",
        borderRadius: 999,
        background: "#F8FAFC",
        border: "1px solid rgba(15,23,42,0.08)",
      }}
    >
      <span
        style={{
          width: 8,
          height: 8,
          borderRadius: "50%",
          background: colorByTone[tone] || "#3B82F6",
        }}
      />
      <Text as="span" tone="subdued" variant="bodySm">
        {label}
      </Text>
      <Text as="span" variant="bodyMd" fontWeight="semibold">
        {value}
      </Text>
    </div>
  );
};

// Click-to-open modal that renders the actual WhatsApp bubble for a log row,
// fills the {{N}} placeholders with whatever values we captured at send time
// (used_samples), and walks the merchant through the status timeline.
const LogPreviewModal = ({ log, onClose, onRetry, retrying }) => {
  if (!log) return null;

  const body = (log.templateComponents || []).find(
    (c) => (c?.type || "").toUpperCase() === "BODY"
  );
  const header = (log.templateComponents || []).find(
    (c) => (c?.type || "").toUpperCase() === "HEADER"
  );
  const footer = (log.templateComponents || []).find(
    (c) => (c?.type || "").toUpperCase() === "FOOTER"
  );
  const buttonsComp = (log.templateComponents || []).find(
    (c) => (c?.type || "").toUpperCase() === "BUTTONS"
  );

  // Build a positional [{{1}} → value] table. Prefer the actual body
  // parameters Meta received (stored by SendTemplateMessageService); fall
  // back to `used_samples` for legacy test rows. Each Meta body parameter
  // is shaped `{type: 'text', text: 'Aman'}`.
  const filledValues = (() => {
    const params = log.bodyParameters;
    if (Array.isArray(params) && params.length) {
      return params.map((p) => (p && typeof p === "object" ? p.text : p));
    }
    return Array.isArray(log.usedSamples) ? log.usedSamples : [];
  })();

  const fillSlots = (text) => {
    if (!text) return "";
    return text.replace(/\{\{(\d+)\}\}/g, (_m, n) => {
      const i = Number(n) - 1;
      const value = filledValues[i];
      return value != null && value !== "" ? String(value) : `{{${n}}}`;
    });
  };

  return (
    <Modal
      open
      onClose={onClose}
      title={I18n.t("whatsapp_logs_page.message_detail")}
      large
      primaryAction={{
        content: "Retry — send again",
        onAction: () => onRetry && onRetry(log),
        loading: !!retrying,
        destructive: log.status === "failed",
      }}
      secondaryActions={[{ content: "Close", onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          {/* WhatsApp-styled preview */}
          <div
            style={{
              background: "#E5DDD5",
              borderRadius: 12,
              padding: 16,
              fontFamily: "system-ui, -apple-system, sans-serif",
            }}
          >
            <div
              style={{
                background: "#ffffff",
                borderRadius: 8,
                padding: "10px 12px",
                fontSize: 14,
                lineHeight: 1.45,
                color: "#111b21",
                maxWidth: 320,
              }}
            >
              {header && header.format === "TEXT" && (
                <div style={{ fontWeight: 700, marginBottom: 6 }}>
                  {fillSlots(header.text)}
                </div>
              )}
              {header && header.format && header.format !== "TEXT" && (
                <div
                  style={{
                    background: "#e7eef5",
                    color: "#445870",
                    borderRadius: 4,
                    padding: "16px 10px",
                    textAlign: "center",
                    fontSize: 11,
                    marginBottom: 6,
                  }}
                >
                  {header.format.charAt(0) +
                    header.format.slice(1).toLowerCase()}{" "}
                  preview
                </div>
              )}
              {body && (
                <div>
                  {(fillSlots(body.text) || "").split("\n").map((line, i) => (
                    <div key={i}>{line || " "}</div>
                  ))}
                </div>
              )}
              {footer && (
                <div style={{ marginTop: 6, fontSize: 11, color: "#667781" }}>
                  {footer.text}
                </div>
              )}
              <div
                style={{
                  fontSize: 10,
                  color: "#8696a0",
                  textAlign: "right",
                  marginTop: 4,
                }}
              >
                {log.sentAt
                  ? new Date(log.sentAt).toLocaleTimeString([], {
                      hour: "2-digit",
                      minute: "2-digit",
                    })
                  : "—"}
                {log.status === "delivered" || log.status === "read" ? " ✓✓" : " ✓"}
              </div>
            </div>
            {(buttonsComp?.buttons || []).map((b, idx) => (
              <div
                key={idx}
                style={{
                  marginTop: 6,
                  background: "#ffffff",
                  borderRadius: 8,
                  padding: "10px 12px",
                  fontSize: 14,
                  color: "#027eb5",
                  textAlign: "center",
                  fontWeight: 500,
                  maxWidth: 320,
                }}
              >
                {b.type === "URL" ? "↗" : b.type === "PHONE_NUMBER" ? "📞" : "↩"}{" "}
                {b.text || "Button"}
              </div>
            ))}
          </div>

          {/* Failed → translated reason banner */}
          {log.status === "failed" && (
            <WhatsappErrorBanner
              code={log.errorCode}
              rawMessage={log.errorMessage}
            />
          )}

          <Divider />

          {/* Metadata + timeline */}
          <BlockStack gap="200">
            <InlineStack align="space-between">
              <Text as="span" tone="subdued">{I18n.t("whatsapp_logs_page.recipient")}</Text>
              <Text as="span" fontWeight="medium">
                {log.recipient || "—"}
              </Text>
            </InlineStack>
            <InlineStack align="space-between">
              <Text as="span" tone="subdued">{I18n.t("whatsapp_logs_page.template")}</Text>
              <Text as="span" fontWeight="medium">
                {log.templateName || "—"}{" "}
                {log.templateLanguage ? `(${log.templateLanguage})` : ""}
              </Text>
            </InlineStack>
            <InlineStack align="space-between">
              <Text as="span" tone="subdued">{I18n.t("whatsapp_logs_page.event")}</Text>
              <Text as="span" fontWeight="medium">{log.eventTypeKey || "—"}</Text>
            </InlineStack>
            {log.retryOfLogId && (
              <InlineStack align="space-between">
                <Text as="span" tone="subdued">{I18n.t("whatsapp_logs_page.retry_of")}</Text>
                <Text as="span" fontWeight="medium">
                  log #{log.retryOfLogId}
                  {log.retryAttempt ? ` (attempt ${log.retryAttempt})` : ""}
                </Text>
              </InlineStack>
            )}
            {log.metaMessageId && (
              <InlineStack align="space-between">
                <Text as="span" tone="subdued">{I18n.t("whatsapp_logs_page.meta_message_id")}</Text>
                <Text as="span" fontWeight="medium" fontFamily="mono">
                  {log.metaMessageId}
                </Text>
              </InlineStack>
            )}
          </BlockStack>

          <SendDiagnostics log={log} />

          <Divider />

          <BlockStack gap="100">
            <TimelineRow label={I18n.t("whatsapp_logs_page.created")} at={log.createdAt} />
            <TimelineRow label={I18n.t("whatsapp_logs_page.sent")} at={log.sentAt} />
            <TimelineRow label={I18n.t("whatsapp_logs_page.delivered")} at={log.deliveredAt} />
            <TimelineRow label={I18n.t("whatsapp_logs_page.read")} at={log.readAt} />
            <TimelineRow label={I18n.t("whatsapp_logs_page.failed")} at={log.failedAt} />
          </BlockStack>

          {(log.replies || []).length > 0 && (
            <>
              <Divider />
              <BlockStack gap="200">
                <Text as="h3" variant="headingSm">
                  {I18n.t("whatsapp_logs_page.customer_replies")}
                </Text>
                {(log.replies || []).map((r) => (
                  <Box
                    key={r.id}
                    padding="200"
                    borderColor="border"
                    borderWidth="025"
                    borderRadius="200"
                    background="bg-surface-secondary"
                  >
                    <BlockStack gap="050">
                      <InlineStack align="space-between" wrap>
                        <Text as="span" fontWeight="medium">
                          {r.kind === "button"
                            ? `↩ Tapped "${r.displayText || r.payload || "button"}"`
                            : r.kind === "interactive"
                            ? `↩ Selected "${r.displayText || r.payload || "option"}"`
                            : r.kind === "text"
                            ? `"${r.displayText || ""}"`
                            : `${r.kind} reply`}
                        </Text>
                        <Text as="span" tone="subdued" variant="bodySm">
                          {r.receivedAt ? new Date(r.receivedAt).toLocaleString() : ""}
                        </Text>
                      </InlineStack>
                    </BlockStack>
                  </Box>
                ))}
                {(log.replyCount || 0) > (log.replies || []).length && (
                  <Text as="span" tone="subdued" variant="bodySm">
                    Showing the {log.replies.length} most recent of {log.replyCount} total replies.
                  </Text>
                )}
              </BlockStack>
            </>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

// Problems Meta rejects inside a body parameter, plus our own blank fallback.
const paramProblems = (text) => {
  const t = text == null ? "" : String(text);
  const out = [];
  if (t.trim() === "" || t === "—") out.push("blank (variable resolved to nothing)");
  if (/[\n\t\r]/.test(t)) out.push("contains newline/tab");
  if (/ {5,}/.test(t)) out.push("more than 4 consecutive spaces");
  if (t.length > 1024) out.push(`too long (${t.length} chars)`);
  return out;
};

const pretty = (v) => {
  try {
    return JSON.stringify(v, null, 2);
  } catch (_e) {
    return String(v);
  }
};

const CodeBlock = ({ value }) => (
  <pre
    style={{
      margin: 0,
      padding: 10,
      background: "#f6f6f7",
      borderRadius: 6,
      fontSize: 12,
      lineHeight: 1.4,
      whiteSpace: "pre-wrap",
      wordBreak: "break-all",
      maxHeight: 260,
      overflow: "auto",
    }}
  >
    {typeof value === "string" ? value : pretty(value)}
  </pre>
);

// "What was sent to Meta" — the exact parameters behind this log row, so a
// rejection like "(#100) Invalid parameter" can be traced from the UI.
const SendDiagnostics = ({ log }) => {
  const [open, setOpen] = useState(log.status === "failed");
  const d = useMemo(() => camelizeKeys(log.diagnostics || {}), [log.diagnostics]);
  const bodyParams = Array.isArray(log.bodyParameters || log.body_parameters)
    ? log.bodyParameters || log.body_parameters
    : [];
  const mapping = log.diagnostics?.variable_mapping || d.variableMapping || {};
  const req = d.sendRequest || {};
  const header = req.headerParameters;
  const headerUsesId = String(pretty(header) || "").includes('"id"');

  const warnings = [];
  bodyParams.forEach((p, i) => {
    const probs = paramProblems(p && typeof p === "object" ? p.text : p);
    if (probs.length) warnings.push(`{{${i + 1}}}: ${probs.join(", ")}`);
  });
  const headerComp = (log.templateComponents || []).find(
    (c) => (c?.type || "").toUpperCase() === "HEADER"
  );
  if (headerComp && headerComp.format && headerComp.format !== "TEXT" && !header) {
    warnings.push(`Template has a ${headerComp.format} header but no header parameter was sent`);
  }
  if (
    d.templateAccountId &&
    d.sendingAccountId &&
    String(d.templateAccountId) !== String(d.sendingAccountId)
  ) {
    warnings.push(
      `Sent from number #${d.sendingAccountId} but the template belongs to number #${d.templateAccountId}` +
        (headerUsesId ? " — the header media id was uploaded for a different number" : "")
    );
  }
  if (d.lineItems === "missing") warnings.push("Order payload has no line_items");

  const copyAll = () => {
    const text = pretty({ bodyParameters: bodyParams, ...d });
    try {
      navigator.clipboard.writeText(text);
    } catch (_e) {
      /* clipboard unavailable — the JSON is visible below */
    }
  };

  return (
    <>
      <Divider />
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h3" variant="headingSm">
            What was sent to Meta
          </Text>
          <InlineStack gap="200">
            {open && (
              <Button size="slim" onClick={copyAll}>
                Copy JSON
              </Button>
            )}
            <Button size="slim" disclosure={open ? "up" : "down"} onClick={() => setOpen(!open)}>
              {open ? "Hide" : "Show"}
            </Button>
          </InlineStack>
        </InlineStack>

        {open && (
          <BlockStack gap="300">
            {d.error && <Banner tone="warning">Couldn't load diagnostics: {d.error}</Banner>}
            {warnings.length > 0 && (
              <Banner tone="warning" title="Possible causes">
                <BlockStack gap="100">
                  {warnings.map((w, i) => (
                    <Text as="p" key={i}>
                      {w}
                    </Text>
                  ))}
                </BlockStack>
              </Banner>
            )}

            <BlockStack gap="100">
              <InlineStack align="space-between">
                <Text as="span" tone="subdued">Sending number</Text>
                <Text as="span" fontWeight="medium">
                  #{d.sendingAccountId ?? "—"} {d.sendingPhone ? `(${d.sendingPhone})` : ""}
                </Text>
              </InlineStack>
              <InlineStack align="space-between">
                <Text as="span" tone="subdued">Template</Text>
                <Text as="span" fontWeight="medium">
                  id {d.templateId ?? "—"} · number #{d.templateAccountId ?? "—"} · {d.templateStatus || "—"}
                </Text>
              </InlineStack>
              {d.orderName && (
                <InlineStack align="space-between">
                  <Text as="span" tone="subdued">Order</Text>
                  <Text as="span" fontWeight="medium">{d.orderName}</Text>
                </InlineStack>
              )}
            </BlockStack>

            <Text as="h4" variant="headingXs">Body variables</Text>
            {bodyParams.length ? (
              <DataTable
                columnContentTypes={["text", "text", "text", "text"]}
                headings={["Slot", "Mapped to", "Value sent", "Check"]}
                rows={bodyParams.map((p, i) => {
                  const text = p && typeof p === "object" ? p.text : p;
                  const probs = paramProblems(text);
                  return [
                    `{{${i + 1}}}`,
                    mapping[String(i + 1)] || "— (unmapped)",
                    <span key="v" style={{ whiteSpace: "pre-wrap", wordBreak: "break-word" }}>
                      {JSON.stringify(text ?? "")}
                    </span>,
                    probs.length ? (
                      <Badge key="b" tone="warning">{probs.join(", ")}</Badge>
                    ) : (
                      <Badge key="b" tone="success">OK</Badge>
                    ),
                  ];
                })}
              />
            ) : (
              <Text as="p" tone="subdued">No body parameters were sent.</Text>
            )}

            <Text as="h4" variant="headingXs">Header parameter</Text>
            <CodeBlock value={header ?? "none"} />

            {Boolean(
              req.buttonSlug ||
                req.urlButtonParams ||
                req.quickReplyButtonParams ||
                req.buttonIndex
            ) && (
              <>
                <Text as="h4" variant="headingXs">Buttons</Text>
                <CodeBlock
                  value={{
                    buttonSlug: req.buttonSlug,
                    buttonIndex: req.buttonIndex,
                    urlButtonParams: req.urlButtonParams,
                    quickReplyButtonParams: req.quickReplyButtonParams,
                  }}
                />
              </>
            )}

            {Array.isArray(log.diagnostics?.meta_attempts || log.diagnostics?.metaAttempts) &&
              (log.diagnostics?.meta_attempts || log.diagnostics?.metaAttempts).map((a, i) => (
                <BlockStack gap="100" key={`attempt-${i}`}>
                  <InlineStack gap="200" blockAlign="center">
                    <Text as="h4" variant="headingXs">
                      Request to Meta — attempt {i + 1}
                    </Text>
                    <Badge tone={a.ok ? "success" : "critical"}>{a.ok ? "accepted" : "rejected"}</Badge>
                  </InlineStack>
                  <CodeBlock value={a.request} />
                  {a.error && (
                    <>
                      <Text as="span" variant="bodySm" tone="subdued">Meta's full error</Text>
                      <CodeBlock value={a.error} />
                    </>
                  )}
                </BlockStack>
              ))}

            {d.lineItems !== undefined && d.lineItems !== null && (
              <>
                <Text as="h4" variant="headingXs">Order line items</Text>
                <CodeBlock value={d.lineItems} />
              </>
            )}

            <Text as="h4" variant="headingXs">Template header media config</Text>
            <CodeBlock value={d.headerMedia ?? "none"} />

            {Array.isArray(d.payloadKeys) && (
              <Text as="p" tone="subdued" variant="bodySm">
                Payload keys: {d.payloadKeys.join(", ") || "—"}
              </Text>
            )}
          </BlockStack>
        )}
      </BlockStack>
    </>
  );
};

const TimelineRow = ({ label, at }) => (
  <InlineStack align="space-between">
    <Text as="span" tone="subdued">{label}</Text>
    <Text as="span" fontWeight="medium" tone={at ? "default" : "subdued"}>
      {at ? new Date(at).toLocaleString() : "—"}
    </Text>
  </InlineStack>
);

export default WhatsappLogsPage;

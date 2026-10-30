import React, { useState, useEffect, useCallback } from "react";
import {
  Card, BlockStack, InlineStack, InlineGrid, Box, Text, Badge, Banner, ProgressBar, DataTable,
  TextField, Tabs, SkeletonBodyText, Divider, Modal,
} from "@shopify/polaris";
import WhatsappLayout from "../WhatsappLayout";
import { navigateTo } from "../../../../utils/navigate";
import { api } from "./api";
import { RelaunchModal } from "./CampaignsTab";
import { CampaignRevenueCard } from "./CampaignRevenue";
import GuardrailBanner, {
  RiskConfirmModal, needsResumeConfirm, isQualityLowError, isQuietHoursHold, frequencyCapHours,
} from "./GuardrailBanner";
import {
  t, paths, statusLabel, STATUS_TONE, STATUS_PROGRESS, percent, formatNumber, audienceSourceLabel,
  fieldLabel,
} from "./copy";

// Meta error codes merchants actually hit, in words they can act on.
const failureReason = (code) =>
  ({
    131049: t("err_131049", "WhatsApp limited marketing messages to this person (retried automatically if retries are on)"),
    131026: t("err_131026", "Number isn't on WhatsApp or can't receive messages"),
    131048: t("err_131048", "Sending too fast — WhatsApp slowed this number down"),
    131056: t("err_131056", "Too many messages to the same person in a short time"),
    131050: t("err_131050", "Customer stopped marketing messages from your business"),
    132000: t("err_132000", "Message variables didn't match the approved message"),
    132001: t("err_132001", "Approved message not found for this number"),
    130472: t("err_130472", "WhatsApp held this message back as part of a test it runs"),
    131000: t("err_131000", "WhatsApp had a temporary problem"),
  })[Number(code)] || (code ? t("err_other", "Error code %{code}", { code }) : t("err_unknown", "Unknown reason"));

const recipientStatus = (r) => {
  switch (r.status) {
    case "retry_pending":
      return r.next_retry_at
        ? t("rcpt_retry_at", "Retrying %{time}", { time: new Date(r.next_retry_at).toLocaleString() })
        : t("rcpt_retry", "Retrying soon");
    case "suppressed":
      return t("rcpt_skipped", "Skipped");
    case "read":
      return t("rcpt_read", "Read");
    case "delivered":
      return t("rcpt_delivered", "Delivered");
    case "sent":
      return t("rcpt_sent", "Sent");
    case "failed":
      return t("rcpt_failed", "Not delivered");
    case "pending":
      return t("rcpt_pending", "Waiting to send");
    case "queued":
      return t("rcpt_queued", "Sending");
    default:
      return r.status;
  }
};

const skipReason = (reason, capHours = 48) => {
  const raw = String(reason || "");
  if (raw === "opted_out") return t("skip_opted_out", "Opted out of your messages");
  if (raw === "frequency_cap") {
    return t("skip_frequency_cap", "Already got a campaign message in the last %{hours} hours", { hours: capHours });
  }
  if (raw.startsWith("missing_variable")) {
    const fields = raw.split(":")[1];
    const names = (fields || "").split(",").map((f) => fieldLabel(f.trim())).filter(Boolean).join(", ");
    return names
      ? t("skip_missing_named", "No %{fields} for this person", { fields: names })
      : t("skip_missing_variable", "Missing personal details for the message");
  }
  return raw;
};

const RECIPIENT_FILTERS = [
  { id: "", label: () => t("filter_all", "All") },
  { id: "read", label: () => t("rcpt_read", "Read") },
  { id: "delivered", label: () => t("rcpt_delivered", "Delivered") },
  { id: "failed", label: () => t("rcpt_failed", "Not delivered") },
  { id: "suppressed", label: () => t("rcpt_skipped", "Skipped") },
];

const Metric = ({ label, value, sub }) => (
  <BlockStack gap="050">
    <Text as="span" variant="bodySm" tone="subdued">{label}</Text>
    <Text as="span" variant="headingLg">{value}</Text>
    {sub && <Text as="span" variant="bodySm" tone="subdued">{sub}</Text>}
  </BlockStack>
);

const CampaignReport = ({ id }) => {
  const [report, setReport] = useState(null);
  const [error, setError] = useState("");
  const [recipients, setRecipients] = useState([]);
  const [recipientTotal, setRecipientTotal] = useState(0);
  const [filter, setFilter] = useState(0);
  const [q, setQ] = useState("");
  const [relaunching, setRelaunching] = useState(false);
  const [confirmStop, setConfirmStop] = useState(false);
  const [busy, setBusy] = useState(false);
  const [risk, setRisk] = useState(null);

  const load = useCallback(async () => {
    try {
      const [data, show] = await Promise.all([
        api(`/api/whatsapp/campaigns/${id}/report`),
        api(`/api/whatsapp/campaigns/${id}`),
      ]);
      setReport({ ...data, schedule_timezone: show.schedule_timezone });
    } catch (e) { setError(e.message); }
  }, [id]);

  useEffect(() => { load(); }, [load]);

  const status = report?.campaign?.status;
  useEffect(() => {
    if (!["building", "sending"].includes(status)) return undefined;
    const timer = setInterval(load, 5000);
    return () => clearInterval(timer);
  }, [status, load]);

  const statusFilter = RECIPIENT_FILTERS[filter].id;
  useEffect(() => {
    const timer = setTimeout(async () => {
      try {
        const params = new URLSearchParams({ q });
        if (statusFilter) params.set("status", statusFilter);
        const data = await api(`/api/whatsapp/campaigns/${id}/recipients?${params.toString()}`);
        setRecipients(data.recipients || []);
        setRecipientTotal(data.total || 0);
      } catch (_) { /* the summary above still loads; the list just stays as it was */ }
    }, 300);
    return () => clearTimeout(timer);
  }, [id, q, statusFilter, report?.progress_pct]);

  const act = async (action, body) => {
    setBusy(true);
    try {
      await api(`/api/whatsapp/campaigns/${id}/${action}`, { method: "POST", body });
      await load();
    } catch (e) {
      if (isQualityLowError(e) && !body?.acknowledge_risk && ["launch", "resume"].includes(action)) {
        setRisk({ action, body });
      } else {
        setError(e.message);
      }
    } finally { setBusy(false); }
  };

  const resume = () => (needsResumeConfirm(report?.campaign) ? setRisk({ action: "resume" }) : act("resume"));

  const c = report?.campaign;
  const d = report?.deliverability || {};

  const headerAction = !c
    ? undefined
    : c.status === "sending"
      ? { content: t("action_pause", "Pause"), onAction: () => act("pause"), loading: busy }
      : c.status === "paused"
        ? { content: t("action_resume", "Resume"), onAction: resume, loading: busy }
        : c.status === "retry_waiting"
          ? { content: t("action_retry", "Retry now"), onAction: () => act("retry_now"), loading: busy }
          : ["cancelled", "failed"].includes(c.status)
            ? { content: t("action_send_again", "Send again"), onAction: () => setRelaunching(true) }
            : undefined;

  const secondary =
    c && ["building", "sending", "paused", "scheduled", "retry_waiting"].includes(c.status)
      ? [{ content: t("action_cancel", "Stop campaign"), destructive: true, onAction: () => setConfirmStop(true) }]
      : undefined;

  const failures = Object.entries(report?.failure_breakdown || {}).sort((a, b) => b[1] - a[1]);
  const inProgress = c && ["building", "sending", "paused", "retry_waiting"].includes(c.status);

  return (
    <WhatsappLayout
      title={c?.name || t("results", "Campaign results")}
      titleMetadata={
        c && (
          <Badge tone={STATUS_TONE[c.status]} progress={STATUS_PROGRESS[c.status]}>
            {statusLabel(c.status)}
          </Badge>
        )
      }
      subtitle={c ? audienceSourceLabel(c.audience_source) : undefined}
      backLabel={t("back_to_campaigns", "Campaigns")}
      onBack={() => navigateTo(paths.home())}
      primaryAction={headerAction}
      secondaryActions={secondary}
    >
      <BlockStack gap="400">
        {error && <Banner tone="critical" onDismiss={() => setError("")}>{error}</Banner>}

        {!report ? (
          <Card><SkeletonBodyText lines={8} /></Card>
        ) : (
          <>
            <GuardrailBanner campaign={c} onResume={c.status === "paused" ? resume : undefined} />
            {c.status === "scheduled" && c.scheduled_at_display && !isQuietHoursHold(c) && (
              <Banner tone="info">
                {t("report_scheduled", "This campaign is scheduled for %{time}.", { time: c.scheduled_at_display })}
              </Banner>
            )}
            {c.retry_pending_count > 0 && (
              <Banner tone="info">
                {t("report_retry", "%{count} people will be retried automatically%{when}.", {
                  count: c.retry_pending_count,
                  when: c.next_retry_at_display ? ` — ${c.next_retry_at_display}` : "",
                })}
              </Banner>
            )}

            <Card>
              <BlockStack gap="400">
                {inProgress && (
                  <BlockStack gap="150">
                    <InlineStack align="space-between">
                      <Text as="span" variant="bodySm" tone="subdued">{t("report_progress", "Sending progress")}</Text>
                      <Text as="span" variant="bodySm" tone="subdued">{report.progress_pct || 0}%</Text>
                    </InlineStack>
                    <ProgressBar progress={report.progress_pct || 0} size="small" />
                  </BlockStack>
                )}
                <InlineGrid columns={{ xs: 2, sm: 3, md: 6 }} gap="400">
                  <Metric label={t("m_audience", "Audience")} value={formatNumber(d.reach)} />
                  <Metric label={t("m_sent", "Sent")} value={formatNumber(d.sent)} />
                  <Metric label={t("m_delivered", "Delivered")} value={formatNumber(d.delivered)} sub={`${percent(d.delivered, d.sent)}%`} />
                  <Metric label={t("m_read", "Read")} value={formatNumber(d.read)} sub={`${percent(d.read, d.sent)}%`} />
                  <Metric label={t("m_replied", "Replied")} value={formatNumber(d.replied)} />
                  <Metric label={t("m_failed", "Not delivered")} value={formatNumber(d.failed)} />
                </InlineGrid>
                {d.suppressed > 0 && (
                  <Text as="p" variant="bodySm" tone="subdued">
                    {t("report_skipped", "%{count} people were skipped because they opted out, unsubscribed or were missing details for the message.", { count: formatNumber(d.suppressed) })}
                  </Text>
                )}
              </BlockStack>
            </Card>

            {c.status !== "draft" && <CampaignRevenueCard campaignId={c.id} />}

            {failures.length > 0 && (
              <Card>
                <BlockStack gap="300">
                  <Text as="h2" variant="headingMd">{t("report_failures", "Why some messages weren't delivered")}</Text>
                  {failures.map(([code, n], i) => (
                    <React.Fragment key={code || "unknown"}>
                      {i > 0 && <Divider />}
                      <InlineStack align="space-between" gap="400" wrap={false}>
                        <Text as="span">{failureReason(code)}</Text>
                        <Text as="span" fontWeight="semibold">{formatNumber(n)}</Text>
                      </InlineStack>
                    </React.Fragment>
                  ))}
                </BlockStack>
              </Card>
            )}

            <Card padding="0">
              <Box padding="400" paddingBlockEnd="200">
                <BlockStack gap="300">
                  <InlineStack align="space-between" blockAlign="center" gap="200">
                    <Text as="h2" variant="headingMd">
                      {t("report_people", "People (%{count})", { count: formatNumber(recipientTotal) })}
                    </Text>
                    <Box minWidth="240px">
                      <TextField
                        labelHidden
                        label={t("search", "Search")}
                        placeholder={t("search_people", "Search by name or phone")}
                        value={q}
                        onChange={setQ}
                        clearButton
                        onClearButtonClick={() => setQ("")}
                        autoComplete="off"
                      />
                    </Box>
                  </InlineStack>
                </BlockStack>
              </Box>
              <Tabs
                tabs={RECIPIENT_FILTERS.map((f) => ({ id: f.id || "all", content: f.label() }))}
                selected={filter}
                onSelect={setFilter}
              />
              {recipients.length === 0 ? (
                <Box padding="400">
                  <Text as="p" tone="subdued">{t("report_no_people", "Nobody here yet.")}</Text>
                </Box>
              ) : (
                <DataTable
                  columnContentTypes={["text", "text", "text", "text"]}
                  headings={[
                    t("col_name", "Name"),
                    t("col_phone", "Phone"),
                    t("col_status", "Status"),
                    t("col_detail", "Details"),
                  ]}
                  rows={recipients.map((r) => [
                    r.name || "—",
                    r.phone,
                    recipientStatus(r),
                    r.status === "suppressed"
                      ? skipReason(r.suppression_reason, frequencyCapHours(c)) || ""
                      : r.error_code
                        ? failureReason(r.error_code)
                        : r.error_message || "",
                  ])}
                />
              )}
            </Card>
          </>
        )}
      </BlockStack>

      {confirmStop && c && (
        <Modal
          open
          onClose={() => setConfirmStop(false)}
          title={t("confirm_cancel_title", "Stop \"%{name}\"?", { name: c.name })}
          primaryAction={{
            content: t("action_cancel", "Stop campaign"),
            destructive: true,
            loading: busy,
            onAction: async () => { await act("cancel"); setConfirmStop(false); },
          }}
          secondaryActions={[{ content: t("keep", "Keep it"), onAction: () => setConfirmStop(false) }]}
        >
          <Modal.Section>
            <Text as="p">
              {t("confirm_cancel_body", "Nobody else will get this message. People who already received it are not affected. You can send it again later to the rest.")}
            </Text>
          </Modal.Section>
        </Modal>
      )}

      {risk && c && (
        <RiskConfirmModal
          campaign={c}
          launching={risk.action === "launch"}
          loading={busy}
          onClose={() => setRisk(null)}
          onConfirm={async () => {
            const { action, body } = risk;
            await act(action, { ...(body || {}), acknowledge_risk: true });
            setRisk(null);
          }}
        />
      )}

      {relaunching && c && (
        <RelaunchModal
          campaign={c}
          scheduleTz={report?.schedule_timezone}
          onClose={() => setRelaunching(false)}
          onConfirm={async (body) => {
            setRelaunching(false);
            await act("launch", body);
          }}
        />
      )}
    </WhatsappLayout>
  );
};

export default CampaignReport;

import React, { useState, useEffect, useCallback } from "react";
import {
  Card, BlockStack, InlineStack, InlineGrid, Box, Text, Button, Badge, DataTable, EmptyState,
  Popover, ActionList, Modal, ChoiceList, TextField, Link, SkeletonBodyText, Banner,
} from "@shopify/polaris";
import { HorizontalDotsMinor } from "@shopify/polaris-icons";
import { navigateTo } from "../../../../utils/navigate";
import { api } from "./api";
import {
  t, paths, statusLabel, STATUS_TONE, STATUS_PROGRESS, campaignTotals, percent, formatNumber,
  audienceSourceLabel,
} from "./copy";
import { useCampaignRevenue, RevenueCell } from "./CampaignRevenue";
import GuardrailBanner, {
  RiskConfirmModal, statusSubLabel, needsResumeConfirm, isQualityLowError, isGuardrailPause, isQuietHoursHold,
  qualityLow, qualityWarning,
} from "./GuardrailBanner";

const EMPTY_IMAGE = "https://cdn.shopify.com/s/files/1/0262/4071/2726/files/emptystate-files.png";

export const scheduleHelpText = (tz) => {
  if (!tz) return t("schedule_help_default", "Uses your store's timezone.");
  const now = tz.now_display ? ` ${t("schedule_now", "It is now %{time}.", { time: tz.now_display })}` : "";
  if (tz.managed === false) {
    return t("schedule_help_utc", "Your store has no timezone set, so this time is in UTC.") + now;
  }
  return t("schedule_help_tz", "Uses your store's timezone (%{zone}).", { zone: tz.label }) + now;
};

const Stat = ({ label, value, help }) => (
  <Card>
    <BlockStack gap="100">
      <Text as="p" variant="bodySm" tone="subdued">
        {label}
      </Text>
      <Text as="p" variant="headingLg">
        {value}
      </Text>
      {help && (
        <Text as="p" variant="bodySm" tone="subdued">
          {help}
        </Text>
      )}
    </BlockStack>
  </Card>
);

export const CampaignStats = ({ stats }) => {
  if (!stats) return null;
  return (
    <InlineGrid columns={{ xs: 2, md: 4 }} gap="400">
      <Stat label={t("stat_campaigns", "Campaigns sent")} value={formatNumber(stats.campaigns)} help={t("stat_period", "Last 30 days")} />
      <Stat label={t("stat_messages", "Messages sent")} value={formatNumber(stats.sent)} help={t("stat_period", "Last 30 days")} />
      <Stat
        label={t("stat_delivered", "Delivered")}
        value={`${percent(stats.delivered, stats.sent)}%`}
        help={t("stat_count", "%{count} messages", { count: formatNumber(stats.delivered) })}
      />
      <Stat
        label={t("stat_read", "Read")}
        value={`${percent(stats.read, stats.sent)}%`}
        help={t("stat_count", "%{count} messages", { count: formatNumber(stats.read) })}
      />
    </InlineGrid>
  );
};

// What the one visible button on a row does, per status. Everything else goes
// in the "More" menu so a row never shows five buttons at once.
const rowActions = (c, handlers) => {
  const { edit, report, act, relaunch, confirm, resume } = handlers;
  const cancel = {
    content: t("action_cancel", "Stop campaign"),
    destructive: true,
    onAction: () => confirm(c, "cancel"),
  };
  const remove = {
    content: t("action_delete", "Delete"),
    destructive: true,
    onAction: () => confirm(c, "delete"),
  };
  const viewReport = { content: t("action_report", "View results"), onAction: () => report(c.id) };

  switch (c.status) {
    case "draft":
      return { primary: { content: t("action_continue", "Continue editing"), onAction: () => edit(c.id) }, more: [remove] };
    case "scheduled":
      if (isQuietHoursHold(c)) return { primary: viewReport, more: [cancel] };
      return { primary: { content: t("action_send_now", "Send now"), onAction: () => act(c.id, "launch", { send_now: true }) }, more: [cancel] };
    case "sending":
      return { primary: { content: t("action_pause", "Pause"), onAction: () => act(c.id, "pause") }, more: [viewReport, cancel] };
    case "paused":
      return { primary: { content: t("action_resume", "Resume"), onAction: () => resume(c) }, more: [viewReport, cancel] };
    case "retry_waiting":
      return { primary: { content: t("action_retry", "Retry now"), onAction: () => act(c.id, "retry_now") }, more: [viewReport, cancel] };
    case "building":
      return { primary: viewReport, more: [cancel] };
    case "cancelled":
    case "failed":
      return { primary: { content: t("action_send_again", "Send again"), onAction: () => relaunch(c) }, more: [viewReport, remove] };
    default:
      return { primary: viewReport, more: [remove] };
  }
};

const MoreActions = ({ items }) => {
  const [open, setOpen] = useState(false);
  if (!items.length) return null;
  return (
    <Popover
      active={open}
      onClose={() => setOpen(false)}
      activator={
        <Button
          size="slim"
          icon={HorizontalDotsMinor}
          accessibilityLabel={t("action_more", "More actions")}
          onClick={() => setOpen((v) => !v)}
        />
      }
    >
      <ActionList
        actionRole="menuitem"
        items={items.map((item) => ({ ...item, onAction: () => { setOpen(false); item.onAction(); } }))}
      />
    </Popover>
  );
};

const CampaignsTab = ({ ready, scheduleTz, onChanged, onError }) => {
  const [campaigns, setCampaigns] = useState(null);
  const [relaunching, setRelaunching] = useState(null);
  const [confirming, setConfirming] = useState(null);
  const [busy, setBusy] = useState(false);
  const [risk, setRisk] = useState(null);
  const revenue = useCampaignRevenue((campaigns || []).filter((c) => c.status !== "draft").map((c) => c.id));

  const load = useCallback(async () => {
    try {
      const data = await api("/api/whatsapp/campaigns");
      setCampaigns(data.campaigns || []);
    } catch (e) {
      onError(e.message);
      setCampaigns((prev) => prev || []);
    }
  }, [onError]);

  useEffect(() => { load(); }, [load]);

  // Keep the numbers moving while something is going out.
  const active = (campaigns || []).some((c) => ["building", "sending"].includes(c.status));
  useEffect(() => {
    if (!active) return undefined;
    const id = setInterval(load, 5000);
    return () => clearInterval(id);
  }, [active, load]);

  const act = async (id, action, body) => {
    try {
      await api(`/api/whatsapp/campaigns/${id}/${action}`, { method: "POST", body });
      await load();
      onChanged();
    } catch (e) {
      const campaign = (campaigns || []).find((c) => c.id === id);
      if (isQualityLowError(e) && !body?.acknowledge_risk && ["launch", "resume"].includes(action) && campaign) {
        setRisk({ campaign, action, body });
      } else {
        onError(e.message);
      }
    }
  };

  const confirmAction = async () => {
    const { campaign, kind } = confirming;
    setBusy(true);
    try {
      if (kind === "delete") {
        await api(`/api/whatsapp/campaigns/${campaign.id}`, { method: "DELETE" });
      } else {
        await api(`/api/whatsapp/campaigns/${campaign.id}/cancel`, { method: "POST" });
      }
      setConfirming(null);
      await load();
      onChanged();
    } catch (e) {
      onError(e.message);
      setConfirming(null);
    } finally { setBusy(false); }
  };

  const handlers = {
    edit: (id) => navigateTo(paths.edit(id)),
    report: (id) => navigateTo(paths.report(id)),
    act,
    relaunch: setRelaunching,
    confirm: (campaign, kind) => setConfirming({ campaign, kind }),
    resume: (campaign) => (needsResumeConfirm(campaign) ? setRisk({ campaign, action: "resume" }) : act(campaign.id, "resume")),
  };

  if (campaigns === null) {
    return (
      <Card>
        <SkeletonBodyText lines={6} />
      </Card>
    );
  }

  if (campaigns.length === 0) {
    return (
      <Card>
        <EmptyState
          heading={ready ? t("empty_title", "Send your first campaign") : t("empty_title_setup", "No campaigns yet")}
          action={ready ? { content: t("create_campaign", "Create campaign"), onAction: () => navigateTo(paths.newCampaign()) } : undefined}
          image={EMPTY_IMAGE}
        >
          <Text as="p">
            {ready
              ? t("empty_body", "Announce a sale, a new drop or a restock to your customers on WhatsApp. You choose who gets it, see exactly what they'll receive, and track who read it.")
              : t("empty_body_setup", "Finish the setup steps above and your first campaign is a few clicks away.")}
          </Text>
        </EmptyState>
      </Card>
    );
  }

  const inFlight = (c) => !["draft", "completed", "cancelled", "failed"].includes(c.status);
  const bannerCampaign =
    campaigns.find(isGuardrailPause) || campaigns.find((c) => inFlight(c) && (qualityLow(c) || qualityWarning(c)));

  const rows = campaigns.map((c) => {
    const totals = campaignTotals(c);
    const subLabel = statusSubLabel(c);
    const { primary, more } = rowActions(c, handlers);
    const when = c.completed_at || c.started_at;
    const detail =
      c.status === "scheduled" && c.scheduled_at_display
        ? t("row_scheduled_for", "Sends %{time}", { time: c.scheduled_at_display })
        : [audienceSourceLabel(c.audience_source), when ? new Date(when).toLocaleDateString() : null]
            .filter(Boolean)
            .join(" · ");
    return [
      <BlockStack gap="050" key={`n${c.id}`}>
        <Link removeUnderline monochrome onClick={() => (c.status === "draft" ? handlers.edit(c.id) : handlers.report(c.id))}>
          <Text as="span" fontWeight="semibold">{c.name}</Text>
        </Link>
        <Text as="span" variant="bodySm" tone="subdued">{detail}</Text>
        {subLabel && (
          <Text as="span" variant="bodySm" tone={isGuardrailPause(c) ? "critical" : "subdued"}>{subLabel}</Text>
        )}
        {c.status === "failed" && c.last_error && (
          <Text as="span" variant="bodySm" tone="critical">{c.last_error}</Text>
        )}
      </BlockStack>,
      <Badge key={`s${c.id}`} tone={STATUS_TONE[c.status]} progress={STATUS_PROGRESS[c.status]}>
        {statusLabel(c.status)}
      </Badge>,
      c.status === "draft" ? "—" : formatNumber(totals.sent),
      c.status === "draft" || !totals.sent ? "—" : `${percent(totals.delivered, totals.sent)}%`,
      c.status === "draft" || !totals.sent ? "—" : `${percent(totals.read, totals.sent)}%`,
      c.status === "draft" ? "—" : <RevenueCell key={`r${c.id}`} data={revenue[c.id]} />,
      <InlineStack key={`a${c.id}`} gap="100" wrap={false} align="end">
        <Button size="slim" onClick={primary.onAction}>{primary.content}</Button>
        <MoreActions items={more} />
      </InlineStack>,
    ];
  });

  return (
    <>
      {bannerCampaign && (
        <Box paddingBlockEnd="400">
          <GuardrailBanner
            campaign={bannerCampaign}
            named
            onResume={isGuardrailPause(bannerCampaign) ? () => handlers.resume(bannerCampaign) : undefined}
          />
        </Box>
      )}
      <Card padding="0">
        <DataTable
          columnContentTypes={["text", "text", "numeric", "numeric", "numeric", "numeric", "numeric"]}
          headings={[
            t("col_campaign", "Campaign"),
            t("col_status", "Status"),
            t("col_sent", "Sent"),
            t("col_delivered", "Delivered"),
            t("col_read", "Read"),
            t("revenue_column", "Orders placed"),
            "",
          ]}
          rows={rows}
          verticalAlign="middle"
        />
      </Card>

      {relaunching && (
        <RelaunchModal
          campaign={relaunching}
          scheduleTz={scheduleTz}
          onClose={() => setRelaunching(null)}
          onConfirm={async (body) => {
            const id = relaunching.id;
            setRelaunching(null);
            await act(id, "launch", body);
          }}
        />
      )}

      {risk && (
        <RiskConfirmModal
          campaign={risk.campaign}
          launching={risk.action === "launch"}
          onClose={() => setRisk(null)}
          onConfirm={async () => {
            const { campaign, action, body } = risk;
            setRisk(null);
            await act(campaign.id, action, { ...(body || {}), acknowledge_risk: true });
          }}
        />
      )}

      {confirming && (
        <Modal
          open
          onClose={() => setConfirming(null)}
          title={
            confirming.kind === "delete"
              ? t("confirm_delete_title", "Delete \"%{name}\"?", { name: confirming.campaign.name })
              : t("confirm_cancel_title", "Stop \"%{name}\"?", { name: confirming.campaign.name })
          }
          primaryAction={{
            content: confirming.kind === "delete" ? t("action_delete", "Delete") : t("action_cancel", "Stop campaign"),
            destructive: true,
            loading: busy,
            onAction: confirmAction,
          }}
          secondaryActions={[{ content: t("keep", "Keep it"), onAction: () => setConfirming(null) }]}
        >
          <Modal.Section>
            <Text as="p">
              {confirming.kind === "delete"
                ? t("confirm_delete_body", "The campaign and its results are removed. This can't be undone.")
                : t("confirm_cancel_body", "Nobody else will get this message. People who already received it are not affected. You can send it again later to the rest.")}
            </Text>
          </Modal.Section>
        </Modal>
      )}
    </>
  );
};

export const RelaunchModal = ({ campaign, scheduleTz, onClose, onConfirm }) => {
  const [mode, setMode] = useState(["now"]);
  const [at, setAt] = useState("");
  const later = mode[0] === "later";

  return (
    <Modal
      open
      onClose={onClose}
      title={t("relaunch_title", "Send \"%{name}\" again", { name: campaign.name })}
      primaryAction={{
        content: later ? t("schedule", "Schedule") : t("action_send_now", "Send now"),
        onAction: () => onConfirm(later ? { scheduled_at: at } : { send_now: true }),
        disabled: later && !at,
      }}
      secondaryActions={[{ content: t("back", "Back"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          <ChoiceList
            title={t("when_title", "When should it go out?")}
            choices={[
              { label: t("when_now", "Right away"), value: "now" },
              { label: t("when_later", "At a later time"), value: "later" },
            ]}
            selected={mode}
            onChange={setMode}
          />
          {later && (
            <TextField
              label={t("send_at", "Date and time")}
              type="datetime-local"
              value={at}
              onChange={setAt}
              min={scheduleTz?.now}
              helpText={scheduleHelpText(scheduleTz)}
              autoComplete="off"
            />
          )}
          <Box>
            <Banner tone="info">
              {t("relaunch_note", "Only people who haven't received it yet are messaged. Nobody gets it twice.")}
            </Banner>
          </Box>
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default CampaignsTab;

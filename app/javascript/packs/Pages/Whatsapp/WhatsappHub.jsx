import React, { useEffect, useMemo, useState } from "react";
import {
  Card,
  BlockStack,
  Box,
  Text,
  InlineStack,
  InlineGrid,
  Badge,
  Banner,
  Button,
  Spinner,
  Icon,
  SkeletonBodyText,
} from "@shopify/polaris";
import { CircleTickMinor } from "@shopify/polaris-icons";
import { camelize } from "humps";
import useApi from "../../Hooks/useApi";
import WhatsappLayout from "./WhatsappLayout";
import FeatureCallout from "../../Components/FeatureCallout";
import { NotificationPauseButton } from "./WhatsappEventMappings";
import { navigateTo } from "../../../utils/navigate";
import { inboxApi } from "./Inbox/api";
import { UNREAD_EVENT } from "./Inbox/format";

import I18n from "../../i18n-lang";

const BRANDED_WHATSAPP_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-11_at_3.15.31_PM.jpg?v=1789127006";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_hub.${key}`, { defaultValue, ...opts });

const NOTIFICATIONS_PATH = "/features/whatsapp/templates?tab=mappings";
const TEMPLATES_PATH = "/features/whatsapp/templates";
const LOGS_PATH = "/features/whatsapp/logs";
const ACCOUNT_PATH = "/features/whatsapp/account";
const CAMPAIGNS_PATH = "/features/whatsapp-campaigns";
const INBOX_PATH = "/features/whatsapp/inbox";

const ORDER_DRIVING_EVENTS = ["abandoned_cart", "cart_abandoned", "browse_abandoned", "cod_to_prepaid"];
const UNPAUSABLE_EVENTS = ["pre_order_otp"];

const formatNumber = (n) => Number(n || 0).toLocaleString("en-IN");
const pct = (part, whole) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "—");
const formatMoney = (amount, currency) => {
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: currency || "INR",
      maximumFractionDigits: 0,
    }).format(Number(amount || 0));
  } catch (e) {
    return `${currency || ""} ${formatNumber(Math.round(Number(amount || 0)))}`.trim();
  }
};

const engagementLine = (row, days) => {
  const parts = [
    t("engagement_read", "Read %{rate}", { rate: pct(row.read, row.sent) }),
  ];
  if (Number(row.clicked) > 0) parts.push(t("engagement_clicked", "Clicked %{rate}", { rate: pct(row.clicked, row.sent) }));
  parts.push(t("engagement_replied", "Replied %{rate}", { rate: pct(row.replied, row.sent) }));
  return `${parts.join(" · ")} · ${t("engagement_days", "last %{days} days", { days })}`;
};

const statusBadge = (status) => {
  switch (status) {
    case "verified":
      return <Badge tone="success">{I18n.t("whatsapp_hub.verified")}</Badge>;
    case "pending_verification":
      return <Badge tone="attention">{I18n.t("whatsapp_hub.pending_verification")}</Badge>;
    case "disabled":
      return <Badge tone="critical">{I18n.t("whatsapp_hub.disabled")}</Badge>;
    default:
      return <Badge>{I18n.t("whatsapp_hub.not_connected")}</Badge>;
  }
};

const qualityTone = (q) => {
  switch (String(q || "").toUpperCase()) {
    case "GREEN":
    case "HIGH":
      return "success";
    case "YELLOW":
    case "MEDIUM":
      return "attention";
    case "RED":
    case "LOW":
      return "critical";
    default:
      return undefined;
  }
};

const qualityLabel = (q) => {
  switch (String(q || "").toUpperCase()) {
    case "GREEN":
    case "HIGH":
      return t("quality_high", "Quality: high");
    case "YELLOW":
    case "MEDIUM":
      return t("quality_medium", "Quality: medium");
    case "RED":
    case "LOW":
      return t("quality_low", "Quality: low");
    default:
      return t("quality_unknown", "Quality: not rated yet");
  }
};

const WhatsappHub = () => {
  const [{ data: account, loading }] = useApi(
    { url: "/api/whatsapp/account", method: "GET" },
    { manual: false }
  );
  const [{ data: templatesData }] = useApi(
    { url: "/api/whatsapp/templates", method: "GET" },
    { manual: false }
  );

  const connected = account?.connected;
  const templates = templatesData?.templates || [];
  const templateCounts = {
    approved: templates.filter((x) => x.status === "approved").length,
    pending: templates.filter((x) => x.status === "pending").length,
    rejected: templates.filter((x) => x.status === "rejected").length,
  };

  return (
    <WhatsappLayout
      title={I18n.t("whatsapp_hub.branded_whatsapp")}
      subtitle={I18n.t("whatsapp_hub.send_order_updates_from_your_own")}
      hideBack
    >
      {loading && !account ? (
        <Card padding="600">
          <InlineStack gap="200" align="center">
            <Spinner size="small" />
            <Text as="span">{I18n.t("whatsapp_hub.loading")}</Text>
          </InlineStack>
        </Card>
      ) : connected ? (
        <ConnectedHub account={account} templateCounts={templateCounts} />
      ) : (
        <NotConnectedHub />
      )}
    </WhatsappLayout>
  );
};

const NotConnectedHub = () => (
  <BlockStack gap="400">
    <FeatureCallout
      illustration="whatsapp"
      image={BRANDED_WHATSAPP_CALLOUT_IMAGE}
      title={I18n.t("whatsapp_hub.branded_whatsapp")}
      description={I18n.t("whatsapp_hub.order_updates_arrive_from_your_own")}
      docsUrl="https://codking.tech/documentation/"
      showChat
    />
    <Card padding="600">
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center">
          <Text variant="headingMd" as="h2">
            {I18n.t("whatsapp_hub.connection")}
          </Text>
          {statusBadge("not_connected")}
        </InlineStack>
        <Banner tone="info">
          {I18n.t("whatsapp_hub.no_whatsapp_account_connected_yet_connect")}
        </Banner>
      </BlockStack>
    </Card>
    <Card padding="600">
      <BlockStack gap="300">
        <Text variant="headingMd" as="h2">
          {I18n.t("whatsapp_hub.get_started")}
        </Text>
        <Text as="p" tone="subdued">
          {I18n.t("whatsapp_hub.connect_your_whatsapp_business_account_to")}
        </Text>
        <InlineStack gap="300">
          <Button variant="primary" onClick={() => navigateTo(ACCOUNT_PATH)}>
            {I18n.t("whatsapp_hub.connect_whatsapp_account")}
          </Button>
          {/* Messages sent from a since-disconnected number are kept — let merchants see them. */}
          <Button onClick={() => navigateTo(LOGS_PATH)}>
            {t("view_past_activity", "View past activity")}
          </Button>
        </InlineStack>
      </BlockStack>
    </Card>
  </BlockStack>
);

const ConnectedHub = ({ account, templateCounts }) => {
  const [{ data: eventsData, loading: eventsLoading }] = useApi(
    { url: "/api/whatsapp/events", method: "GET" },
    { manual: false }
  );
  const [{ data: bindingsData, loading: bindingsLoading }, refetchBindings] = useApi(
    { url: "/api/whatsapp/template_bindings", method: "GET" },
    { manual: false }
  );
  const [{ data: attribution }] = useApi(
    { url: "/api/whatsapp/attribution/notifications", method: "GET", params: { days: 30 } },
    { manual: false }
  );
  const [{ data: engagement }] = useApi(
    { url: "/api/whatsapp/attribution/engagement", method: "GET", params: { days: 30 } },
    { manual: false }
  );
  const [{ data: summary, loading: summaryLoading }] = useApi(
    { url: "/api/whatsapp/message_logs", method: "GET", params: { days: 7, summary: 1 } },
    { manual: false }
  );
  const [{ data: overview }] = useApi(
    { url: "/api/whatsapp/campaigns/overview", method: "GET" },
    { manual: false }
  );

  const events = useMemo(
    () => (eventsData?.events || []).filter((e) => e.kind !== "campaign"),
    [eventsData]
  );
  const bindings = bindingsData?.bindings || [];
  const liveCount = events.filter((e) =>
    bindings.some((b) => b.eventTypeKey === e.key && !b.paused)
  ).length;
  const revenueByEvent = useMemo(() => {
    const map = {};
    [...(attribution?.notifications || []), ...(attribution?.conversions || [])].forEach((row) => {
      if (row?.eventTypeKey) map[row.eventTypeKey] = row;
    });
    return map;
  }, [attribution]);

  const engagementByEvent = useMemo(() => {
    const map = {};
    (engagement?.events || []).forEach((row) => {
      if (row?.eventTypeKey) map[row.eventTypeKey] = row;
    });
    return map;
  }, [engagement]);

  const setupDone = templateCounts.approved > 0 && bindings.length > 0;

  return (
    <BlockStack gap="400">
      <AccountStrip account={account} />
      <QualityBanner quality={account.qualityRating} />
      {!setupDone && !bindingsLoading && (
        <SetupChecklist
          hasApprovedTemplate={templateCounts.approved > 0}
          hasPendingTemplate={templateCounts.pending > 0}
          hasNotification={bindings.length > 0}
        />
      )}
      <StatsRow summary={summary} loading={summaryLoading && !summary} />
      <NotificationsCard
        events={events}
        bindings={bindings}
        byEvent={summary?.byEvent || {}}
        liveCount={liveCount}
        revenueByEvent={revenueByEvent}
        engagementByEvent={engagementByEvent}
        engagementDays={engagement?.days || 30}
        attributionDays={attribution?.days || 30}
        onPauseChanged={() => refetchBindings()}
        loading={(eventsLoading && !eventsData) || (bindingsLoading && !bindingsData)}
      />
      <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
        <CampaignsCard overview={overview} hasTemplate={templateCounts.approved > 0} />
        <TemplatesCard counts={templateCounts} />
      </InlineGrid>
    </BlockStack>
  );
};

const AccountStrip = ({ account }) => (
  <Card padding="400">
    <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
      <BlockStack gap="050">
        <InlineStack gap="200" blockAlign="center">
          <Text as="h2" variant="headingMd">
            {account.displayPhoneNumber || "—"}
          </Text>
          {account.verifiedName && (
            <Text as="span" tone="subdued">
              · {account.verifiedName}
            </Text>
          )}
        </InlineStack>
        <InlineStack gap="200">
          {statusBadge(account.status)}
          <Badge tone={qualityTone(account.qualityRating)}>
            {qualityLabel(account.qualityRating)}
          </Badge>
        </InlineStack>
      </BlockStack>
      <Button variant="plain" onClick={() => navigateTo(ACCOUNT_PATH)}>
        {t("manage_account", "Manage account")}
      </Button>
    </InlineStack>
  </Card>
);

const QualityBanner = ({ quality }) => {
  const q = String(quality || "").toUpperCase();
  if (q === "RED" || q === "LOW") {
    return (
      <Banner
        tone="critical"
        title={t("quality_banner_low_title", "Your number quality is low")}
        action={{ content: t("quality_banner_action", "View number"), onAction: () => navigateTo(ACCOUNT_PATH) }}
      >
        {t(
          "quality_banner_low_body",
          "Many customers have blocked or reported your messages. WhatsApp may limit how many messages you can send. Send fewer marketing messages and only to customers who expect them."
        )}
      </Banner>
    );
  }
  if (q === "YELLOW" || q === "MEDIUM") {
    return (
      <Banner
        tone="warning"
        title={t("quality_banner_medium_title", "Your number quality has dropped")}
        action={{ content: t("quality_banner_action", "View number"), onAction: () => navigateTo(ACCOUNT_PATH) }}
      >
        {t(
          "quality_banner_medium_body",
          "Some customers have blocked or reported your messages. Slow down marketing messages for a few days so your number keeps its daily messaging limit."
        )}
      </Banner>
    );
  }
  return null;
};

const SetupChecklist = ({ hasApprovedTemplate, hasPendingTemplate, hasNotification }) => {
  const steps = [
    {
      done: hasApprovedTemplate,
      title: t("checklist_template", "Get a message template approved"),
      hint: hasPendingTemplate
        ? t("checklist_template_pending", "Waiting for WhatsApp to approve — usually a few hours.")
        : t("checklist_template_hint", "Pick a pre-made template or write your own."),
      cta: t("checklist_template_cta", "Add template"),
      to: TEMPLATES_PATH,
    },
    {
      done: hasNotification,
      title: t("checklist_notification", "Turn on your first notification"),
      hint: t("checklist_notification_hint", "Choose which template goes out when an order is placed, shipped, and so on."),
      cta: t("checklist_notification_cta", "Set up notification"),
      to: NOTIFICATIONS_PATH,
    },
  ];
  const next = steps.findIndex((s) => !s.done);

  return (
    <Card padding="400">
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h2" variant="headingMd">
            {t("checklist_title", "Finish setting up")}
          </Text>
          <Text as="span" tone="subdued" variant="bodySm">
            {t("checklist_progress", "%{done} of %{total} done", {
              done: steps.filter((s) => s.done).length,
              total: steps.length,
            })}
          </Text>
        </InlineStack>
        {steps.map((s, i) => (
          <InlineStack key={s.title} align="space-between" blockAlign="center" gap="300" wrap={false}>
            <InlineStack gap="300" blockAlign="start" wrap={false}>
              <Box minWidth="20px">
                {s.done ? (
                  <Icon source={CircleTickMinor} tone="success" />
                ) : (
                  <Box
                    borderWidth="050"
                    borderColor="border"
                    borderRadius="full"
                    minWidth="20px"
                    minHeight="20px"
                  />
                )}
              </Box>
              <BlockStack gap="050">
                <Text as="span" fontWeight="medium" tone={s.done ? "subdued" : undefined}>
                  {s.title}
                </Text>
                {!s.done && (
                  <Text as="span" tone="subdued" variant="bodySm">
                    {s.hint}
                  </Text>
                )}
              </BlockStack>
            </InlineStack>
            {!s.done && (
              <Button
                variant={i === next ? "primary" : undefined}
                onClick={() => navigateTo(s.to)}
              >
                {s.cta}
              </Button>
            )}
          </InlineStack>
        ))}
      </BlockStack>
    </Card>
  );
};

const Stat = ({ label, value, tone, action }) => (
  <Box background="bg-surface-secondary" padding="300" borderRadius="200">
    <BlockStack gap="100">
      <Text as="span" tone="subdued" variant="bodySm">
        {label}
      </Text>
      <InlineStack gap="200" blockAlign="baseline">
        <Text as="span" variant="headingLg" tone={tone}>
          {value}
        </Text>
        {action}
      </InlineStack>
    </BlockStack>
  </Box>
);

const InboxLink = () => {
  const [unread, setUnread] = useState(0);

  useEffect(() => {
    let alive = true;
    inboxApi
      .summary()
      .then((data) => alive && setUnread(Number(data?.unread_conversations || 0)))
      .catch(() => {});
    const onUnread = (e) => setUnread(Number(e.detail || 0));
    window.addEventListener(UNREAD_EVENT, onUnread);
    return () => {
      alive = false;
      window.removeEventListener(UNREAD_EVENT, onUnread);
    };
  }, []);

  return (
    <InlineStack gap="100" blockAlign="center">
      <Button variant="plain" onClick={() => navigateTo(INBOX_PATH)}>
        {I18n.t("whatsapp_inbox.hub_link", { defaultValue: "Inbox" })}
      </Button>
      {unread > 0 && (
        <Badge tone="info" size="small">
          {String(unread)}
        </Badge>
      )}
    </InlineStack>
  );
};

// Each log row holds its *current* status, so a read message is counted only
// under `read`: delivered = delivered + read.
const StatsRow = ({ summary, loading }) => {
  const s = summary?.stats || {};
  const delivered = (s.delivered || 0) + (s.read || 0);
  const failed = (s.failed || 0) + (s.dropped || 0);
  const settled = delivered + (s.sent || 0) + failed;
  const total = summary?.total || 0;

  return (
    <BlockStack gap="200">
      <InlineStack align="space-between" blockAlign="center">
        <Text as="h2" variant="headingSm" tone="subdued">
          {t("last_7_days", "Last 7 days")}
        </Text>
        <InlineStack gap="400">
          <InboxLink />
          <Button variant="plain" onClick={() => navigateTo(`${INBOX_PATH}/ai`)}>
            {I18n.t("whatsapp_inbox.ai.hub_link", { defaultValue: "AI agent" })}
          </Button>
          <Button variant="plain" onClick={() => navigateTo(LOGS_PATH)}>
            {t("view_activity", "View activity")}
          </Button>
        </InlineStack>
      </InlineStack>
      <InlineGrid columns={{ xs: 2, md: 4 }} gap="300">
        <Stat label={t("stat_sent", "Messages sent")} value={loading ? "…" : formatNumber(total)} />
        <Stat label={t("stat_delivered", "Delivered")} value={loading ? "…" : pct(delivered, settled)} />
        <Stat label={t("stat_read", "Read")} value={loading ? "…" : pct(s.read || 0, settled)} />
        <Stat
          label={t("stat_failed", "Failed")}
          value={loading ? "…" : formatNumber(failed)}
          tone={failed > 0 ? "critical" : undefined}
          action={
            failed > 0 ? (
              <Button variant="plain" onClick={() => navigateTo(`${LOGS_PATH}?status=failed`)}>
                {t("view", "View")}
              </Button>
            ) : null
          }
        />
      </InlineGrid>
    </BlockStack>
  );
};

const NotificationsCard = ({
  events,
  bindings,
  byEvent,
  liveCount,
  revenueByEvent,
  engagementByEvent = {},
  engagementDays = 30,
  attributionDays,
  onPauseChanged,
  loading,
}) => {
  const [pauseError, setPauseError] = useState(null);

  return (
    <Card padding="0">
      {pauseError && (
        <Box padding="400" paddingBlockEnd="0">
          <Banner tone="critical" onDismiss={() => setPauseError(null)}>
            {pauseError}
          </Banner>
        </Box>
      )}
      <Box padding="400" paddingBlockEnd="200">
        <InlineStack align="space-between" blockAlign="center">
          <BlockStack gap="050">
            <Text as="h2" variant="headingMd">
              {I18n.t("whatsapp_hub.customer_notifications")}
            </Text>
            <Text as="p" tone="subdued" variant="bodySm">
              {t("notifications_live_count", "%{live} of %{total} turned on", {
                live: liveCount,
                total: events.length,
              })}
            </Text>
          </BlockStack>
          <Button variant="plain" onClick={() => navigateTo(NOTIFICATIONS_PATH)}>
            {t("manage_all", "Manage all")}
          </Button>
        </InlineStack>
      </Box>
      {loading ? (
        <Box padding="400">
          <SkeletonBodyText lines={4} />
        </Box>
      ) : (
        events.map((event) => {
          const eventBindings = bindings
            .filter((b) => b.eventTypeKey === event.key)
            .sort((a, b) => (a.stageIndex || 0) - (b.stageIndex || 0));
          const live = eventBindings.length > 0;
          const paused = live && eventBindings.some((b) => b.paused);
          const pausable = live && !UNPAUSABLE_EVENTS.includes(event.key) && eventBindings[0].pausable !== false;
          const sent = byEvent[camelize(event.key)] || 0;
          const engagementRow = engagementByEvent[event.key];
          const revenue = ORDER_DRIVING_EVENTS.includes(event.key) ? revenueByEvent[event.key] : null;
          const awaitingApproval = eventBindings.some(
            (b) => b.templateStatus && b.templateStatus !== "approved"
          );

          let detail;
          if (!live) {
            detail = event.description || t("not_set_up", "Not set up");
          } else {
            const names = eventBindings.map((b) => b.templateName).filter(Boolean);
            const templateText =
              eventBindings.length > 1
                ? t("n_messages", "%{count} messages", { count: eventBindings.length })
                : names[0] || "—";
            detail = `${templateText} · ${t("sent_this_week", "%{count} sent this week", {
              count: formatNumber(sent),
            })}`;
          }

          return (
            <Box
              key={event.key}
              paddingInline="400"
              paddingBlock="300"
              borderBlockStartWidth="025"
              borderColor="border-secondary"
            >
              <InlineStack align="space-between" blockAlign="center" gap="300" wrap={false}>
                <BlockStack gap="050">
                  <InlineStack gap="200" blockAlign="center">
                    <Text as="span" fontWeight="medium">
                      {event.label}
                    </Text>
                    {paused && <Badge tone="warning">{t("paused", "Paused")}</Badge>}
                    {live && !paused && !awaitingApproval && <Badge tone="success">{t("live", "Live")}</Badge>}
                    {live && !paused && awaitingApproval && (
                      <Badge tone="attention">{t("awaiting_approval", "Awaiting approval")}</Badge>
                    )}
                  </InlineStack>
                  <Text as="span" tone="subdued" variant="bodySm" truncate>
                    {detail}
                  </Text>
                  {live && engagementRow && Number(engagementRow.sent) > 0 && (
                    <Text as="span" variant="bodySm" tone="subdued">
                      {engagementLine(engagementRow, engagementDays)}
                    </Text>
                  )}
                  {live && revenue && Number(revenue.orders) > 0 && (
                    <Text as="span" variant="bodySm" tone="success">
                      {t("revenue_line", "%{revenue} from %{count} orders placed (last %{days} days)", {
                        revenue: formatMoney(revenue.revenue, revenue.currency),
                        count: formatNumber(revenue.orders),
                        days: attributionDays,
                      })}
                    </Text>
                  )}
                </BlockStack>
                <InlineStack gap="300" blockAlign="center" wrap={false}>
                  {pausable && (
                    <NotificationPauseButton
                      eventKey={event.key}
                      paused={paused}
                      variant="plain"
                      onChanged={() => {
                        setPauseError(null);
                        onPauseChanged();
                      }}
                      onError={setPauseError}
                    />
                  )}
                  <Button
                    variant={live ? "plain" : undefined}
                    onClick={() => navigateTo(NOTIFICATIONS_PATH)}
                  >
                    {live ? t("edit", "Edit") : t("set_up", "Set up")}
                  </Button>
                </InlineStack>
              </InlineStack>
            </Box>
          );
        })
      )}
    </Card>
  );
};

const CampaignsCard = ({ overview, hasTemplate }) => {
  const last30 = overview?.last30Days;
  let summaryText;
  if (!overview) {
    summaryText = "…";
  } else if (!overview.campaignsCount) {
    summaryText = hasTemplate
      ? t("campaigns_empty", "Send an offer or announcement to your customers, now or scheduled.")
      : t("campaigns_need_template", "Campaigns need an approved template first.");
  } else if (last30?.campaigns) {
    summaryText = t("campaigns_last_30", "Last 30 days: %{campaigns} sent to %{sent} people · %{read} read", {
      campaigns: last30.campaigns,
      sent: formatNumber(last30.sent),
      read: pct(last30.read, last30.sent),
    });
  } else {
    summaryText = t("campaigns_none_recent", "No campaigns in the last 30 days.");
  }

  return (
    <Card padding="400">
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center">
          <Text as="h2" variant="headingMd">
            {t("campaigns", "Campaigns")}
          </Text>
          <Button onClick={() => navigateTo(CAMPAIGNS_PATH)}>
            {t("new_campaign", "New campaign")}
          </Button>
        </InlineStack>
        <Text as="p" tone="subdued" variant="bodySm">
          {summaryText}
        </Text>
        <InlineStack gap="400">
          <Button variant="plain" onClick={() => navigateTo(CAMPAIGNS_PATH)}>
            {t("all_campaigns", "All campaigns")}
          </Button>
          <Button variant="plain" onClick={() => navigateTo(`${CAMPAIGNS_PATH}?tab=audiences`)}>
            {t("audiences", "Audiences")}
          </Button>
        </InlineStack>
      </BlockStack>
    </Card>
  );
};

const TemplatesCard = ({ counts }) => (
  <Card padding="400">
    <BlockStack gap="300">
      <InlineStack align="space-between" blockAlign="center">
        <Text as="h2" variant="headingMd">
          {I18n.t("whatsapp_hub.my_templates")}
        </Text>
        <Button onClick={() => navigateTo(TEMPLATES_PATH)}>
          {t("new_template", "New template")}
        </Button>
      </InlineStack>
      <InlineStack gap="200">
        <Badge tone="success">
          {t("n_approved", "%{count} approved", { count: counts.approved })}
        </Badge>
        {counts.pending > 0 && (
          <Badge tone="attention">
            {t("n_pending", "%{count} pending", { count: counts.pending })}
          </Badge>
        )}
        {counts.rejected > 0 && (
          <Badge tone="critical">
            {t("n_rejected", "%{count} rejected", { count: counts.rejected })}
          </Badge>
        )}
      </InlineStack>
      <Box>
        <Button variant="plain" onClick={() => navigateTo(TEMPLATES_PATH)}>
          {t("manage_templates", "Manage templates")}
        </Button>
      </Box>
    </BlockStack>
  </Card>
);

export default WhatsappHub;

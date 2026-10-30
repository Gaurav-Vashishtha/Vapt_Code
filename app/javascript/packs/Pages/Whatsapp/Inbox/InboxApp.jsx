import React, { useCallback, useEffect, useState } from "react";
import { BlockStack, Card, InlineGrid, InlineStack, Modal, Spinner, Text, useBreakpoints } from "@shopify/polaris";
import InboxFullscreen from "./InboxFullscreen";
import { navigateTo } from "../../../../utils/navigate";
import InboxSettingsPage from "./Settings/InboxSettingsPage";
import AiAgentPage from "./Ai/AiAgentPage";
import { AI_BASE } from "./Ai/api";
import { inboxApi } from "./api";
import { INBOX_BASE, INBOX_SETTINGS_PATH, conversationPath, t } from "./format";
import ConnectEmptyState from "./ConnectEmptyState";
import ReportCard from "./ReportCard";
import ConversationList from "./ConversationList";
import ConversationView from "./ConversationView";
import CustomerPanel from "./CustomerPanel";

const WHATSAPP_HOME = "/features/whatsapp";

export const isInboxPath = (path) => path === INBOX_BASE || path.startsWith(`${INBOX_BASE}/`);

const PANE_HEIGHT = "max(360px, calc(100vh - 230px))";
const THREAD_HEIGHT = "max(280px, calc(100vh - 400px))";

const parsePath = (path) => {
  const rest = path.slice(INBOX_BASE.length).replace(/^\/+|\/+$/g, "");
  if (rest === "settings") return { view: "settings" };
  if (rest === "ai" || rest.startsWith("ai/")) return { view: "ai", tab: rest.split("/")[1] || "setup" };
  if (/^\d+$/.test(rest)) return { view: "inbox", conversationId: Number(rest) };
  return { view: "inbox", conversationId: null };
};

export const RedirectToInbox = () => {
  useEffect(() => {
    window.history.replaceState({}, "", INBOX_BASE);
    window.dispatchEvent(new PopStateEvent("popstate"));
  }, []);
  return null;
};

const SelectPrompt = () => (
  <Card>
    <BlockStack gap="200" inlineAlign="center">
      <Text as="h2" variant="headingSm">
        {t("thread.select_title", "Pick a conversation")}
      </Text>
      <Text as="p" tone="subdued" alignment="center">
        {t("thread.select_body", "Choose a customer on the left to read and reply to their messages.")}
      </Text>
    </BlockStack>
  </Card>
);

const InboxHome = ({ conversationId }) => {
  const { mdUp, lgUp } = useBreakpoints();
  const [summary, setSummary] = useState(null);
  const [agents, setAgents] = useState([]);
  const [labels, setLabels] = useState([]);
  const [active, setActive] = useState(null);
  const [insert, setInsert] = useState(null);
  const [customerOpen, setCustomerOpen] = useState(false);

  useEffect(() => {
    let alive = true;
    inboxApi
      .summary()
      .then((data) => alive && setSummary(data))
      .catch(() => alive && setSummary({ enabled: true }));
    inboxApi
      .me()
      .then((data) => alive && setAgents(data.agents || (data.agent ? [data.agent] : [])))
      .catch(() => {});
    inboxApi
      .labels()
      .then((data) => alive && setLabels(data.labels || []))
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, []);

  useEffect(() => {
    setActive(null);
    setInsert(null);
    setCustomerOpen(false);
  }, [conversationId]);

  const onSelect = useCallback((id) => navigateTo(conversationPath(id)), []);
  const toList = useCallback(() => navigateTo(INBOX_BASE), []);
  const onInsert = useCallback((text) => {
    setInsert({ text, nonce: Date.now() });
    setCustomerOpen(false);
  }, []);

  const layout = (body) => (
    <InboxFullscreen
      title={t("title", "WhatsApp inbox")}
      onClose={() => navigateTo(WHATSAPP_HOME)}
      onSettings={() => navigateTo(INBOX_SETTINGS_PATH)}
      onAi={() => navigateTo(AI_BASE)}
    >
      {body}
    </InboxFullscreen>
  );

  if (!summary) {
    return layout(
      <InlineStack align="center">
        <Spinner accessibilityLabel={t("list.loading", "Loading conversations")} />
      </InlineStack>,
    );
  }
  if (summary.enabled === false) return layout(<ConnectEmptyState />);

  const showList = mdUp || !conversationId;
  const showThread = mdUp || !!conversationId;
  const showPanel = lgUp && !!conversationId && !!active;
  const columns = lgUp && conversationId ? "320px minmax(0, 1fr) 300px" : mdUp ? "300px minmax(0, 1fr)" : "minmax(0, 1fr)";

  const panel = active && (
    <CustomerPanel conversation={active} onInsert={onInsert} onConversationChange={setActive} />
  );

  return layout(
    <BlockStack gap="400">
      <ReportCard />
      <InlineGrid columns={columns} gap="400" alignItems="start">
        {showList && (
          <ConversationList
            selectedId={conversationId}
            onSelect={onSelect}
            agents={agents}
            labels={labels}
            patch={active}
            height={PANE_HEIGHT}
          />
        )}
        {showThread &&
          (conversationId ? (
            <ConversationView
              conversationId={conversationId}
              agents={agents}
              labels={labels}
              height={THREAD_HEIGHT}
              insert={insert}
              onConversationChange={setActive}
              onBack={mdUp ? undefined : toList}
              onLeave={toList}
              onOpenCustomer={lgUp ? undefined : () => setCustomerOpen(true)}
            />
          ) : (
            <SelectPrompt />
          ))}
        {showPanel && panel}
      </InlineGrid>
      {!lgUp && active && (
        <Modal open={customerOpen} onClose={() => setCustomerOpen(false)} title={t("customer.title", "Customer")}>
          <Modal.Section>{panel}</Modal.Section>
        </Modal>
      )}
    </BlockStack>,
  );
};

const InboxApp = ({ path }) => {
  const route = parsePath(path);
  if (route.view === "ai") {
    return (
      <InboxFullscreen title={t("ai.page_title", "AI agent")} onClose={() => navigateTo(INBOX_BASE)}>
        <AiAgentPage tab={route.tab} />
      </InboxFullscreen>
    );
  }
  if (route.view === "settings") {
    return (
      <InboxFullscreen title={t("settings_title", "Inbox settings")} onClose={() => navigateTo(INBOX_BASE)}>
        <InboxSettingsPage />
      </InboxFullscreen>
    );
  }
  return <InboxHome conversationId={route.conversationId} />;
};

export default InboxApp;

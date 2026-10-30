import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Badge,
  Banner,
  BlockStack,
  Box,
  Button,
  ButtonGroup,
  Card,
  InlineStack,
  SkeletonBodyText,
  Text,
} from "@shopify/polaris";
import { navigateTo } from "../../../../../utils/navigate";
import { errorMessage, t } from "../format";
import { AI_TABS, aiApi, aiPath, formatCredits } from "./api";
import SetupTab from "./SetupTab";
import KnowledgeTab from "./KnowledgeTab";
import TestTab from "./TestTab";
import CreditsTab from "./CreditsTab";
import ActivityTab from "./ActivityTab";

const FORM_KEYS = [
  "reply_mode",
  "agent_name",
  "tone",
  "skills",
  "discount",
  "allow_cancel",
  "knowledge",
  "handoff_text",
  "test_numbers",
  "team_timeout_minutes",
  "daily_reply_limit",
];

const toForm = (settings) => Object.fromEntries(FORM_KEYS.map((key) => [key, settings[key]]));

const STATUS_TONE = { off: undefined, test: "attention", live: "success" };

const TAB_LABELS = {
  setup: () => t("ai.tab_setup", "Setup"),
  knowledge: () => t("ai.tab_knowledge", "Knowledge"),
  test: () => t("ai.tab_test", "Test"),
  credits: () => t("ai.tab_credits", "Credits"),
  activity: () => t("ai.tab_activity", "Activity"),
};

const STATUS_LABELS = {
  off: () => t("ai.status_off", "Off"),
  test: () => t("ai.status_test", "Test"),
  live: () => t("ai.status_live", "Live"),
};

const SaveBar = ({ saving, onSave, onDiscard }) => (
  <div
    style={{
      position: "sticky",
      bottom: 0,
      zIndex: 2,
      marginTop: 16,
      background: "var(--p-color-bg-surface, #fff)",
      borderTop: "1px solid var(--p-color-border, #e3e3e3)",
      boxShadow: "0 -4px 12px rgba(0,0,0,0.06)",
      borderRadius: 12,
    }}
  >
    <Box padding="300">
      <InlineStack align="space-between" blockAlign="center" gap="200">
        <Text as="span" fontWeight="semibold">
          {t("ai.unsaved", "Unsaved changes")}
        </Text>
        <InlineStack gap="200">
          <Button onClick={onDiscard} disabled={saving}>
            {t("ai.discard", "Discard")}
          </Button>
          <Button variant="primary" onClick={onSave} loading={saving}>
            {t("ai.save", "Save")}
          </Button>
        </InlineStack>
      </InlineStack>
    </Box>
  </div>
);

const AiAgentPage = ({ tab: rawTab }) => {
  const tab = AI_TABS.includes(rawTab) ? rawTab : "setup";
  const [data, setData] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [statusBusy, setStatusBusy] = useState(null);
  const [notice, setNotice] = useState(null);

  const load = useCallback(async () => {
    try {
      const next = await aiApi.settings();
      setData(next);
      setForm(toForm(next.settings));
      setLoadError(null);
    } catch (e) {
      setLoadError(e);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const saved = useMemo(() => (data ? toForm(data.settings) : null), [data]);
  const dirty = useMemo(() => form && saved && JSON.stringify(form) !== JSON.stringify(saved), [form, saved]);

  const update = useCallback((patch) => setForm((prev) => ({ ...prev, ...patch })), []);

  const applyResponse = (next) => {
    setData(next);
    setForm(toForm(next.settings));
  };

  const save = async () => {
    setSaving(true);
    setNotice(null);
    try {
      applyResponse(await aiApi.saveSettings(form));
      setNotice({ tone: "success", text: t("ai.saved", "Saved") });
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
    } finally {
      setSaving(false);
    }
  };

  const setStatus = async (status) => {
    if (!data || status === data.settings.status) return;
    setStatusBusy(status);
    setNotice(null);
    try {
      const wasOff = data.settings.status === "off";
      const next = await aiApi.saveSettings(dirty ? { ...form, status } : { status });
      applyResponse(next);
      if (wasOff && status !== "off" && next.wallet?.free_granted) {
        setNotice({
          tone: "success",
          text:
            status === "test"
              ? t("ai.test_on", "Test mode is on. The AI now replies only to your test numbers.")
              : t("ai.live_on", "The AI agent is live and answering your customers."),
        });
      }
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
    } finally {
      setStatusBusy(null);
    }
  };

  const onWallet = useCallback((wallet) => setData((prev) => (prev ? { ...prev, wallet } : prev)), []);

  if (loadError) {
    return (
      <Card>
        <BlockStack gap="300">
          <Banner tone="critical">{errorMessage(loadError)}</Banner>
          <InlineStack>
            <Button onClick={load}>{t("ai.retry", "Try again")}</Button>
          </InlineStack>
        </BlockStack>
      </Card>
    );
  }

  if (!data || !form) {
    return (
      <Card>
        <SkeletonBodyText lines={6} />
      </Card>
    );
  }

  const { settings, wallet, config } = data;
  const status = settings.status;

  return (
    <div style={{ maxWidth: 1080, margin: "0 auto" }}>
      <BlockStack gap="400">
        {!config?.configured && (
          <Banner tone="warning" title={t("ai.not_configured_title", "AI replies aren't available yet")}>
            {t(
              "ai.not_configured_body",
              "The AI service isn't connected on the server. Your settings are saved and will start working once it is.",
            )}
          </Banner>
        )}
        {status === "live" && wallet.balance <= 0 && (
          <Banner tone="critical" title={t("ai.empty_title", "You're out of AI credits")}>
            <BlockStack gap="200">
              <Text as="p">
                {t("ai.empty_body", "The AI agent has stopped replying. Your normal auto-replies are being used instead.")}
              </Text>
              <InlineStack>
                <Button onClick={() => navigateTo(aiPath("credits"))}>{t("ai.buy_credits", "Buy credits")}</Button>
              </InlineStack>
            </BlockStack>
          </Banner>
        )}
        {status === "live" && wallet.balance > 0 && wallet.low && (
          <Banner tone="warning">
            {t("ai.low_body", "Only %{count} AI credits left. Top up so the agent keeps replying.", {
              count: formatCredits(wallet.balance),
            })}
          </Banner>
        )}
        {notice && (
          <Banner tone={notice.tone} onDismiss={() => setNotice(null)}>
            {notice.text}
          </Banner>
        )}

        <Card>
          <InlineStack align="space-between" blockAlign="center" gap="400">
            <BlockStack gap="100">
              <InlineStack gap="200" blockAlign="center">
                <Text as="h2" variant="headingMd">
                  {t("ai.agent_title", "AI agent")}
                </Text>
                <Badge tone={STATUS_TONE[status]}>{STATUS_LABELS[status]()}</Badge>
              </InlineStack>
              <Text as="p" tone="subdued">
                {status === "off" &&
                  t("ai.status_off_body", "Turn on Test to try it on your own number, then go Live for all customers.")}
                {status === "test" &&
                  t("ai.status_test_body", "Replies only to your test numbers. Free while testing.")}
                {status === "live" &&
                  t("ai.status_live_body", "Answering every customer inside WhatsApp's 24-hour window.")}
              </Text>
            </BlockStack>
            <InlineStack gap="300" blockAlign="center">
              <Button variant="tertiary" onClick={() => navigateTo(aiPath("credits"))}>
                {t("ai.credits_chip", "%{count} credits", { count: formatCredits(wallet.balance) })}
              </Button>
              <ButtonGroup variant="segmented">
                {["off", "test", "live"].map((key) => (
                  <Button
                    key={key}
                    pressed={status === key}
                    loading={statusBusy === key}
                    onClick={() => setStatus(key)}
                  >
                    {STATUS_LABELS[key]()}
                  </Button>
                ))}
              </ButtonGroup>
            </InlineStack>
          </InlineStack>
        </Card>

        <ButtonGroup variant="segmented" fullWidth>
          {AI_TABS.map((key) => (
            <Button key={key} pressed={tab === key} onClick={() => navigateTo(aiPath(key))}>
              {TAB_LABELS[key]()}
            </Button>
          ))}
        </ButtonGroup>

        {tab === "setup" && <SetupTab form={form} update={update} settings={settings} storeName={data.store_name} />}
        {tab === "knowledge" && <KnowledgeTab form={form} update={update} limits={settings.limits} />}
        {tab === "test" && <TestTab form={form} update={update} settings={settings} onStatus={setStatus} />}
        {tab === "credits" && <CreditsTab wallet={wallet} onWallet={onWallet} />}
        {tab === "activity" && <ActivityTab />}

        {dirty && <SaveBar saving={saving} onSave={save} onDiscard={() => setForm(saved)} />}
      </BlockStack>
    </div>
  );
};

export default AiAgentPage;

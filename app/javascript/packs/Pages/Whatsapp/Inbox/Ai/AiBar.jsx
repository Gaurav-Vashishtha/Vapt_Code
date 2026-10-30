import React, { useState } from "react";
import { Badge, Box, Button, InlineStack, Text } from "@shopify/polaris";
import { PauseCircleMajor, PlayCircleMajor, WandMinor } from "@shopify/polaris-icons";
import { errorMessage, t } from "../format";
import { aiApi } from "./api";

const AiBar = ({ conversation, windowOpen, onConversation, onInsert, onNotice }) => {
  const [busy, setBusy] = useState(null);
  const ai = conversation?.ai || {};

  const run = async (key, action) => {
    setBusy(key);
    try {
      await action();
    } catch (e) {
      onNotice({ tone: "critical", text: errorMessage(e) });
    } finally {
      setBusy(null);
    }
  };

  const suggest = () =>
    run("suggest", async () => {
      const data = await aiApi.suggest(conversation.id);
      if (data.text) {
        onInsert(data.text);
        if (data.handoff) {
          onNotice({
            tone: "info",
            text: t("ai.suggest_handoff", "AI thinks a person should handle this: %{note}", { note: data.note || "—" }),
          });
        }
      } else {
        onNotice({ tone: "warning", text: data.error || t("ai.suggest_empty", "AI couldn't suggest a reply this time.") });
      }
    });

  const toggle = () =>
    run("toggle", async () => {
      const data = ai.paused || ai.agent_quiet ? await aiApi.resume(conversation.id) : await aiApi.pause(conversation.id);
      onConversation(data.conversation);
    });

  const useDraft = () =>
    run("draft", async () => {
      onInsert(ai.draft);
      const data = await aiApi.dismissDraft(conversation.id);
      onConversation(data.conversation);
    });

  const dismissDraft = () =>
    run("dismiss", async () => {
      const data = await aiApi.dismissDraft(conversation.id);
      onConversation(data.conversation);
    });

  let status = null;
  if (ai.enabled) {
    if (ai.paused) {
      status = (
        <InlineStack gap="200" blockAlign="center">
          <Badge tone="warning">{ai.handoff_at ? t("ai.bar_handed_off", "Handed to team") : t("ai.bar_paused", "AI paused")}</Badge>
          <Text as="span" variant="bodySm" tone="subdued">
            {ai.handoff_at && ai.team_timeout_minutes > 0
              ? t("ai.bar_handoff_timeout", "If your team doesn't reply within %{minutes} min, the AI steps back in.", {
                  minutes: ai.team_timeout_minutes,
                })
              : t("ai.bar_paused_body", "AI won't reply in this chat until you resume it or resolve the chat.")}
          </Text>
        </InlineStack>
      );
    } else if (ai.agent_quiet) {
      status = (
        <Text as="span" variant="bodySm" tone="subdued">
          {ai.team_timeout_minutes > 0
            ? t("ai.bar_quiet_timeout", "Your team replied. If the customer waits over %{minutes} min, the AI steps back in.", {
                minutes: ai.team_timeout_minutes,
              })
            : t("ai.bar_quiet", "AI stays quiet for 6 hours after a team reply.")}
        </Text>
      );
    } else {
      status = (
        <InlineStack gap="200" blockAlign="center">
          <Badge tone="success">{ai.mode === "test" ? t("ai.bar_test", "AI test mode") : t("ai.bar_on", "AI on")}</Badge>
          <Text as="span" variant="bodySm" tone="subdued">
            {t("ai.bar_on_body", "The AI agent answers this customer.")}
          </Text>
        </InlineStack>
      );
    }
  }

  return (
    <Box paddingBlockEnd="200">
      <InlineStack align="space-between" blockAlign="center" gap="200">
        <div style={{ minWidth: 0, flex: 1 }}>{status}</div>
        <InlineStack gap="200" blockAlign="center">
          {ai.draft && (
            <>
              <Button size="slim" variant="primary" onClick={useDraft} loading={busy === "draft"}>
                {t("ai.use_draft", "Use AI draft")}
              </Button>
              <Button size="slim" variant="tertiary" onClick={dismissDraft} loading={busy === "dismiss"}>
                {t("ai.dismiss_draft", "Dismiss")}
              </Button>
            </>
          )}
          {ai.enabled && (
            <Button
              size="slim"
              icon={ai.paused || ai.agent_quiet ? PlayCircleMajor : PauseCircleMajor}
              onClick={toggle}
              loading={busy === "toggle"}
            >
              {ai.paused || ai.agent_quiet ? t("ai.resume", "Resume AI") : t("ai.pause", "Pause AI")}
            </Button>
          )}
          {windowOpen && ai.available && (
            <Button size="slim" icon={WandMinor} onClick={suggest} loading={busy === "suggest"}>
              {t("ai.suggest", "Suggest reply")}
            </Button>
          )}
        </InlineStack>
      </InlineStack>
    </Box>
  );
};

export default AiBar;

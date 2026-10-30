import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Banner, BlockStack, Box, Button, Card, InlineStack, Modal, Spinner, Text } from "@shopify/polaris";
import usePolling from "./usePolling";
import { inboxApi, isAbort } from "./api";
import { dayKey, dayLabel, errorMessage, t, windowState } from "./format";
import ConversationHeader from "./ConversationHeader";
import MessageBubble from "./MessageBubble";
import Composer from "./Composer";
import TemplatePicker from "./TemplatePicker";
import AiBar from "./Ai/AiBar";

const POLL_MS = 10000;
const PAGE = 50;

const byTime = (a, b) => new Date(a.occurred_at) - new Date(b.occurred_at) || a.id - b.id;

const mergeMessages = (prev, incoming = []) => {
  if (!incoming.length) return prev;
  const map = new Map(prev.map((m) => [m.id, m]));
  incoming.forEach((m) => map.set(m.id, m));
  return Array.from(map.values()).sort(byTime);
};

const beforeCursor = (message) => `${new Date(message.occurred_at).getTime() / 1000}_${message.id}`;

const groupReactions = (messages) => {
  const ids = new Set(messages.map((m) => m.id));
  const byMeta = new Map(messages.filter((m) => m.meta_message_id).map((m) => [m.meta_message_id, m.id]));
  const latest = {};
  const visible = [];
  messages.forEach((m) => {
    if (m.kind === "reaction") {
      const target = byMeta.get(m.content?.target_meta_message_id) ?? m.reply_to?.id;
      if (target != null && ids.has(target)) {
        latest[target] = { ...(latest[target] || {}), [m.direction]: m.content?.emoji || "" };
        return;
      }
    }
    visible.push(m);
  });
  const reactions = Object.fromEntries(
    Object.entries(latest).map(([id, bySide]) => [id, Object.values(bySide).filter(Boolean)]),
  );
  return { visible, reactions };
};

const ConversationView = ({
  conversationId,
  agents,
  labels,
  height,
  insert,
  onConversationChange,
  onBack,
  onLeave,
  onOpenCustomer,
}) => {
  const [conversation, setConversation] = useState(null);
  const [messages, setMessages] = useState([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [loadError, setLoadError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);
  const [closedAtInbound, setClosedAtInbound] = useState(null);
  const [templateOpen, setTemplateOpen] = useState(false);
  const [lightbox, setLightbox] = useState(null);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [now, setNow] = useState(Date.now());
  const [aiInsert, setAiInsert] = useState(null);
  const sinceRef = useRef(null);
  const scrollRef = useRef(null);
  const stickToBottom = useRef(true);
  const restoreFrom = useRef(null);
  const readKey = useRef(null);
  const changeRef = useRef(onConversationChange);
  changeRef.current = onConversationChange;

  const applyConversation = useCallback((next) => {
    if (next) setConversation(next);
  }, []);

  useEffect(() => {
    if (conversation && changeRef.current) changeRef.current(conversation);
  }, [conversation]);

  useEffect(() => {
    sinceRef.current = null;
    stickToBottom.current = true;
    restoreFrom.current = null;
    readKey.current = null;
    setConversation(null);
    setMessages([]);
    setHasMore(false);
    setLoading(true);
    setLoadError(null);
    setNotice(null);
    setClosedAtInbound(null);
    setTemplateOpen(false);
    setAiInsert(null);
  }, [conversationId]);

  const poll = useCallback(
    async (signal) => {
      const since = sinceRef.current;
      try {
        const data = await inboxApi.messages(conversationId, since ? { since } : { limit: PAGE }, { signal });
        if (since) {
          setMessages((prev) => mergeMessages(prev, data.messages));
        } else {
          setMessages([...(data.messages || [])].sort(byTime));
          setHasMore(!!data.has_more);
        }
        sinceRef.current = data.server_time || since;
        applyConversation(data.conversation);
        setLoadError(null);
        setNow(Date.now());
      } catch (e) {
        if (!isAbort(e) && !since) setLoadError(e);
      } finally {
        if (!signal?.aborted) setLoading(false);
      }
    },
    [conversationId, applyConversation],
  );

  usePolling(poll, POLL_MS, [conversationId]);

  useEffect(() => {
    if (!conversation || conversation.unread_count <= 0 || document.hidden) return;
    const key = `${conversation.id}:${conversation.last_inbound_at}`;
    if (readKey.current === key) return;
    readKey.current = key;
    inboxApi
      .markRead(conversation.id)
      .then(() => applyConversation((prev) => (prev && prev.id === conversation.id ? { ...prev, unread_count: 0 } : prev)))
      .catch(() => {
        readKey.current = null;
      });
  }, [conversation, applyConversation]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    if (restoreFrom.current !== null) {
      el.scrollTop = el.scrollHeight - restoreFrom.current;
      restoreFrom.current = null;
    } else if (stickToBottom.current) {
      el.scrollTop = el.scrollHeight;
    }
  }, [messages]);

  const loadOlder = useCallback(async () => {
    if (loadingOlder || !hasMore || !messages.length) return;
    setLoadingOlder(true);
    try {
      const data = await inboxApi.messages(conversationId, { before: beforeCursor(messages[0]), limit: PAGE });
      if (scrollRef.current) restoreFrom.current = scrollRef.current.scrollHeight;
      setMessages((prev) => mergeMessages(prev, data.messages));
      setHasMore(!!data.has_more);
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
    } finally {
      setLoadingOlder(false);
    }
  }, [conversationId, hasMore, loadingOlder, messages]);

  const onScroll = (e) => {
    const el = e.currentTarget;
    stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    if (el.scrollTop < 60) loadOlder();
  };

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return undefined;
    const keepBottom = () => {
      if (stickToBottom.current) el.scrollTop = el.scrollHeight;
    };
    el.addEventListener("load", keepBottom, true);
    el.addEventListener("loadedmetadata", keepBottom, true);
    return () => {
      el.removeEventListener("load", keepBottom, true);
      el.removeEventListener("loadedmetadata", keepBottom, true);
    };
  }, [conversation?.id]);

  const handleSendError = (e) => {
    if (e.code === "window_closed") {
      setClosedAtInbound(conversation?.last_inbound_at || "closed");
      setNotice({
        tone: "warning",
        text: t("composer.window_closed_notice", "The reply window closed before this was sent. Send a template instead."),
      });
      return;
    }
    setNotice({ tone: "critical", text: errorMessage(e) });
    if (e.code === "send_failed") poll();
  };

  const onSend = async (payload) => {
    setNotice(null);
    try {
      const data =
        payload.type === "media"
          ? await inboxApi.sendMedia(conversationId, payload)
          : await inboxApi.sendText(conversationId, payload);
      stickToBottom.current = true;
      if (data.message) setMessages((prev) => mergeMessages(prev, [data.message]));
      applyConversation(data.conversation);
      return true;
    } catch (e) {
      handleSendError(e);
      return false;
    }
  };

  const onSendTemplate = async (payload) => {
    const data = await inboxApi.sendTemplate(conversationId, payload);
    stickToBottom.current = true;
    if (data.message) setMessages((prev) => mergeMessages(prev, [data.message]));
    applyConversation(data.conversation);
  };

  const runAction = async (action) => {
    setBusy(true);
    setNotice(null);
    try {
      await action();
    } catch (e) {
      setNotice({ tone: "critical", text: errorMessage(e) });
    } finally {
      setBusy(false);
    }
  };

  const onUpdate = (patch) =>
    runAction(async () => {
      const data = await inboxApi.updateConversation(conversationId, patch);
      applyConversation(data.conversation);
    });

  const onLabels = (labelIds) =>
    runAction(async () => {
      const data = await inboxApi.setLabels(conversationId, labelIds);
      applyConversation((prev) => (prev ? { ...prev, labels: data.labels || [] } : prev));
    });

  const onMarkUnread = () =>
    runAction(async () => {
      await inboxApi.markUnread(conversationId);
      const next = { ...conversation, unread_count: Math.max(1, conversation.unread_count || 0) };
      setConversation(next);
      if (changeRef.current) changeRef.current(next);
      if (onLeave) onLeave();
    });

  const setBlocked = (block) =>
    runAction(async () => {
      const data = block ? await inboxApi.block(conversationId) : await inboxApi.unblock(conversationId);
      applyConversation((prev) => (prev ? { ...prev, opted_out: !!data.opted_out } : prev));
      setConfirmBlock(false);
    });

  const { visible, reactions } = useMemo(() => groupReactions(messages), [messages]);

  if (!conversation) {
    return (
      <Card>
        {loading ? (
          <InlineStack align="center">
            <Spinner size="small" accessibilityLabel={t("thread.loading", "Loading conversation")} />
          </InlineStack>
        ) : (
          <BlockStack gap="300">
            <Banner tone="critical">
              {loadError?.status === 404
                ? t("thread.not_found", "This conversation isn't available anymore.")
                : errorMessage(loadError)}
            </Banner>
            {onLeave && (
              <InlineStack>
                <Button onClick={onLeave}>{t("thread.back_to_list", "Back to conversations")}</Button>
              </InlineStack>
            )}
          </BlockStack>
        )}
      </Card>
    );
  }

  const windowOpen =
    windowState(conversation, now).open && !(closedAtInbound && closedAtInbound === (conversation.last_inbound_at || "closed"));

  let lastDay = null;
  const rows = [];
  visible.forEach((message) => {
    const day = dayKey(message.occurred_at);
    if (day !== lastDay) {
      lastDay = day;
      rows.push(
        <Box key={`day-${day}`} paddingBlock="200">
          <Text as="p" variant="bodySm" tone="subdued" alignment="center">
            {dayLabel(message.occurred_at)}
          </Text>
        </Box>,
      );
    }
    rows.push(
      <MessageBubble key={message.id} message={message} reactions={reactions[message.id] || []} onOpenImage={setLightbox} />,
    );
  });

  return (
    <>
      <Card padding="0">
        <ConversationHeader
          conversation={conversation}
          agents={agents}
          labels={labels}
          now={now}
          busy={busy}
          onUpdate={onUpdate}
          onLabels={onLabels}
          onMarkUnread={onMarkUnread}
          onBlockToggle={() => (conversation.opted_out ? setBlocked(false) : setConfirmBlock(true))}
          onBack={onBack}
          onOpenCustomer={onOpenCustomer}
        />
        {notice && (
          <Box padding="300">
            <Banner tone={notice.tone} onDismiss={() => setNotice(null)}>
              {notice.text}
            </Banner>
          </Box>
        )}
        <div ref={scrollRef} onScroll={onScroll} style={{ height, overflowY: "auto" }}>
          <Box padding="300">
            <BlockStack gap="200">
              {hasMore && (
                <InlineStack align="center">
                  <Button variant="plain" onClick={loadOlder} loading={loadingOlder}>
                    {t("thread.load_older", "Load older messages")}
                  </Button>
                </InlineStack>
              )}
              {rows.length === 0 && (
                <Text as="p" tone="subdued" alignment="center">
                  {t("thread.empty", "No messages yet.")}
                </Text>
              )}
              {rows}
            </BlockStack>
          </Box>
        </div>
        <Box padding="300" borderBlockStartWidth="025" borderColor="border-secondary">
          <AiBar
            conversation={conversation}
            windowOpen={windowOpen}
            onConversation={applyConversation}
            onInsert={(text) => setAiInsert({ text, nonce: Date.now(), conversationId })}
            onNotice={setNotice}
          />
          <Composer
            key={conversationId}
            conversation={conversation}
            windowOpen={windowOpen}
            onSend={onSend}
            onOpenTemplates={() => setTemplateOpen(true)}
            insert={
              aiInsert && aiInsert.conversationId === conversationId && (!insert || aiInsert.nonce > insert.nonce)
                ? aiInsert
                : insert
            }
          />
        </Box>
      </Card>
      <TemplatePicker
        open={templateOpen}
        conversationId={conversationId}
        onClose={() => setTemplateOpen(false)}
        onSend={onSendTemplate}
      />
      <Modal open={!!lightbox} onClose={() => setLightbox(null)} title={t("thread.image", "Image")} size="large">
        <Modal.Section>
          {lightbox && <img src={lightbox} alt="" style={{ display: "block", maxWidth: "100%", margin: "0 auto" }} />}
        </Modal.Section>
      </Modal>
      <Modal
        open={confirmBlock}
        onClose={() => setConfirmBlock(false)}
        title={t("header.block_title", "Block this customer?")}
        primaryAction={{
          content: t("header.block", "Block customer"),
          destructive: true,
          loading: busy,
          onAction: () => setBlocked(true),
        }}
        secondaryActions={[{ content: t("header.cancel", "Cancel"), onAction: () => setConfirmBlock(false) }]}
      >
        <Modal.Section>
          <Text as="p">
            {t(
              "header.block_body",
              "They won't get marketing messages from you anymore. They can still message you, and you can still reply here.",
            )}
          </Text>
        </Modal.Section>
      </Modal>
    </>
  );
};

export default ConversationView;

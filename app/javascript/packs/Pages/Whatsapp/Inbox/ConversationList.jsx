import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Banner, BlockStack, Box, Button, ButtonGroup, Card, Spinner, Text } from "@shopify/polaris";
import usePolling from "./usePolling";
import { inboxApi, isAbort } from "./api";
import { t } from "./format";
import InboxFilters from "./InboxFilters";
import ConversationListItem from "./ConversationListItem";

const POLL_MS = 30000;
const TAB_KEYS = ["open", "pending", "resolved", "all"];

const listParams = (tab, filters) => ({
  status: tab,
  assignee: filters.assignee || undefined,
  label_id: filters.label_id || undefined,
  account_id: filters.account_id || undefined,
  unread: filters.unread ? "true" : undefined,
  q: filters.q || undefined,
});

const mergeFirstPage = (fresh, previous) => {
  const ids = new Set(fresh.map((c) => c.id));
  return [...fresh, ...previous.slice(fresh.length).filter((c) => !ids.has(c.id))];
};

const ConversationList = ({ selectedId, onSelect, agents, labels, patch, height }) => {
  const [tab, setTab] = useState("open");
  const [filters, setFilters] = useState({ assignee: "", label_id: "", account_id: "", unread: false, q: "" });
  const [conversations, setConversations] = useState([]);
  const [counts, setCounts] = useState({});
  const [nextCursor, setNextCursor] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [now, setNow] = useState(Date.now());
  const [accounts, setAccounts] = useState([]);
  const seq = useRef(0);
  const params = useMemo(() => listParams(tab, filters), [tab, filters]);
  const paramsKey = JSON.stringify(params);

  useEffect(() => {
    setConversations([]);
    setNextCursor(null);
    setLoading(true);
  }, [paramsKey]);

  const poll = useCallback(
    async (signal) => {
      const id = ++seq.current;
      try {
        const data = await inboxApi.conversations(params, { signal });
        if (id !== seq.current) return;
        const fresh = data.conversations || [];
        setConversations((prev) => mergeFirstPage(fresh, prev));
        setNextCursor((prev) => prev ?? data.next_cursor ?? null);
        setCounts(data.counts || {});
        setAccounts((prev) => {
          const map = new Map(prev.map((a) => [a.id, a]));
          fresh.forEach((c) => c.account?.id && map.set(c.account.id, c.account));
          return map.size === prev.length ? prev : Array.from(map.values());
        });
        setError("");
        setNow(Date.now());
      } catch (e) {
        if (!isAbort(e) && id === seq.current) setError(e.message);
      } finally {
        if (id === seq.current) setLoading(false);
      }
    },
    [params],
  );

  usePolling(poll, POLL_MS, [params]);

  useEffect(() => {
    if (!patch?.id) return;
    setConversations((prev) => prev.map((c) => (c.id === patch.id ? { ...c, ...patch } : c)));
  }, [patch]);

  const loadMore = useCallback(async () => {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    const id = seq.current;
    try {
      const data = await inboxApi.conversations({ ...params, cursor: nextCursor });
      if (id !== seq.current) return;
      setConversations((prev) => {
        const ids = new Set(prev.map((c) => c.id));
        return [...prev, ...(data.conversations || []).filter((c) => !ids.has(c.id))];
      });
      setNextCursor(data.next_cursor || null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoadingMore(false);
    }
  }, [nextCursor, loadingMore, params]);

  const onScroll = (e) => {
    const el = e.currentTarget;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 120) loadMore();
  };

  const tabLabel = (key) => {
    const label = t(`tabs.${key}`, key.charAt(0).toUpperCase() + key.slice(1));
    return key !== "all" && counts[key] ? `${label} ${counts[key]}` : label;
  };

  const updateFilters = useCallback((partial) => setFilters((prev) => ({ ...prev, ...partial })), []);
  const filtered = !!(filters.assignee || filters.label_id || filters.account_id || filters.unread || filters.q);

  return (
    <Card padding="0">
      <Box padding="300" paddingBlockEnd="0">
        <ButtonGroup variant="segmented" fullWidth>
          {TAB_KEYS.map((key) => (
            <Button key={key} size="slim" pressed={tab === key} onClick={() => setTab(key)}>
              {tabLabel(key)}
            </Button>
          ))}
        </ButtonGroup>
      </Box>
      <Box padding="300" borderBlockEndWidth="025" borderColor="border-secondary">
        <InboxFilters filters={filters} onChange={updateFilters} agents={agents} labels={labels} accounts={accounts} />
      </Box>
      {error && (
        <Box padding="300">
          <Banner tone="critical" onDismiss={() => setError("")}>
            {error}
          </Banner>
        </Box>
      )}
      <div style={{ height, overflowY: "auto" }} onScroll={onScroll}>
        {loading && conversations.length === 0 ? (
          <Box padding="600">
            <BlockStack inlineAlign="center">
              <Spinner size="small" accessibilityLabel={t("list.loading", "Loading conversations")} />
            </BlockStack>
          </Box>
        ) : conversations.length === 0 ? (
          <Box padding="600">
            <Text as="p" tone="subdued" alignment="center">
              {filtered || tab !== "open"
                ? t("list.empty_all", "No conversations match these filters.")
                : t("list.empty_open", "No open conversations. New customer messages will show up here.")}
            </Text>
          </Box>
        ) : (
          conversations.map((conversation) => (
            <ConversationListItem
              key={conversation.id}
              conversation={conversation}
              selected={conversation.id === selectedId}
              onSelect={onSelect}
              now={now}
            />
          ))
        )}
        {loadingMore && (
          <Box padding="300">
            <BlockStack inlineAlign="center">
              <Spinner size="small" />
            </BlockStack>
          </Box>
        )}
      </div>
    </Card>
  );
};

export default ConversationList;

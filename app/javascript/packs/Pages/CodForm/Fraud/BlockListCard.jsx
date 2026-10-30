import React, { useCallback, useEffect, useRef, useState } from "react";
import { BlockStack, Button, Card, Divider, InlineStack, Pagination, SkeletonBodyText, Tabs, Text, TextField, Banner } from "@shopify/polaris";
import { DeleteMinor } from "@shopify/polaris-icons";
import { codFormApi, parseError } from "../api";
import Gate from "../components/Gate";
import { FEATURES } from "../constants";
import { formatDateTime } from "../utils";
import { t } from "../i18n";
import BlockEntryModal from "./BlockEntryModal";

const KINDS = ["phone", "email", "ip"];

/** Block lists for phone, email and IP with a custom message (FRD-1). */
const BlockListCard = ({ fraud, onChange }) => {
  const [tab, setTab] = useState(0);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [state, setState] = useState({ items: null, meta: {} });
  const [error, setError] = useState(null);
  const [adding, setAdding] = useState(false);
  const [saving, setSaving] = useState(false);
  const [modalError, setModalError] = useState(null);
  const [notice, setNotice] = useState(null);
  const requestRef = useRef(0);
  const kind = KINDS[tab];

  const load = useCallback(() => {
    const request = requestRef.current + 1;
    requestRef.current = request;
    setError(null);
    return codFormApi.blockEntries
      .index({ kind, q: query.trim(), page })
      .then((response) => {
        if (requestRef.current !== request) return;
        setState({ items: (response && response.items) || [], meta: (response && response.meta) || {} });
      })
      .catch((err) => {
        if (requestRef.current === request) setError(parseError(err));
      });
  }, [kind, query, page]);

  useEffect(() => {
    const timer = setTimeout(load, query ? 300 : 0);
    return () => clearTimeout(timer);
  }, [load, query]);

  const submit = (payload) => {
    setSaving(true);
    setModalError(null);
    const request = payload.values ? codFormApi.blockEntries.createBulk(payload) : codFormApi.blockEntries.create(payload);
    request
      .then((response) => {
        setAdding(false);
        setNotice(
          t("fraud.block_added", "%{created} added, %{skipped} already on the list or skipped.", {
            created: (response && response.created) || 0,
            skipped: (response && response.skipped) || 0,
          }) +
            (response && Number(response.over_limit) > 0
              ? ` ${t("fraud.block_over_limit", "%{count} were not added because the list is full.", { count: response.over_limit })}`
              : ""),
        );
        setPage(1);
        return load();
      })
      .catch((err) => setModalError(parseError(err)))
      .then(() => setSaving(false));
  };

  const remove = (entry) => {
    setState((current) => ({ ...current, items: (current.items || []).filter((item) => item.id !== entry.id) }));
    codFormApi.blockEntries.destroy(entry.id).catch((err) => {
      setError(parseError(err));
      load();
    });
  };

  const tabs = [
    { id: "phone", content: t("fraud.block_phone", "Phone numbers") },
    { id: "email", content: t("fraud.block_email", "Emails") },
    { id: "ip", content: t("fraud.block_ip", "IP addresses") },
  ];
  const { items, meta } = state;
  const pages = Number(meta.pages) || 1;

  return (
    <Card>
      <BlockStack gap="400">
        <BlockStack gap="100">
          <Text as="h2" variant="headingMd">
            {t("fraud.block_title", "Block lists")}
          </Text>
          <Text as="p" tone="subdued">
            {t("fraud.block_help", "Buyers on these lists cannot place a COD order through the form. They see your message and can pay online.")}
          </Text>
        </BlockStack>
        <Gate feature={FEATURES.BLOCK_LISTS} compact title={t("fraud.block_title", "Block lists")}>
          <BlockStack gap="400">
            <Tabs
              tabs={tabs}
              selected={tab}
              onSelect={(index) => {
                setTab(index);
                setPage(1);
                setQuery("");
                setState({ items: null, meta: {} });
              }}
            />
            <InlineStack gap="200" blockAlign="end" wrap>
              <div style={{ flex: "1 1 220px" }}>
                <TextField
                  label={t("fraud.block_search", "Search")}
                  labelHidden
                  placeholder={t("fraud.block_search", "Search")}
                  value={query}
                  onChange={(value) => {
                    setQuery(value);
                    setPage(1);
                  }}
                  clearButton
                  onClearButtonClick={() => setQuery("")}
                  autoComplete="off"
                />
              </div>
              <Button variant="primary" onClick={() => { setModalError(null); setAdding(true); }}>
                {t("fraud.block_add", "Add to block list")}
              </Button>
            </InlineStack>
            {notice && (
              <Banner tone="success" onDismiss={() => setNotice(null)}>
                <p>{notice}</p>
              </Banner>
            )}
            {error && (
              <Banner tone="critical" onDismiss={() => setError(null)}>
                <p>{t("fraud.block_error", "The block list could not be loaded or changed. Try again.")}</p>
              </Banner>
            )}
            {items === null ? (
              <SkeletonBodyText lines={3} />
            ) : items.length === 0 ? (
              <Text as="p" tone="subdued">
                {query
                  ? t("fraud.block_no_match", "Nothing on this list matches your search.")
                  : t("fraud.block_empty", "This list is empty.")}
              </Text>
            ) : (
              <BlockStack gap="200">
                {items.map((entry, index) => (
                  <React.Fragment key={entry.id}>
                    {index > 0 && <Divider />}
                    <InlineStack align="space-between" blockAlign="center" gap="300" wrap={false}>
                      <BlockStack gap="050">
                        <Text as="span" variant="bodyMd" fontWeight="semibold" breakWord>
                          {entry.value}
                        </Text>
                        <Text as="span" variant="bodySm" tone="subdued">
                          {[entry.note, formatDateTime(entry.created_at)].filter(Boolean).join(" · ")}
                        </Text>
                      </BlockStack>
                      <Button icon={DeleteMinor} tone="critical" accessibilityLabel={t("common.delete", "Delete")} onClick={() => remove(entry)} />
                    </InlineStack>
                  </React.Fragment>
                ))}
              </BlockStack>
            )}
            {pages > 1 && (
              <InlineStack align="center">
                <Pagination
                  hasPrevious={page > 1}
                  hasNext={page < pages}
                  onPrevious={() => setPage(page - 1)}
                  onNext={() => setPage(page + 1)}
                  label={t("common.page_of", "Page %{page} of %{pages}", { page, pages })}
                />
              </InlineStack>
            )}
            <Text as="p" variant="bodySm" tone="subdued">
              {t("fraud.block_limit_note", "Up to 5,000 entries per list.")}
              {meta.count != null ? ` ${t("fraud.block_count", "%{count} on this list.", { count: meta.count })}` : ""}
            </Text>
            <Divider />
            <TextField
              label={t("fraud.blocked_message", "Message for blocked buyers")}
              value={fraud.blocked_message || ""}
              onChange={(value) => onChange(["fraud", "blocked_message"], value)}
              placeholder={t("fraud.blocked_message_placeholder", "Cash on delivery is not available for this order.")}
              helpText={t("fraud.blocked_message_help", "Leave empty to use the default text of the form.")}
              maxLength={300}
              autoComplete="off"
            />
          </BlockStack>
        </Gate>
      </BlockStack>
      <BlockEntryModal
        open={adding}
        kind={kind}
        saving={saving}
        error={modalError}
        onClose={() => setAdding(false)}
        onSubmit={submit}
      />
    </Card>
  );
};

export default BlockListCard;

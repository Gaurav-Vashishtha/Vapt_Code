import React, { useState, useEffect, useCallback } from "react";
import {
  Card, BlockStack, InlineStack, InlineGrid, Box, Text, Button, Badge, Banner, Modal, TextField,
  Checkbox, DropZone, DataTable, Tag, Select, ChoiceList, Collapsible, SkeletonBodyText, Spinner,
  Link, Divider,
} from "@shopify/polaris";
import { PlusMinor } from "@shopify/polaris-icons";
import { navigateToPreservingParams } from "../../../../utils/navigate";
import { api, waitForImport } from "./api";
import {
  t, paths, audiencePresets, describeFilters, formatNumber, parseTags,
} from "./copy";

// ── Saved audiences ───────────────────────────────────────────────────

const AudienceCard = ({ audience, onEdit, onView }) => (
  <Card>
    <BlockStack gap="300">
      <BlockStack gap="100">
        <InlineStack align="space-between" blockAlign="start" gap="200" wrap={false}>
          <Text as="h3" variant="headingSm">{audience.name}</Text>
          <Badge>{t("people_count", "%{count} people", { count: formatNumber(audience.count ?? 0) })}</Badge>
        </InlineStack>
        <Text as="p" variant="bodySm" tone="subdued">
          {audience.description || describeFilters(audience.filters)}
        </Text>
      </BlockStack>
      <InlineStack gap="200">
        <Button
          variant="primary"
          size="slim"
          onClick={() => navigateToPreservingParams(paths.newCampaign(), { audience: audience.id })}
        >
          {t("send_to_audience", "Send a campaign")}
        </Button>
        <Button size="slim" onClick={() => onView(audience)}>{t("view_people", "View people")}</Button>
        <Button size="slim" variant="plain" onClick={() => onEdit(audience)}>{t("edit", "Edit")}</Button>
      </InlineStack>
    </BlockStack>
  </Card>
);

const PresetCard = ({ preset, onAdd, adding }) => (
  <Box background="bg-surface-secondary" padding="400" borderRadius="200">
    <BlockStack gap="200">
      <BlockStack gap="050">
        <Text as="h3" variant="headingSm">{preset.name}</Text>
        <Text as="p" variant="bodySm" tone="subdued">{preset.description}</Text>
      </BlockStack>
      <Box>
        <Button size="slim" icon={PlusMinor} loading={adding} onClick={() => onAdd(preset)}>
          {t("preset_add", "Add")}
        </Button>
      </Box>
    </BlockStack>
  </Box>
);

const SavedAudiences = ({ audiences, onReload, onView, onError }) => {
  const [editing, setEditing] = useState(null);
  const [creating, setCreating] = useState(false);
  const [adding, setAdding] = useState(null);

  const names = new Set((audiences || []).map((a) => a.name.toLowerCase()));
  const presets = audiencePresets().filter((p) => !names.has(p.name.toLowerCase()));

  const addPreset = async (preset) => {
    setAdding(preset.key);
    try {
      await api("/api/whatsapp/segments", {
        method: "POST",
        body: { name: preset.name, filters: preset.filters },
      });
      await onReload();
    } catch (e) { onError(e.message); } finally { setAdding(null); }
  };

  return (
    <Card>
      <BlockStack gap="400">
        <InlineStack align="space-between" blockAlign="center" gap="200">
          <BlockStack gap="050">
            <Text as="h2" variant="headingMd">{t("saved_audiences", "Saved audiences")}</Text>
            <Text as="p" variant="bodySm" tone="subdued">
              {t("saved_audiences_help", "Groups of customers you send to again and again. They update on their own as customers order.")}
            </Text>
          </BlockStack>
          <Button onClick={() => setCreating(true)}>{t("create_audience", "Create audience")}</Button>
        </InlineStack>

        {audiences === null ? (
          <SkeletonBodyText lines={3} />
        ) : audiences.length > 0 ? (
          <InlineGrid columns={{ xs: 1, md: 2, lg: 3 }} gap="300">
            {audiences.map((a) => (
              <AudienceCard key={a.id} audience={a} onEdit={setEditing} onView={onView} />
            ))}
          </InlineGrid>
        ) : null}

        {audiences !== null && presets.length > 0 && (
          <BlockStack gap="300">
            {audiences.length > 0 && <Divider />}
            <Text as="h3" variant="headingSm">
              {audiences.length > 0 ? t("presets_more", "More ready-made audiences") : t("presets_title", "Start with a ready-made audience")}
            </Text>
            <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="300">
              {presets.map((p) => (
                <PresetCard key={p.key} preset={p} onAdd={addPreset} adding={adding === p.key} />
              ))}
            </InlineGrid>
          </BlockStack>
        )}
      </BlockStack>

      {(creating || editing) && (
        <AudienceEditor
          audience={editing}
          onClose={() => { setCreating(false); setEditing(null); }}
          onSaved={async () => { setCreating(false); setEditing(null); await onReload(); }}
          onError={onError}
        />
      )}
    </Card>
  );
};

const EMPTY_RULES = {
  min_orders: "", max_orders: "", min_spent: "", max_spent: "",
  recency: "any", recency_days: "30",
  tags_any: "", tags_none: "",
  created_from: "", created_to: "",
  cod_only: false, min_cod_orders: "", rto: "any", unconfirmed_cod_days: "",
};

const rulesFromFilters = (raw) => {
  const f = raw || {};
  return {
  ...EMPTY_RULES,
  min_orders: f.min_orders ?? "",
  max_orders: f.max_orders ?? "",
  min_spent: f.min_spent ?? "",
  max_spent: f.max_spent ?? "",
  recency: f.last_order_within_days ? "within" : f.last_order_older_than_days ? "older" : "any",
  recency_days: String(f.last_order_within_days || f.last_order_older_than_days || "30"),
  tags_any: (f.tags_any || []).join(", "),
  tags_none: (f.tags_none || []).join(", "),
  created_from: f.created_from || "",
  created_to: f.created_to || "",
  cod_only: f.cod_only === true || f.cod_only === "true",
  min_cod_orders: f.min_cod_orders ?? "",
  rto: ["only", "exclude"].includes(f.rto) ? f.rto : "any",
  unconfirmed_cod_days: f.unconfirmed_cod_within_days ?? "",
  };
};

const filtersFromRules = (r, keep = {}) => {
  const out = {};
  ["min_orders", "max_orders", "min_spent", "max_spent", "created_from", "created_to"].forEach((k) => {
    if (String(r[k] ?? "").trim() !== "") out[k] = String(r[k]).trim();
  });
  if (r.recency === "within" && r.recency_days) out.last_order_within_days = String(r.recency_days);
  if (r.recency === "older" && r.recency_days) out.last_order_older_than_days = String(r.recency_days);
  const any = parseTags(r.tags_any);
  const none = parseTags(r.tags_none);
  if (any.length) out.tags_any = any;
  if (none.length) out.tags_none = none;
  if (r.cod_only) out.cod_only = true;
  if (String(r.min_cod_orders ?? "").trim() !== "") out.min_cod_orders = String(r.min_cod_orders).trim();
  if (r.rto === "only" || r.rto === "exclude") out.rto = r.rto;
  if (String(r.unconfirmed_cod_days ?? "").trim() !== "") out.unconfirmed_cod_within_days = String(r.unconfirmed_cod_days).trim();
  // Rules this editor has no control for (set through the API or Sidekick)
  // are carried over untouched rather than silently dropped on save.
  ["tags_all", "sources", "include_unsubscribed"].forEach((k) => {
    if (keep[k] !== undefined) out[k] = keep[k];
  });
  return out;
};

export const AudienceEditor = ({ audience, onClose, onSaved, onError }) => {
  const [name, setName] = useState(audience?.name || "");
  const [rules, setRules] = useState(rulesFromFilters(audience?.filters));
  const [count, setCount] = useState(null);
  const [counting, setCounting] = useState(false);
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [tagCounts, setTagCounts] = useState({});
  const [showMore, setShowMore] = useState(!!(audience?.filters?.created_from || audience?.filters?.created_to));
  const [err, setErr] = useState("");

  const set = (key) => (value) => setRules((prev) => ({ ...prev, [key]: value }));
  const filters = filtersFromRules(rules, audience?.filters || {});
  const filtersKey = JSON.stringify(filters);

  useEffect(() => {
    api("/api/whatsapp/contacts/meta").then((m) => setTagCounts(m.tags || {})).catch(() => {});
  }, []);

  // Live count: re-counted a moment after the merchant stops typing.
  useEffect(() => {
    setCounting(true);
    const timer = setTimeout(async () => {
      try {
        const data = await api("/api/whatsapp/segments/preview", { method: "POST", body: { filters } });
        setCount(data.count);
      } catch (_) { setCount(null); } finally { setCounting(false); }
    }, 500);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtersKey]);

  const addTag = (key, tag) => {
    const current = parseTags(rules[key]);
    if (!current.includes(tag)) set(key)([...current, tag].join(", "));
  };

  const save = async () => {
    setBusy(true);
    setErr("");
    try {
      // A description written for the old rules would now be wrong; the card
      // falls back to describing the rules themselves.
      const rulesUnchanged = audience && describeFilters(audience.filters) === describeFilters(filters);
      const body = { name: name.trim(), description: rulesUnchanged ? audience.description || "" : "", filters };
      const res = audience
        ? await api(`/api/whatsapp/segments/${audience.id}`, { method: "PATCH", body })
        : await api("/api/whatsapp/segments", { method: "POST", body });
      onSaved(res?.segment);
    } catch (e) { setErr(e.message); setBusy(false); }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await api(`/api/whatsapp/segments/${audience.id}`, { method: "DELETE" });
      onSaved();
    } catch (e) { setErr(e.message); setBusy(false); setConfirmDelete(false); }
  };

  const topTags = Object.entries(tagCounts).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([tag]) => tag);

  if (confirmDelete) {
    return (
      <Modal
        open
        onClose={() => setConfirmDelete(false)}
        title={t("audience_delete_title", "Delete \"%{name}\"?", { name: audience.name })}
        primaryAction={{ content: t("action_delete", "Delete"), destructive: true, loading: busy, onAction: remove }}
        secondaryActions={[{ content: t("keep", "Keep it"), onAction: () => setConfirmDelete(false) }]}
      >
        <Modal.Section>
          <Text as="p">
            {t("audience_delete_body", "Only the saved audience is deleted. The people in it stay in your contacts.")}
          </Text>
        </Modal.Section>
      </Modal>
    );
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={audience ? t("audience_edit_title", "Edit audience") : t("audience_new_title", "Create audience")}
      primaryAction={{ content: t("save_audience", "Save audience"), onAction: save, loading: busy, disabled: !name.trim() }}
      secondaryActions={[
        ...(audience ? [{ content: t("action_delete", "Delete"), destructive: true, onAction: () => setConfirmDelete(true) }] : []),
        { content: t("back", "Back"), onAction: onClose },
      ]}
    >
      <Modal.Section>
        <Box background="bg-surface-secondary" padding="300" borderRadius="200">
          <InlineStack align="space-between" blockAlign="center" gap="300" wrap={false}>
            <Text as="p" variant="bodySm">{describeFilters(filters)}</Text>
            <Box minWidth="96px">
              <InlineStack align="end" gap="100" blockAlign="center">
                {counting && <Spinner size="small" />}
                <Text as="span" variant="headingSm">
                  {count === null ? "—" : t("people_count", "%{count} people", { count: formatNumber(count) })}
                </Text>
              </InlineStack>
            </Box>
          </InlineStack>
        </Box>
      </Modal.Section>
      <Modal.Section>
        <BlockStack gap="400">
          {err && <Banner tone="critical" onDismiss={() => setErr("")}>{err}</Banner>}
          <TextField
            label={t("audience_name", "Audience name")}
            value={name}
            onChange={setName}
            placeholder={t("audience_name_placeholder", "e.g. VIP customers")}
            autoComplete="off"
          />

          <BlockStack gap="200">
            <Text as="h3" variant="headingSm">{t("rules_orders", "Orders")}</Text>
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
              <TextField label={t("rules_min_orders", "At least this many orders")} type="number" min={0} value={String(rules.min_orders)} onChange={set("min_orders")} autoComplete="off" />
              <TextField label={t("rules_max_orders", "At most this many orders")} type="number" min={0} value={String(rules.max_orders)} onChange={set("max_orders")} autoComplete="off" helpText={t("rules_max_orders_help", "Use 0 for people who haven't ordered yet")} />
              <TextField label={t("rules_min_spent", "Spent at least")} type="number" min={0} value={String(rules.min_spent)} onChange={set("min_spent")} autoComplete="off" />
              <TextField label={t("rules_max_spent", "Spent at most")} type="number" min={0} value={String(rules.max_spent)} onChange={set("max_spent")} autoComplete="off" />
            </InlineGrid>
          </BlockStack>

          <Divider />

          <BlockStack gap="200">
            <ChoiceList
              title={t("rules_last_order", "Last order")}
              choices={[
                { label: t("rules_any_time", "Any time"), value: "any" },
                { label: t("rules_within", "Ordered recently"), value: "within" },
                { label: t("rules_older", "Haven't ordered for a while"), value: "older" },
              ]}
              selected={[rules.recency]}
              onChange={(v) => set("recency")(v[0])}
            />
            {rules.recency !== "any" && (
              <Box maxWidth="220px">
                <TextField
                  label={rules.recency === "within" ? t("rules_within_days", "In the last") : t("rules_older_days", "Not in the last")}
                  type="number"
                  min={1}
                  suffix={t("days", "days")}
                  value={String(rules.recency_days)}
                  onChange={set("recency_days")}
                  autoComplete="off"
                />
              </Box>
            )}
          </BlockStack>

          <Divider />

          <BlockStack gap="200">
            <BlockStack gap="050">
              <Text as="h3" variant="headingSm">{t("rules_payment_title", "Payment and delivery history")}</Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {t("rules_payment_help", "Based on orders synced to COD King")}
              </Text>
            </BlockStack>
            <Checkbox
              label={t("rules_payment_cod_only", "Only ever paid cash on delivery")}
              helpText={t("rules_payment_cod_only_help", "Has COD orders and has never paid online")}
              checked={!!rules.cod_only}
              onChange={set("cod_only")}
            />
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
              <TextField
                label={t("rules_payment_min_cod", "At least this many COD orders")}
                type="number"
                min={1}
                value={String(rules.min_cod_orders)}
                onChange={set("min_cod_orders")}
                autoComplete="off"
              />
              <Select
                label={t("rules_payment_rto", "Returns and RTO")}
                options={[
                  { label: t("rules_payment_rto_any", "Any"), value: "any" },
                  { label: t("rules_payment_rto_only", "Had a return or RTO"), value: "only" },
                  { label: t("rules_payment_rto_exclude", "No returns or RTO"), value: "exclude" },
                ]}
                value={rules.rto}
                onChange={set("rto")}
              />
            </InlineGrid>
            <Box maxWidth="260px">
              <TextField
                label={t("rules_payment_unconfirmed", "COD order not confirmed, placed in the last")}
                type="number"
                min={1}
                suffix={t("days", "days")}
                value={String(rules.unconfirmed_cod_days)}
                onChange={set("unconfirmed_cod_days")}
                helpText={t("rules_payment_unconfirmed_help", "Leave empty to include everyone")}
                autoComplete="off"
              />
            </Box>
          </BlockStack>

          <Divider />

          <BlockStack gap="200">
            <Text as="h3" variant="headingSm">{t("rules_tags", "Tags")}</Text>
            <TextField label={t("rules_tags_any", "Has any of these tags")} value={rules.tags_any} onChange={set("tags_any")} placeholder="vip, loyal" autoComplete="off" />
            {topTags.length > 0 && (
              <InlineStack gap="100" wrap>
                {topTags.map((tag) => (
                  <Tag key={tag} onClick={() => addTag("tags_any", tag)}>{`+ ${tag}`}</Tag>
                ))}
              </InlineStack>
            )}
            <TextField label={t("rules_tags_none", "Doesn't have any of these tags")} value={rules.tags_none} onChange={set("tags_none")} placeholder="wholesale" autoComplete="off" />
          </BlockStack>

          <Box>
            <Button variant="plain" disclosure={showMore ? "up" : "down"} onClick={() => setShowMore((v) => !v)}>
              {t("rules_more", "More filters")}
            </Button>
          </Box>
          <Collapsible open={showMore} id="audience-more-filters">
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
              <TextField label={t("rules_added_after", "Added to contacts on or after")} type="date" value={rules.created_from} onChange={set("created_from")} autoComplete="off" />
              <TextField label={t("rules_added_before", "Added to contacts on or before")} type="date" value={rules.created_to} onChange={set("created_to")} autoComplete="off" />
            </InlineGrid>
          </Collapsible>

          <Text as="p" variant="bodySm" tone="subdued">
            {t("rules_note", "People who opted out are never included. The audience is re-checked each time you send, so new customers who match are included automatically.")}
          </Text>
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

// ── Contacts ──────────────────────────────────────────────────────────

const syncLine = (sync) => {
  if (!sync) return null;
  if (sync.status === "queued" || sync.status === "running") {
    return t("sync_running", "Bringing in customers from your store… %{count} so far", {
      count: formatNumber((sync.carts || 0) + (sync.customers || 0)),
    });
  }
  if (sync.status === "done" && sync.finished_at) {
    return t("sync_done", "Updated from your store %{time}", { time: new Date(sync.finished_at).toLocaleString() });
  }
  if (sync.status === "failed" || sync.status === "stale") {
    return t("sync_failed", "The last update from your store didn't finish.");
  }
  return null;
};

const ContactsTable = ({ contacts, onOpen }) => (
  <DataTable
    columnContentTypes={["text", "text", "numeric", "text", "text"]}
    headings={[
      t("col_name", "Name"),
      t("col_phone", "Phone"),
      t("col_orders", "Orders"),
      t("col_tags", "Tags"),
      t("col_messages", "Campaigns"),
    ]}
    rows={contacts.map((c) => [
      onOpen
        ? <Link key={`n${c.id}`} removeUnderline onClick={() => onOpen(c)}>{c.name || c.phone}</Link>
        : c.name || c.phone,
      c.phone,
      c.order_count || 0,
      (c.tags || []).length ? (
        <InlineStack key={`t${c.id}`} gap="100" wrap>{c.tags.map((tag) => <Tag key={tag}>{tag}</Tag>)}</InlineStack>
      ) : "—",
      c.subscribed
        ? <Badge key={`s${c.id}`} tone="success">{t("subscribed", "Subscribed")}</Badge>
        : <Badge key={`s${c.id}`}>{t("unsubscribed", "Opted out")}</Badge>,
    ])}
  />
);

const Pager = ({ offset, pageSize, total, onPage }) => (
  <InlineStack align="space-between" blockAlign="center">
    <Text as="span" variant="bodySm" tone="subdued">
      {t("showing", "Showing %{from}–%{to} of %{total}", {
        from: formatNumber(offset + 1),
        to: formatNumber(Math.min(offset + pageSize, total)),
        total: formatNumber(total),
      })}
    </Text>
    <InlineStack gap="200">
      <Button disabled={offset === 0} onClick={() => onPage(Math.max(0, offset - pageSize))}>{t("previous", "Previous")}</Button>
      <Button disabled={offset + pageSize >= total} onClick={() => onPage(offset + pageSize)}>{t("next", "Next")}</Button>
    </InlineStack>
  </InlineStack>
);

const Contacts = ({ overview, onSync, syncing, audiences, filterAudience, onFilterAudience, onError, onChanged, importRef }) => {
  const [contacts, setContacts] = useState(null);
  const [total, setTotal] = useState(0);
  const [pageSize, setPageSize] = useState(50);
  const [offset, setOffset] = useState(0);
  const [q, setQ] = useState("");
  const [editing, setEditing] = useState(null);
  const [adding, setAdding] = useState(false);
  const [importing, setImporting] = useState(false);

  const sync = overview?.contacts?.sync;
  const syncRunning = ["queued", "running"].includes(sync?.status);

  const load = useCallback(async (off = 0) => {
    try {
      const params = new URLSearchParams({ offset: off });
      if (q.trim()) params.set("q", q.trim());
      if (filterAudience?.id) params.set("segment_id", filterAudience.id);
      const data = await api(`/api/whatsapp/contacts?${params.toString()}`);
      setContacts(data.contacts || []);
      setTotal(data.total || 0);
      setPageSize(data.page_size || 50);
      setOffset(off);
    } catch (e) { onError(e.message); setContacts((prev) => prev || []); }
  }, [q, filterAudience?.id, onError]);

  // Search as you type (debounced) and refresh whenever the filter or the store sync changes.
  useEffect(() => {
    const timer = setTimeout(() => load(0), 300);
    return () => clearTimeout(timer);
  }, [load, sync?.status]);

  useEffect(() => {
    if (importRef) importRef.current = () => setImporting(true);
  }, [importRef]);

  const refresh = async () => { await load(offset); onChanged(); };

  const line = syncLine(sync);

  return (
    <Card padding="0">
      <Box padding="400">
        <BlockStack gap="300">
          <InlineStack align="space-between" blockAlign="start" gap="200">
            <BlockStack gap="050">
              <Text as="h2" variant="headingMd">{t("contacts", "Contacts")}</Text>
              <Text as="p" variant="bodySm" tone="subdued">
                {t("contacts_summary", "%{total} contacts · %{subscribed} can receive campaigns", {
                  total: formatNumber(overview?.contacts?.total),
                  subscribed: formatNumber(overview?.contacts?.subscribed),
                })}
              </Text>
              {line && (
                <InlineStack gap="100" blockAlign="center">
                  {syncRunning && <Spinner size="small" />}
                  <Text as="span" variant="bodySm" tone={sync?.status === "failed" || sync?.status === "stale" ? "critical" : "subdued"}>
                    {line}
                  </Text>
                  {!syncRunning && (
                    <Link onClick={onSync} removeUnderline>
                      {syncing ? t("sync_starting", "Starting…") : t("sync_now", "Update now")}
                    </Link>
                  )}
                </InlineStack>
              )}
              {!line && (
                <Link onClick={onSync} removeUnderline>{t("sync_import", "Import customers from your store")}</Link>
              )}
            </BlockStack>
            <InlineStack gap="200">
              <Button onClick={() => setImporting(true)}>{t("upload_list", "Upload a list")}</Button>
              <Button onClick={() => setAdding(true)}>{t("add_contact", "Add contact")}</Button>
            </InlineStack>
          </InlineStack>

          <InlineStack gap="200" blockAlign="end" wrap>
            <Box minWidth="240px">
              <TextField
                labelHidden
                label={t("search", "Search")}
                placeholder={t("search_contacts", "Search by name, phone or email")}
                value={q}
                onChange={setQ}
                clearButton
                onClearButtonClick={() => setQ("")}
                autoComplete="off"
              />
            </Box>
            <Select
              labelHidden
              label={t("filter_audience", "Audience")}
              value={filterAudience?.id ? String(filterAudience.id) : ""}
              options={[
                { label: t("filter_everyone", "Everyone"), value: "" },
                ...(audiences || []).map((a) => ({ label: a.name, value: String(a.id) })),
              ]}
              onChange={(v) => onFilterAudience(v ? (audiences || []).find((a) => String(a.id) === v) : null)}
            />
          </InlineStack>
        </BlockStack>
      </Box>

      {contacts === null ? (
        <Box padding="400"><SkeletonBodyText lines={5} /></Box>
      ) : contacts.length === 0 ? (
        <Box padding="400" paddingBlockStart="0">
          <Text as="p" tone="subdued">
            {filterAudience
              ? t("contacts_none_in_audience", "Nobody matches this audience yet.")
              : q
                ? t("contacts_none_search", "No contacts match your search.")
                : t("contacts_none", "No contacts yet. Import customers from your store or upload a list.")}
          </Text>
        </Box>
      ) : (
        <>
          <ContactsTable contacts={contacts} onOpen={setEditing} />
          <Box padding="400">
            <Pager offset={offset} pageSize={pageSize} total={total} onPage={load} />
          </Box>
        </>
      )}

      {(adding || editing) && (
        <ContactModal
          contact={editing}
          onClose={() => { setAdding(false); setEditing(null); }}
          onSaved={async () => { setAdding(false); setEditing(null); await refresh(); }}
          onError={onError}
        />
      )}
      {importing && (
        <ImportModal
          onClose={() => setImporting(false)}
          onDone={async () => { setImporting(false); await refresh(); }}
        />
      )}
    </Card>
  );
};

const ContactModal = ({ contact, onClose, onSaved, onError }) => {
  const [phone, setPhone] = useState(contact?.phone || "");
  const [name, setName] = useState(contact?.name || "");
  const [email, setEmail] = useState(contact?.email || "");
  const [tags, setTags] = useState((contact?.tags || []).join(", "));
  const [subscribed, setSubscribed] = useState(contact ? !!contact.subscribed : true);
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [err, setErr] = useState("");

  const save = async () => {
    setBusy(true);
    setErr("");
    try {
      const body = { name, email, tags: parseTags(tags), subscribed };
      if (contact) {
        await api(`/api/whatsapp/contacts/${contact.id}`, { method: "PATCH", body });
      } else {
        await api("/api/whatsapp/contacts", { method: "POST", body: { ...body, phone } });
      }
      onSaved();
    } catch (e) { setErr(e.message); setBusy(false); }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await api(`/api/whatsapp/contacts/${contact.id}`, { method: "DELETE" });
      onSaved();
    } catch (e) { onError(e.message); onClose(); }
  };

  if (confirmDelete) {
    return (
      <Modal
        open
        onClose={() => setConfirmDelete(false)}
        title={t("contact_delete_title", "Delete this contact?")}
        primaryAction={{ content: t("action_delete", "Delete"), destructive: true, loading: busy, onAction: remove }}
        secondaryActions={[{ content: t("keep", "Keep it"), onAction: () => setConfirmDelete(false) }]}
      >
        <Modal.Section>
          <Text as="p">
            {t("contact_delete_body", "%{phone} is removed from your contacts. If they're still a customer, the next update from your store may add them back.", { phone: contact.phone })}
          </Text>
        </Modal.Section>
      </Modal>
    );
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={contact ? contact.name || contact.phone : t("add_contact", "Add contact")}
      primaryAction={{ content: t("save", "Save"), onAction: save, loading: busy, disabled: !contact && !phone.trim() }}
      secondaryActions={[
        ...(contact ? [{ content: t("action_delete", "Delete"), destructive: true, onAction: () => setConfirmDelete(true) }] : []),
        { content: t("back", "Back"), onAction: onClose },
      ]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          {err && <Banner tone="critical" onDismiss={() => setErr("")}>{err}</Banner>}
          {contact ? (
            <Text as="p" variant="bodySm" tone="subdued">{contact.phone}</Text>
          ) : (
            <TextField
              label={t("contact_phone", "WhatsApp number")}
              value={phone}
              onChange={setPhone}
              placeholder="919999988888"
              helpText={t("contact_phone_help", "Include the country code, e.g. 91 for India.")}
              autoComplete="off"
            />
          )}
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
            <TextField label={t("contact_name", "Name")} value={name} onChange={setName} autoComplete="off" />
            <TextField label={t("contact_email", "Email")} value={email} onChange={setEmail} autoComplete="off" />
          </InlineGrid>
          <TextField
            label={t("contact_tags", "Tags")}
            value={tags}
            onChange={setTags}
            placeholder="vip, loyal"
            helpText={t("contact_tags_help", "Separate with commas. Use tags to build audiences.")}
            autoComplete="off"
          />
          <Checkbox
            label={t("contact_subscribed", "Can receive campaigns")}
            helpText={t("contact_subscribed_help", "Turn off if this person asked not to get marketing messages.")}
            checked={subscribed}
            onChange={setSubscribed}
          />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

const ImportModal = ({ onClose, onDone }) => {
  const [tags, setTags] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);
  const [err, setErr] = useState("");

  const upload = async (files) => {
    if (!files?.[0]) return;
    setBusy(true);
    setResult(null);
    setErr("");
    try {
      const fd = new FormData();
      fd.append("file", files[0]);
      parseTags(tags).forEach((tag) => fd.append("tags[]", tag));
      const created = await api("/api/whatsapp/contacts/import", { method: "POST", form: fd });
      setResult(await waitForImport(created.id, created));
    } catch (e) { setErr(e.message); } finally { setBusy(false); }
  };

  const done = result?.status === "ready";

  return (
    <Modal
      open
      onClose={onClose}
      title={t("import_title", "Upload a list of contacts")}
      primaryAction={done ? { content: t("done", "Done"), onAction: onDone } : undefined}
      secondaryActions={[{ content: done ? t("upload_another", "Upload another") : t("back", "Back"), onAction: done ? () => setResult(null) : onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          {err && <Banner tone="critical" onDismiss={() => setErr("")}>{err}</Banner>}
          {!done && (
            <>
              <Text as="p">
                {t("import_help", "A CSV file with a phone number column (with country code). Name and email columns are picked up too, and any other column can be used to personalise messages.")}
              </Text>
              <TextField
                label={t("import_tags", "Tag everyone in this list (optional)")}
                value={tags}
                onChange={setTags}
                placeholder={t("import_tags_placeholder", "e.g. diwali-2026")}
                helpText={t("import_tags_help", "Makes it easy to send to just this list later.")}
                autoComplete="off"
              />
              <DropZone accept=".csv,text/csv" type="file" onDrop={upload} allowMultiple={false} disabled={busy}>
                {busy ? (
                  <Box padding="600">
                    <InlineStack gap="200" align="center" blockAlign="center">
                      <Spinner size="small" />
                      <Text as="span">{t("importing", "Reading your list…")}</Text>
                    </InlineStack>
                  </Box>
                ) : (
                  <DropZone.FileUpload actionTitle={t("choose_file", "Choose CSV file")} actionHint={t("or_drop", "or drop it here")} />
                )}
              </DropZone>
            </>
          )}
          {done && (
            <Banner tone="success">
              {t("import_done", "%{valid} of %{rows} rows added to your contacts.", {
                valid: formatNumber(result.valid_count),
                rows: formatNumber(result.row_count),
              })}
            </Banner>
          )}
          {result?.status === "failed" && (
            <Banner tone="critical">{t("import_failed", "We couldn't read this file: %{error}", { error: result.error })}</Banner>
          )}
          {result && !["ready", "failed"].includes(result.status) && (
            <Banner tone="info">{t("import_slow", "Still reading a large file. Contacts will appear in a minute or two; you can close this.")}</Banner>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

// ── Audience people ───────────────────────────────────────────────────

const AudiencePeopleModal = ({ audience, onClose, onError }) => {
  const [contacts, setContacts] = useState(null);
  const [total, setTotal] = useState(0);
  const [pageSize, setPageSize] = useState(50);
  const [offset, setOffset] = useState(0);
  const [q, setQ] = useState("");

  const load = useCallback(async (off = 0) => {
    try {
      const params = new URLSearchParams({ offset: off, segment_id: audience.id });
      if (q.trim()) params.set("q", q.trim());
      const data = await api(`/api/whatsapp/contacts?${params.toString()}`);
      setContacts(data.contacts || []);
      setTotal(data.total || 0);
      setPageSize(data.page_size || 50);
      setOffset(off);
    } catch (e) { onError(e.message); setContacts((prev) => prev || []); }
  }, [q, audience.id, onError]);

  useEffect(() => {
    const timer = setTimeout(() => load(0), 300);
    return () => clearTimeout(timer);
  }, [load]);

  return (
    <Modal
      open
      size="large"
      onClose={onClose}
      title={audience.name}
      primaryAction={{
        content: t("send_to_audience", "Send a campaign"),
        onAction: () => navigateToPreservingParams(paths.newCampaign(), { audience: audience.id }),
      }}
      secondaryActions={[{ content: t("close", "Close"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="300">
          <Text as="p" variant="bodySm" tone="subdued">
            {audience.description || describeFilters(audience.filters)}
          </Text>
          <TextField
            labelHidden
            label={t("search", "Search")}
            placeholder={t("search_contacts", "Search by name, phone or email")}
            value={q}
            onChange={setQ}
            clearButton
            onClearButtonClick={() => setQ("")}
            autoComplete="off"
          />
        </BlockStack>
      </Modal.Section>
      {contacts === null ? (
        <Modal.Section><SkeletonBodyText lines={5} /></Modal.Section>
      ) : contacts.length === 0 ? (
        <Modal.Section>
          <Text as="p" tone="subdued">
            {q
              ? t("contacts_none_search", "No contacts match your search.")
              : t("contacts_none_in_audience", "Nobody matches this audience yet.")}
          </Text>
        </Modal.Section>
      ) : (
        <>
          <ContactsTable contacts={contacts} />
          <Modal.Section>
            <Pager offset={offset} pageSize={pageSize} total={total} onPage={load} />
          </Modal.Section>
        </>
      )}
    </Modal>
  );
};

// ── Opted out ─────────────────────────────────────────────────────────

const OptOuts = ({ onError }) => {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState(null);
  const [total, setTotal] = useState(0);
  const [phone, setPhone] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await api("/api/whatsapp/opt_outs");
      setItems(data.opt_outs || []);
      setTotal(data.total || 0);
    } catch (e) { onError(e.message); setItems([]); }
  }, [onError]);

  useEffect(() => { load(); }, [load]);

  const add = async () => {
    setBusy(true);
    try {
      await api("/api/whatsapp/opt_outs", { method: "POST", body: { phone } });
      setPhone("");
      await load();
    } catch (e) { onError(e.message); } finally { setBusy(false); }
  };

  const remove = async (p) => {
    try {
      await api(`/api/whatsapp/opt_outs/${p}`, { method: "DELETE" });
      await load();
    } catch (e) { onError(e.message); }
  };

  return (
    <Card>
      <BlockStack gap="300">
        <InlineStack align="space-between" blockAlign="center" gap="200">
          <BlockStack gap="050">
            <Text as="h2" variant="headingMd">{t("optouts_title", "Opted out (%{count})", { count: formatNumber(total) })}</Text>
            <Text as="p" variant="bodySm" tone="subdued">
              {t("optouts_help", "These numbers never get campaigns. Anyone who replies STOP is added automatically.")}
            </Text>
          </BlockStack>
          <Button variant="plain" disclosure={open ? "up" : "down"} onClick={() => setOpen((v) => !v)}>
            {open ? t("hide", "Hide") : t("manage", "Manage")}
          </Button>
        </InlineStack>
        <Collapsible open={open} id="opt-outs">
          <BlockStack gap="300">
            <InlineStack gap="200" blockAlign="end" wrap>
              <Box minWidth="240px">
                <TextField
                  label={t("optout_add", "Stop messaging a number")}
                  value={phone}
                  onChange={setPhone}
                  placeholder="919999988888"
                  autoComplete="off"
                />
              </Box>
              <Button onClick={add} loading={busy} disabled={!phone.trim()}>{t("optout_add_action", "Add")}</Button>
            </InlineStack>
            {items && items.length > 0 && (
              <DataTable
                columnContentTypes={["text", "text", "text", "text"]}
                headings={[t("col_phone", "Phone"), t("col_reason", "Reason"), t("col_when", "Since"), ""]}
                rows={items.map((o) => [
                  o.phone,
                  o.reason || "—",
                  o.opted_out_at ? new Date(o.opted_out_at).toLocaleDateString() : "—",
                  <Button key={o.phone} size="slim" variant="plain" onClick={() => remove(o.phone)}>
                    {t("optout_remove", "Allow again")}
                  </Button>,
                ])}
              />
            )}
          </BlockStack>
        </Collapsible>
      </BlockStack>
    </Card>
  );
};

// ── Tab ───────────────────────────────────────────────────────────────

const AudiencesTab = ({ overview, onSync, syncing, onChanged, onError, importRef }) => {
  const [audiences, setAudiences] = useState(null);
  const [filterAudience, setFilterAudience] = useState(null);
  const [viewing, setViewing] = useState(null);

  const loadAudiences = useCallback(async () => {
    try {
      const data = await api("/api/whatsapp/segments");
      setAudiences(data.segments || []);
    } catch (e) { onError(e.message); setAudiences((prev) => prev || []); }
  }, [onError]);

  useEffect(() => { loadAudiences(); }, [loadAudiences]);

  return (
    <BlockStack gap="400">
      <SavedAudiences
        audiences={audiences}
        onReload={async () => { await loadAudiences(); onChanged(); }}
        onView={setViewing}
        onError={onError}
      />
      <Contacts
        overview={overview}
        onSync={onSync}
        syncing={syncing}
        audiences={audiences}
        filterAudience={filterAudience}
        onFilterAudience={setFilterAudience}
        onError={onError}
        onChanged={onChanged}
        importRef={importRef}
      />
      <OptOuts onError={onError} />
      {viewing && (
        <AudiencePeopleModal
          audience={viewing}
          onClose={() => setViewing(null)}
          onError={onError}
        />
      )}
    </BlockStack>
  );
};

export default AudiencesTab;

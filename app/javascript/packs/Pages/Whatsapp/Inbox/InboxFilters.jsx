import React, { useEffect, useRef, useState } from "react";
import { BlockStack, Button, Icon, InlineGrid, Select, TextField } from "@shopify/polaris";
import { SearchMinor } from "@shopify/polaris-icons";
import { t } from "./format";

const SEARCH_DEBOUNCE_MS = 300;

const InboxFilters = ({ filters, onChange, agents = [], labels = [], accounts = [] }) => {
  const [query, setQuery] = useState(filters.q || "");
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  useEffect(() => {
    if (query === (filters.q || "")) return undefined;
    const timer = setTimeout(() => onChangeRef.current({ q: query.trim() }), SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query, filters.q]);

  const assigneeOptions = [
    { label: t("filters.everyone", "Everyone"), value: "" },
    { label: t("filters.assigned_to_me", "Assigned to me"), value: "me" },
    { label: t("filters.unassigned", "Unassigned"), value: "unassigned" },
    ...agents.filter((a) => !a.is_me).map((a) => ({ label: a.name, value: String(a.id) })),
  ];

  const labelOptions = [
    { label: t("filters.all_labels", "All labels"), value: "" },
    ...labels.map((l) => ({ label: l.name, value: String(l.id) })),
  ];

  const accountOptions = [
    { label: t("filters.all_numbers", "All numbers"), value: "" },
    ...accounts.map((a) => ({ label: a.label, value: String(a.id) })),
  ];

  return (
    <BlockStack gap="200">
      <TextField
        label={t("filters.search_label", "Search conversations")}
        labelHidden
        value={query}
        onChange={setQuery}
        placeholder={t("filters.search_placeholder", "Search name, phone or order number")}
        prefix={<Icon source={SearchMinor} tone="subdued" />}
        clearButton
        onClearButtonClick={() => setQuery("")}
        autoComplete="off"
      />
      <InlineGrid columns={accounts.length > 1 ? 3 : 2} gap="200">
        <Select
          label={t("filters.assignee_label", "Assignee")}
          labelHidden
          options={assigneeOptions}
          value={filters.assignee || ""}
          onChange={(value) => onChange({ assignee: value })}
        />
        <Select
          label={t("filters.label_label", "Label")}
          labelHidden
          options={labelOptions}
          value={filters.label_id || ""}
          onChange={(value) => onChange({ label_id: value })}
        />
        {accounts.length > 1 && (
          <Select
            label={t("filters.number_label", "WhatsApp number")}
            labelHidden
            options={accountOptions}
            value={filters.account_id || ""}
            onChange={(value) => onChange({ account_id: value })}
          />
        )}
      </InlineGrid>
      <div>
        <Button size="slim" pressed={!!filters.unread} onClick={() => onChange({ unread: !filters.unread })}>
          {t("list.unread", "Unread only")}
        </Button>
      </div>
    </BlockStack>
  );
};

export default InboxFilters;

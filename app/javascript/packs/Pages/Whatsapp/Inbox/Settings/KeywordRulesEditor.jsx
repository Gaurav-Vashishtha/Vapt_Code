import React, { useState } from "react";
import {
  BlockStack,
  InlineStack,
  Box,
  Text,
  Button,
  TextField,
  Select,
  Checkbox,
  Tag,
  Divider,
} from "@shopify/polaris";
import { PlusMinor, DeleteMinor } from "@shopify/polaris-icons";
import I18n from "../../../../i18n-lang";

const t = (key, defaultValue, opts = {}) =>
  I18n.t(`whatsapp_inbox_settings.${key}`, { defaultValue, ...opts });

export const MAX_RULES = 10;
const MAX_KEYWORDS = 10;
const MAX_KEYWORD_LENGTH = 30;
const MAX_REPLY_LENGTH = 1024;

const VARIABLE_LABELS = {
  name: "Customer name",
  first_name: "First name",
  order_number: "Order number",
  order_status: "Order status",
  tracking_url: "Tracking link",
  order_amount: "Order amount",
  store_name: "Store name",
};

export const appendToken = (text, token) => {
  const current = text || "";
  if (!current) return token;
  return /\s$/.test(current) ? `${current}${token}` : `${current} ${token}`;
};

export const VariableButtons = ({ variables, onInsert }) => (
  <BlockStack gap="100">
    <Text as="span" variant="bodySm" tone="subdued">
      {t("variables.title", "Insert customer details")}
    </Text>
    <InlineStack gap="100" wrap>
      {(variables || Object.keys(VARIABLE_LABELS)).map((key) => (
        <Button key={key} size="micro" onClick={() => onInsert(`{{${key}}}`)}>
          {t(`variables.${key}`, VARIABLE_LABELS[key] || key)}
        </Button>
      ))}
    </InlineStack>
  </BlockStack>
);

const newRuleId = () =>
  typeof crypto !== "undefined" && crypto.randomUUID
    ? crypto.randomUUID()
    : `rule-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

export const ruleErrors = (rule) => {
  const errors = {};
  if (!rule.keywords || rule.keywords.length === 0) {
    errors.keywords = t("keyword_rules.keywords_required", "Add at least one keyword");
  }
  if (!rule.reply_text || !rule.reply_text.trim()) {
    errors.reply = t("keyword_rules.reply_required", "Write the reply to send");
  }
  return errors;
};

const RuleRow = ({ rule, index, variables, showErrors, onChange, onRemove }) => {
  const [draft, setDraft] = useState("");
  const errors = showErrors ? ruleErrors(rule) : {};
  const keywords = rule.keywords || [];

  const addKeywords = (raw) => {
    const incoming = raw
      .split(",")
      .map((k) => k.trim().replace(/\s+/g, " ").slice(0, MAX_KEYWORD_LENGTH))
      .filter(Boolean);
    if (incoming.length === 0) return;
    const seen = new Set(keywords.map((k) => k.toLowerCase()));
    const next = [...keywords];
    incoming.forEach((k) => {
      if (!seen.has(k.toLowerCase()) && next.length < MAX_KEYWORDS) {
        seen.add(k.toLowerCase());
        next.push(k);
      }
    });
    onChange({ ...rule, keywords: next });
    setDraft("");
  };

  const handleDraft = (value) => {
    if (value.includes(",")) {
      addKeywords(value);
    } else {
      setDraft(value);
    }
  };

  return (
    <BlockStack gap="300">
      <InlineStack align="space-between" blockAlign="center">
        <Text as="h3" variant="headingSm">
          {t("keyword_rules.rule_title", "Rule %{number}", { number: index + 1 })}
        </Text>
        <InlineStack gap="200" blockAlign="center">
          <Checkbox
            label={t("keyword_rules.enabled", "On")}
            checked={rule.enabled !== false}
            onChange={(checked) => onChange({ ...rule, enabled: checked })}
          />
          <Button
            icon={DeleteMinor}
            variant="plain"
            tone="critical"
            accessibilityLabel={t("keyword_rules.remove", "Remove rule")}
            onClick={onRemove}
          />
        </InlineStack>
      </InlineStack>
      <div
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            addKeywords(draft);
          }
        }}
      >
        <TextField
          label={t("keyword_rules.keywords", "Keywords")}
          value={draft}
          onChange={handleDraft}
          onBlur={() => addKeywords(draft)}
          autoComplete="off"
          maxLength={MAX_KEYWORD_LENGTH}
          placeholder={t("keyword_rules.keywords_placeholder", "e.g. track, where is my order")}
          helpText={t("keyword_rules.keywords_help", "Press Enter or type a comma after each keyword. Up to 10.")}
          error={errors.keywords}
          disabled={keywords.length >= MAX_KEYWORDS}
          connectedRight={
            <Select
              label={t("keyword_rules.match", "Match")}
              labelHidden
              options={[
                { label: t("keyword_rules.match_contains", "Message contains the word"), value: "contains" },
                { label: t("keyword_rules.match_exact", "Message is exactly the word"), value: "exact" },
              ]}
              value={rule.match || "contains"}
              onChange={(value) => onChange({ ...rule, match: value })}
            />
          }
        />
      </div>
      {keywords.length > 0 && (
        <InlineStack gap="100" wrap>
          {keywords.map((keyword) => (
            <Tag
              key={keyword}
              onRemove={() => onChange({ ...rule, keywords: keywords.filter((k) => k !== keyword) })}
            >
              {keyword}
            </Tag>
          ))}
        </InlineStack>
      )}
      <TextField
        label={t("keyword_rules.reply", "Reply")}
        value={rule.reply_text || ""}
        onChange={(value) => onChange({ ...rule, reply_text: value })}
        multiline={3}
        maxLength={MAX_REPLY_LENGTH}
        showCharacterCount
        autoComplete="off"
        error={errors.reply}
      />
      <VariableButtons
        variables={variables}
        onInsert={(token) => onChange({ ...rule, reply_text: appendToken(rule.reply_text, token) })}
      />
    </BlockStack>
  );
};

const KeywordRulesEditor = ({ rules, variables, showErrors, onChange }) => {
  const list = rules || [];

  const update = (index, rule) => onChange(list.map((r, i) => (i === index ? rule : r)));
  const remove = (index) => onChange(list.filter((_, i) => i !== index));
  const add = () =>
    onChange([
      ...list,
      { id: newRuleId(), keywords: [], match: "contains", reply_text: "", enabled: true },
    ]);

  return (
    <BlockStack gap="400">
      {list.length === 0 && (
        <Text as="p" tone="subdued">
          {t(
            "keyword_rules.empty",
            "No keyword replies yet. Example: when a customer writes \"track\", reply with their tracking link."
          )}
        </Text>
      )}
      {list.map((rule, index) => (
        <BlockStack key={rule.id || index} gap="400">
          {index > 0 && <Divider />}
          <RuleRow
            rule={rule}
            index={index}
            variables={variables}
            showErrors={showErrors}
            onChange={(next) => update(index, next)}
            onRemove={() => remove(index)}
          />
        </BlockStack>
      ))}
      <Box>
        <InlineStack gap="200" blockAlign="center">
          <Button icon={PlusMinor} onClick={add} disabled={list.length >= MAX_RULES}>
            {t("keyword_rules.add", "Add keyword reply")}
          </Button>
          {list.length >= MAX_RULES && (
            <Text as="span" variant="bodySm" tone="subdued">
              {t("keyword_rules.limit", "You can have up to %{count} keyword replies", { count: MAX_RULES })}
            </Text>
          )}
        </InlineStack>
      </Box>
    </BlockStack>
  );
};

export default KeywordRulesEditor;

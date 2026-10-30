import React, { useEffect, useState } from "react";
import { Modal, BlockStack, Checkbox, InlineGrid, Select, TextField, Text, Button, InlineStack, Divider } from "@shopify/polaris";
import { DeleteMinor } from "@shopify/polaris-icons";
import CountryMultiSelect from "../components/CountryMultiSelect";
import { LOCKED_FIELD_KEYS, SCHEMA_REQUIRED_FIELD_KEYS } from "../defaults";
import { LIMITS, localeName } from "../constants";
import { clone, toInt } from "../utils";
import { t } from "../i18n";
import { defaultText } from "./texts";
import { fieldTypeName } from "./fieldLabels";

const TEXT_TYPES = ["text", "textarea", "tel", "email", "postal", "city"];
const NO_PLACEHOLDER = ["consent", "checkbox", "radio", "select", "country", "date", "province"];

const regexError = (pattern) => {
  if (!pattern) return undefined;
  if (pattern.length > LIMITS.REGEX_MAX_CHARS) {
    return t("designer.regex_too_long", "The pattern can be up to 200 characters.");
  }
  try {
    // eslint-disable-next-line no-new
    new RegExp(pattern);
    return undefined;
  } catch (_) {
    return t("designer.regex_invalid", "This is not a valid pattern.");
  }
};

/**
 * Per-field settings (FRM-3, FRM-15): show / hide, required, width, the
 * label / placeholder / error text for the locale being edited, validation.
 * Texts are not stored on the field: they are text keys (C.2).
 */
const FieldEditor = ({ open, field, texts, defaultsTexts, locale, onClose, onSave }) => {
  const [draft, setDraft] = useState(null);
  const [strings, setStrings] = useState({ label: "", placeholder: "", error: "" });

  useEffect(() => {
    if (!open || !field) return;
    const own = (texts && texts[locale]) || {};
    setDraft(clone(field));
    setStrings({
      label: own[`label_${field.key}`] || "",
      placeholder: own[`placeholder_${field.key}`] || "",
      error: own[`error_${field.key}`] || "",
    });
  }, [open, field, texts, locale]);

  if (!draft) return null;

  const isCustom = draft.key.startsWith("cf_");
  const locked = LOCKED_FIELD_KEYS.includes(draft.key);
  const followsSchema = SCHEMA_REQUIRED_FIELD_KEYS.includes(draft.key);
  const validation = draft.validation || {};
  const hasOptions = draft.type === "select" || draft.type === "radio";
  const patternError = regexError(validation.regex);
  const optionsInvalid = hasOptions && (draft.options || []).filter((option) => option.value).length === 0;

  const set = (key, value) => setDraft((current) => ({ ...current, [key]: value }));
  const setValidation = (key, value) =>
    setDraft((current) => {
      const next = { ...(current.validation || {}) };
      if (value === null || value === "" || value === false) delete next[key];
      else next[key] = value;
      return { ...current, validation: next };
    });
  const setOption = (index, patch) =>
    setDraft((current) => {
      const options = (current.options || []).map((option, i) => (i === index ? { ...option, ...patch } : option));
      return { ...current, options };
    });

  const requiredValue = draft.required === null || draft.required === undefined ? "schema" : draft.required ? "yes" : "no";
  const requiredOptions = [
    ...(followsSchema ? [{ label: t("designer.required_schema", "Follow the buyer's country"), value: "schema" }] : []),
    { label: t("designer.field_required", "Required"), value: "yes" },
    { label: t("designer.field_optional", "Optional"), value: "no" },
  ];

  const placeholderOf = (kind) => defaultText(defaultsTexts, locale, `${kind}_${draft.key}`) || (kind === "error" ? defaultText(defaultsTexts, locale, "error_required") : "");

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("designer.edit_field_title", "Edit field: %{name}", {
        name: strings.label || defaultText(defaultsTexts, locale, `label_${draft.key}`) || draft.key,
      })}
      primaryAction={{
        content: t("common.done", "Done"),
        disabled: !!patternError || optionsInvalid,
        onAction: () => onSave(draft, strings),
      }}
      secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.field_type_line", "Type: %{type}", { type: fieldTypeName(draft.type) })}
          </Text>
          <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
            <Checkbox
              label={t("designer.field_show", "Show this field")}
              checked={!!draft.enabled}
              disabled={locked}
              helpText={locked ? t("designer.field_locked", "Always shown") : undefined}
              onChange={(value) => set("enabled", value)}
            />
            <Select
              label={t("designer.field_requirement", "Required")}
              options={requiredOptions}
              value={requiredValue}
              disabled={draft.key === "phone" || draft.key === "country"}
              onChange={(value) => set("required", value === "schema" ? null : value === "yes")}
            />
            <Select
              label={t("designer.field_width", "Width")}
              options={[
                { label: t("designer.width_full", "Full width"), value: "full" },
                { label: t("designer.width_half", "Half width"), value: "half" },
              ]}
              value={draft.width || "full"}
              onChange={(value) => set("width", value)}
            />
          </InlineGrid>

          <Divider />
          <Text as="h4" variant="headingSm">
            {t("designer.field_texts", "Texts (%{language})", { language: localeName(locale) })}
          </Text>
          <TextField
            label={t("designer.field_label", "Label")}
            value={strings.label}
            placeholder={placeholderOf("label")}
            onChange={(value) => setStrings((current) => ({ ...current, label: value }))}
            maxLength={LIMITS.TEXT_MAX_CHARS}
            autoComplete="off"
          />
          {!NO_PLACEHOLDER.includes(draft.type) && (
            <TextField
              label={t("designer.field_placeholder", "Placeholder")}
              value={strings.placeholder}
              placeholder={placeholderOf("placeholder")}
              onChange={(value) => setStrings((current) => ({ ...current, placeholder: value }))}
              maxLength={LIMITS.TEXT_MAX_CHARS}
              autoComplete="off"
            />
          )}
          <TextField
            label={t("designer.field_error", "Error text")}
            value={strings.error}
            placeholder={placeholderOf("error")}
            onChange={(value) => setStrings((current) => ({ ...current, error: value }))}
            maxLength={LIMITS.TEXT_MAX_CHARS}
            helpText={t("designer.field_texts_help", "Leave a text empty to use the default for this language.")}
            autoComplete="off"
          />

          {hasOptions && (
            <>
              <Divider />
              <Text as="h4" variant="headingSm">
                {t("designer.options_title", "Choices")}
              </Text>
              {(draft.options || []).map((option, index) => (
                <InlineStack key={index} gap="200" blockAlign="end" wrap={false}>
                  <div style={{ flex: 1 }}>
                    <TextField
                      label={t("designer.option_label", "Choice %{number}", { number: index + 1 })}
                      value={(option.label && (option.label[locale] || option.label.default)) || ""}
                      onChange={(value) =>
                        setOption(index, {
                          label: { ...(option.label || {}), default: (option.label && option.label.default) || value, [locale]: value },
                          value: option.value || value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").slice(0, 40),
                        })
                      }
                      autoComplete="off"
                    />
                  </div>
                  <Button
                    icon={DeleteMinor}
                    accessibilityLabel={t("common.delete", "Delete")}
                    onClick={() => set("options", (draft.options || []).filter((_, i) => i !== index))}
                  />
                </InlineStack>
              ))}
              <InlineStack>
                <Button
                  onClick={() => set("options", [...(draft.options || []), { value: "", label: { default: "" } }])}
                  disabled={(draft.options || []).length >= 30}
                >
                  {t("designer.add_option", "Add choice")}
                </Button>
              </InlineStack>
            </>
          )}

          {draft.type === "consent" && (
            <>
              <Divider />
              <Checkbox
                label={t("designer.consent_default_checked", "Ticked by default")}
                checked={!!draft.default_checked}
                onChange={(value) => set("default_checked", value)}
              />
              <InlineStack gap="400">
                {["sms", "email"].map((channel) => (
                  <Checkbox
                    key={channel}
                    label={channel === "sms" ? t("designer.consent_sms", "SMS marketing") : t("designer.consent_email", "Email marketing")}
                    checked={(draft.channels || []).includes(channel)}
                    onChange={(value) =>
                      set(
                        "channels",
                        value ? [...new Set([...(draft.channels || []), channel])] : (draft.channels || []).filter((item) => item !== channel),
                      )
                    }
                  />
                ))}
              </InlineStack>
            </>
          )}

          {TEXT_TYPES.includes(draft.type) && draft.key !== "phone" && (
            <>
              <Divider />
              <Text as="h4" variant="headingSm">
                {t("designer.validation_title", "Validation")}
              </Text>
              <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                <TextField
                  label={t("designer.validation_min", "Minimum length")}
                  type="number"
                  min={0}
                  value={validation.min == null ? "" : String(validation.min)}
                  onChange={(value) => setValidation("min", toInt(value))}
                  autoComplete="off"
                />
                <TextField
                  label={t("designer.validation_max", "Maximum length")}
                  type="number"
                  min={1}
                  value={validation.max == null ? "" : String(validation.max)}
                  onChange={(value) => setValidation("max", toInt(value))}
                  autoComplete="off"
                />
              </InlineGrid>
              <TextField
                label={t("designer.regex", "Pattern (regular expression)")}
                value={validation.regex || ""}
                onChange={(value) => setValidation("regex", value)}
                error={patternError}
                helpText={t("designer.regex_help", "Optional. The value must match this pattern, for example ^[0-9]{6}$.")}
                autoComplete="off"
                monospaced
              />
              <Checkbox
                label={t("designer.latin_only", "Latin characters only")}
                checked={!!validation.latin_only}
                onChange={(value) => setValidation("latin_only", value)}
              />
            </>
          )}

          {!locked && (
            <>
              <Divider />
              <CountryMultiSelect
                label={t("designer.only_countries", "Show only for buyers in (optional)")}
                value={draft.only_countries || []}
                onChange={(codes) =>
                  setDraft((current) => {
                    const next = { ...current };
                    if (codes.length) next.only_countries = codes;
                    else delete next.only_countries;
                    return next;
                  })
                }
              />
            </>
          )}

          {isCustom && (
            <Text as="p" variant="bodySm" tone="subdued">
              {t("designer.custom_field_note", "The buyer's answer is saved on the order as an additional detail.")}
            </Text>
          )}
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default FieldEditor;

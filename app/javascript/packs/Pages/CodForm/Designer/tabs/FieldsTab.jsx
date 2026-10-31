import React, { useState } from "react";
import { Badge, Banner, BlockStack, Button, Card, Checkbox, Divider, InlineStack, Text } from "@shopify/polaris";
import { EditMinor, DeleteMinor } from "@shopify/polaris-icons";
import Gate from "../../components/Gate";
import { FEATURES } from "../../constants";
import { LOCKED_FIELD_KEYS } from "../../defaults";
import { moveItem } from "../../utils";
import { t } from "../../i18n";
import useCodFormBootstrap from "../../useCodFormBootstrap";
import SortableList from "../SortableList";
import FieldEditor from "../FieldEditor";
import CustomFieldModal from "../CustomFieldModal";
import { resolveText } from "../texts";
import { fieldTypeName } from "../fieldLabels";

const GROUPS = ["contact", "address"];

/** Fields list: show / hide, required, reorder, edit texts and validation, custom fields. */
const FieldsTab = ({ config, setConfig, defaultsTexts, locale }) => {
  const [editing, setEditing] = useState(null);
  const [adding, setAdding] = useState(false);
  const bootstrap = useCodFormBootstrap();
  const fields = config.fields || [];
  const oneNameField = !fields.some((field) => field.key === "last_name" && field.enabled);

  const writeFields = (next) => setConfig((current) => ({ ...current, fields: next }));

  const patchField = (key, patch) =>
    writeFields(fields.map((field) => (field.key === key ? { ...field, ...patch } : field)));

  const reorder = (group, from, to) => {
    const inGroup = fields.filter((field) => field.group === group);
    const moved = moveItem(inGroup, from, to);
    const next = [];
    GROUPS.forEach((name) => {
      (name === group ? moved : fields.filter((field) => field.group === name)).forEach((field) => next.push(field));
    });
    fields.filter((field) => !GROUPS.includes(field.group)).forEach((field) => next.push(field));
    writeFields(next);
  };

  const saveField = (field, strings) => {
    setConfig((current) => {
      const texts = { ...(current.texts || {}) };
      const set = { ...(texts[locale] || {}) };
      [
        [`label_${field.key}`, strings.label],
        [`placeholder_${field.key}`, strings.placeholder],
        [`error_${field.key}`, strings.error],
      ].forEach(([key, value]) => {
        if (value) set[key] = value;
        else delete set[key];
      });
      // Kept even when empty: an added language stays in the list (see setTextOverride).
      if (Object.keys(set).length || texts[locale]) texts[locale] = set;
      return {
        ...current,
        texts,
        fields: (current.fields || []).map((item) => (item.key === field.key ? field : item)),
      };
    });
    setEditing(null);
  };

  const addCustom = (field, label) => {
    setConfig((current) => {
      const texts = { ...(current.texts || {}) };
      // The label is written for English (the storefront's last fallback) and the locale being edited.
      ["en", locale].forEach((code) => {
        texts[code] = { ...(texts[code] || {}), [`label_${field.key}`]: label };
      });
      return { ...current, texts, fields: [...(current.fields || []), field] };
    });
    setAdding(false);
  };

  const removeCustom = (key) =>
    setConfig((current) => {
      const texts = {};
      Object.keys(current.texts || {}).forEach((code) => {
        const set = { ...current.texts[code] };
        delete set[`label_${key}`];
        delete set[`placeholder_${key}`];
        delete set[`error_${key}`];
        if (Object.keys(set).length) texts[code] = set;
      });
      return { ...current, texts, fields: (current.fields || []).filter((field) => field.key !== key) };
    });

  const renderField = (field) => {
    const locked = LOCKED_FIELD_KEYS.includes(field.key);
    const custom = field.key.startsWith("cf_");
    // With Last name hidden, First name is the one "Full name" field (the storefront labels it
    // so unless the merchant wrote a label of their own).
    const ownLabel = ((config.texts || {})[locale] || {})[`label_${field.key}`];
    const fullName = field.key === "first_name" && oneNameField && !ownLabel;
    const label =
      (fullName && (resolveText(config, defaultsTexts, locale, "label_full_name") || t("designer.full_name", "Full name"))) ||
      resolveText(config, defaultsTexts, locale, `label_${field.key}`) ||
      field.key;
    return (
      <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
        <BlockStack gap="050">
          <InlineStack gap="200" blockAlign="center" wrap>
            <Text as="span" variant="bodyMd" fontWeight="semibold">
              {label}
            </Text>
            {!field.enabled ? (
              <Badge>{t("designer.field_hidden", "Hidden")}</Badge>
            ) : field.required === null || field.required === undefined ? (
              <Badge tone="info">{t("designer.field_by_country", "By country")}</Badge>
            ) : field.required ? (
              <Badge tone="attention">{t("designer.field_required", "Required")}</Badge>
            ) : (
              <Badge>{t("designer.field_optional", "Optional")}</Badge>
            )}
            {custom && <Badge tone="info">{t("designer.field_custom_badge", "Custom")}</Badge>}
          </InlineStack>
          <Text as="span" variant="bodySm" tone="subdued">
            {fieldTypeName(field.type)}
            {field.width === "half" ? ` · ${t("designer.width_half", "Half width")}` : ""}
          </Text>
        </BlockStack>
        <InlineStack gap="200" blockAlign="center" wrap={false}>
          <Checkbox
            label={t("designer.field_show_short", "Show")}
            checked={!!field.enabled}
            disabled={locked}
            onChange={(value) => patchField(field.key, { enabled: value })}
          />
          <Button icon={EditMinor} onClick={() => setEditing(field)} accessibilityLabel={t("common.edit", "Edit")} />
          {custom && (
            <Button
              icon={DeleteMinor}
              tone="critical"
              onClick={() => removeCustom(field.key)}
              accessibilityLabel={t("common.delete", "Delete")}
            />
          )}
        </InlineStack>
      </InlineStack>
    );
  };

  return (
    <BlockStack gap="400">
      {GROUPS.map((group) => {
        const list = fields.filter((field) => field.group === group);
        return (
          <Card key={group}>
            <BlockStack gap="200">
              <Text as="h3" variant="headingSm">
                {group === "contact"
                  ? t("designer.block_contact", "Contact fields")
                  : t("designer.block_address", "Address fields")}
              </Text>
              <SortableList
                items={list}
                getKey={(field) => field.key}
                onReorder={(from, to) => reorder(group, from, to)}
                renderItem={renderField}
              />
            </BlockStack>
          </Card>
        );
      })}

      <Card>
        <BlockStack gap="300">
          <Text as="h3" variant="headingSm">
            {t("designer.custom_fields_title", "Custom fields")}
          </Text>
          <Gate feature={FEATURES.CUSTOM_FIELDS} compact title={t("designer.custom_fields_title", "Custom fields")}>
            <BlockStack gap="200">
              <Text as="p" variant="bodyMd" tone="subdued">
                {t("designer.custom_fields_help", "Ask for anything else you need, such as a delivery time or a size. Answers are saved on the order.")}
              </Text>
              <InlineStack>
                <Button onClick={() => setAdding(true)}>{t("designer.add_custom_field", "Add custom field")}</Button>
              </InlineStack>
            </BlockStack>
          </Gate>
          <Divider />
          <Checkbox
            label={t("designer.phone_first", "Ask for the phone number first")}
            helpText={t("designer.phone_first_help", "Phone, then OTP, then a saved address is filled in. Off by default: the address form comes first.")}
            checked={!!(config.steps && config.steps.phone_first)}
            onChange={(value) => setConfig((current) => ({ ...current, steps: { ...(current.steps || {}), phone_first: value } }))}
          />
          {config.steps && config.steps.phone_first && bootstrap && !bootstrap.otpEnabled && (
            <Banner tone="warning">
              <p>
                {t(
                  "designer.phone_first_needs_otp",
                  "OTP in the form is off, so this option has no effect and the address form opens first. To use it, turn on \"Ask buyers to verify their phone number with a code\" in COD Form setup.",
                )}
              </p>
            </Banner>
          )}
          <Text as="p" variant="bodySm" tone="subdued">
            {oneNameField
              ? t("designer.one_name_note", "Buyers enter their name in one Full name field. Turn on Last name to ask for first and last name separately.")
              : t("designer.two_names_note", "Buyers enter first and last name separately. Hide Last name to ask for one Full name instead.")}
          </Text>
          <Text as="p" variant="bodySm" tone="subdued">
            {t("designer.country_field_note", "Phone and country are always part of the form. The country field is shown only when more than one country is enabled in Setup. City, state and postal code follow each country's address format.")}
          </Text>
        </BlockStack>
      </Card>

      <FieldEditor
        open={!!editing}
        field={editing}
        texts={config.texts}
        defaultsTexts={defaultsTexts}
        locale={locale}
        onClose={() => setEditing(null)}
        onSave={saveField}
      />
      <CustomFieldModal
        open={adding}
        existingKeys={fields.map((field) => field.key)}
        onClose={() => setAdding(false)}
        onCreate={addCustom}
      />
    </BlockStack>
  );
};

export default FieldsTab;

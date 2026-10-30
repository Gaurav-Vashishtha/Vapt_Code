import React, { useEffect, useState } from "react";
import { Modal, BlockStack, Checkbox, InlineGrid, Select, TextField } from "@shopify/polaris";
import { CUSTOM_FIELD_TYPES } from "../defaults";
import { LIMITS } from "../constants";
import { randomKey, splitEntries } from "../utils";
import { t } from "../i18n";
import { fieldTypeName } from "./fieldLabels";

/** New custom field (FRM-13): text, text area, dropdown, radio, checkbox, date. */
const CustomFieldModal = ({ open, existingKeys, onClose, onCreate }) => {
  const [type, setType] = useState("text");
  const [label, setLabel] = useState("");
  const [group, setGroup] = useState("address");
  const [required, setRequired] = useState(false);
  const [choices, setChoices] = useState("");

  useEffect(() => {
    if (open) {
      setType("text");
      setLabel("");
      setGroup("address");
      setRequired(false);
      setChoices("");
    }
  }, [open]);

  const needsChoices = type === "select" || type === "radio";
  const options = splitEntries(choices).slice(0, 30);
  const valid = label.trim() !== "" && (!needsChoices || options.length > 0);

  const create = () => {
    let key = `cf_${randomKey(8)}`;
    while ((existingKeys || []).includes(key)) key = `cf_${randomKey(8)}`;
    const field = {
      key,
      type,
      group,
      enabled: true,
      required,
      width: "full",
      validation: {},
    };
    if (needsChoices) {
      field.options = options.map((text, index) => ({
        value: text.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 40) || `option_${index + 1}`,
        label: { default: text },
      }));
    }
    onCreate(field, label.trim());
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("designer.add_custom_field", "Add custom field")}
      primaryAction={{ content: t("common.add", "Add"), onAction: create, disabled: !valid }}
      secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
    >
      <Modal.Section>
        <BlockStack gap="400">
          <TextField
            label={t("designer.field_label", "Label")}
            value={label}
            onChange={setLabel}
            maxLength={LIMITS.TEXT_MAX_CHARS}
            autoComplete="off"
          />
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <Select
              label={t("designer.custom_type", "Type")}
              options={CUSTOM_FIELD_TYPES.map((value) => ({ value, label: fieldTypeName(value) }))}
              value={type}
              onChange={setType}
            />
            <Select
              label={t("designer.custom_group", "Section")}
              options={[
                { value: "contact", label: t("designer.block_contact", "Contact fields") },
                { value: "address", label: t("designer.block_address", "Address fields") },
              ]}
              value={group}
              onChange={setGroup}
            />
          </InlineGrid>
          {needsChoices && (
            <TextField
              label={t("designer.custom_choices", "Choices")}
              value={choices}
              onChange={setChoices}
              multiline={4}
              helpText={t("designer.custom_choices_help", "One choice per line.")}
              error={options.length === 0 && choices !== "" ? t("designer.custom_choices_error", "Add at least one choice.") : undefined}
              autoComplete="off"
            />
          )}
          <Checkbox
            label={t("designer.field_required", "Required")}
            checked={required}
            onChange={setRequired}
          />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default CustomFieldModal;

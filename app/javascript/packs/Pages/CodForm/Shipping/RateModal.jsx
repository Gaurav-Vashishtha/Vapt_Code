import React, { useEffect, useState } from "react";
import { Modal, BlockStack, Checkbox, Divider, InlineGrid, TextField } from "@shopify/polaris";
import MoneyField from "../components/MoneyField";
import { SaveErrorBanner } from "../components/Screen";
import { withRateDefaults } from "../defaults";
import { t } from "../i18n";
import ConditionsEditor, { invalidProvinces } from "./ConditionsEditor";

/** Add / edit a shipping rate (SHP-1..3, SHP-6). Free shipping is a rate priced 0. */
const RateModal = ({ open, rate, currency, saving, error, onClose, onSave }) => {
  const [draft, setDraft] = useState(null);

  useEffect(() => {
    if (open) setDraft(withRateDefaults(rate));
  }, [open, rate]);

  if (!draft) return null;
  const set = (key, value) => setDraft((current) => ({ ...current, [key]: value }));
  const free = Number(draft.price_cents) === 0;
  const products = draft.conditions.products || {};
  const productsInvalid =
    products.mode && products.mode !== "any" && (products.product_ids || []).length === 0 && (products.collection_ids || []).length === 0;
  const invalid = draft.name.trim() === "" || invalidProvinces(draft.conditions.provinces).length > 0 || productsInvalid;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={draft.id ? t("shipping.edit_rate", "Edit shipping rate") : t("shipping.add_rate", "Add shipping rate")}
      primaryAction={{
        content: t("common.save", "Save"),
        onAction: () => onSave({ ...draft, name: draft.name.trim(), currency: draft.currency || null }),
        loading: saving,
        disabled: invalid,
      }}
      secondaryActions={[{ content: t("common.cancel", "Cancel"), onAction: onClose }]}
      large
    >
      <Modal.Section>
        <BlockStack gap="400">
          <SaveErrorBanner error={error} />
          <TextField
            label={t("shipping.name", "Name")}
            value={draft.name}
            onChange={(value) => set("name", value)}
            placeholder={t("shipping.name_placeholder", "Standard delivery")}
            helpText={t("shipping.name_help", "Buyers see this name, and it becomes the shipping line of the order.")}
            maxLength={80}
            autoComplete="off"
          />
          <TextField
            label={t("shipping.description", "Description (optional)")}
            value={draft.description || ""}
            onChange={(value) => set("description", value)}
            placeholder={t("shipping.description_placeholder", "2–4 business days")}
            maxLength={120}
            autoComplete="off"
          />
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <MoneyField
              label={t("shipping.price", "Price")}
              value={draft.price_cents}
              onChange={(cents) => set("price_cents", cents === null ? 0 : cents)}
              currency={draft.currency || currency}
              required
              helpText={free ? t("shipping.free", "Free shipping") : undefined}
            />
            <TextField
              label={t("shipping.currency", "Currency (optional)")}
              value={draft.currency || ""}
              onChange={(value) => set("currency", value.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 3))}
              placeholder={currency}
              helpText={t("shipping.currency_help", "Leave empty for your store currency. A rate applies only to orders in its currency.")}
              autoComplete="off"
            />
          </InlineGrid>
          <Checkbox
            label={t("shipping.active", "Active")}
            checked={draft.active !== false}
            onChange={(value) => set("active", value)}
          />
          <Divider />
          <ConditionsEditor conditions={draft.conditions} onChange={(conditions) => set("conditions", conditions)} />
        </BlockStack>
      </Modal.Section>
    </Modal>
  );
};

export default RateModal;

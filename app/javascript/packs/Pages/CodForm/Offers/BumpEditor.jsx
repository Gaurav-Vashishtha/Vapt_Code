import React from "react";
import { BlockStack, Checkbox, ChoiceList, InlineGrid, Select, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import MoneyField from "../components/MoneyField";
import { toInt } from "../utils";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import VariantField from "./VariantField";

const validate = (offer) => {
  const config = offer.config || {};
  const problems = [];
  if (!config.title || !config.title.default) problems.push(t("offers.error_bump_title", "Give the order bump a title."));
  if (config.kind === "variant" && !config.variant_id) problems.push(t("offers.error_bump_variant", "Select the product for this order bump."));
  if (config.kind === "custom" && !(Number(config.price_cents) >= 0)) problems.push(t("offers.error_bump_price", "Enter a price."));
  if (config.compare_at_cents != null && config.price_cents != null && Number(config.compare_at_cents) <= Number(config.price_cents)) {
    problems.push(t("offers.error_bump_compare", "The compare-at price must be higher than the price."));
  }
  return problems;
};

/** Order bump (OFF-5, OFF-6): a product variant or a custom line the buyer can tick in the form. */
const BumpEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate}>
    {({ config, setConfig, setData }) => (
      <SectionCard
        title={t("offers.bump_title", "Order bump")}
        description={t("offers.bump_help", "Shown inside the form. Up to 3 matching bumps are shown, in priority order.")}
      >
        <BlockStack gap="400">
          <LocalizedTextField
            label={t("offers.offer_title", "Title")}
            value={config.title}
            onChange={(value) => setConfig("title", value)}
            placeholder={t("offers.bump_title_placeholder", "Add express handling")}
            maxLength={80}
          />
          <LocalizedTextField
            label={t("offers.offer_description", "Description (optional)")}
            value={config.description}
            onChange={(value) => setConfig("description", value)}
            maxLength={160}
          />
          <TextField
            label={t("offers.tier_image", "Image URL (optional)")}
            value={config.image_url || ""}
            onChange={(value) => setConfig("image_url", value.trim())}
            error={config.image_url && !/^https:\/\//i.test(config.image_url) ? t("designer.https_required", "Use a link that starts with https://") : undefined}
            autoComplete="off"
          />
          <ChoiceList
            title={t("offers.bump_kind", "What is added to the order")}
            choices={[
              {
                label: t("offers.bump_kind_custom", "A custom line (no product needed)"),
                value: "custom",
                helpText: t("offers.bump_kind_custom_help", "For services such as gift wrap or express handling."),
              },
              {
                label: t("offers.bump_kind_variant", "A product from my store"),
                value: "variant",
                helpText: t("offers.bump_kind_variant_help", "Uses the product's inventory and SKU."),
              },
            ]}
            selected={[config.kind || "custom"]}
            onChange={(value) =>
              setData((current) => ({
                ...current,
                config: { ...current.config, kind: value[0], variant_id: value[0] === "variant" ? current.config.variant_id : null },
              }))
            }
          />
          {config.kind === "variant" && (
            <VariantField
              label={t("offers.bump_variant", "Product")}
              value={config.variant_id}
              onChange={(value) => setConfig("variant_id", value)}
            />
          )}
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <MoneyField
              label={config.kind === "variant" ? t("offers.bump_price_override", "Special price (optional)") : t("offers.bump_price", "Price")}
              value={config.price_cents}
              onChange={(cents) => setConfig("price_cents", config.kind === "variant" ? cents : cents === null ? 0 : cents)}
              required={config.kind !== "variant"}
              helpText={config.kind === "variant" ? t("offers.bump_price_override_help", "Leave empty to use the product's own price.") : undefined}
            />
            <MoneyField
              label={t("offers.bump_compare_at", "Compare-at price (optional)")}
              value={config.compare_at_cents}
              onChange={(cents) => setConfig("compare_at_cents", cents)}
            />
          </InlineGrid>
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="200">
            <Checkbox
              label={t("offers.checked_by_default", "Ticked by default")}
              checked={!!config.checked_by_default}
              onChange={(value) => setConfig("checked_by_default", value)}
            />
            <Checkbox
              label={t("offers.quantity_picker", "Let the buyer choose a quantity")}
              checked={!!config.quantity_picker}
              onChange={(value) => setConfig("quantity_picker", value)}
            />
            <Checkbox
              label={t("offers.requires_shipping", "Requires shipping")}
              checked={!!config.requires_shipping}
              onChange={(value) => setConfig("requires_shipping", value)}
            />
            <Checkbox
              label={t("offers.taxable", "Charge tax")}
              checked={config.taxable !== false}
              onChange={(value) => setConfig("taxable", value)}
            />
          </InlineGrid>
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            {config.quantity_picker && (
              <TextField
                label={t("offers.max_quantity", "Maximum quantity")}
                type="number"
                min={1}
                max={99}
                value={String(config.max_quantity == null ? 1 : config.max_quantity)}
                onChange={(value) => setConfig("max_quantity", Math.min(99, Math.max(1, toInt(value, 1))))}
                autoComplete="off"
              />
            )}
            <Select
              label={t("offers.position", "Position in the form")}
              options={[
                { value: "after_summary", label: t("offers.position_after_summary", "After the order summary") },
                { value: "before_shipping", label: t("offers.position_before_shipping", "Before shipping options") },
                { value: "before_totals", label: t("offers.position_before_totals", "Before the totals") },
              ]}
              value={config.position || "before_totals"}
              onChange={(value) => setConfig("position", value)}
            />
          </InlineGrid>
        </BlockStack>
      </SectionCard>
    )}
  </OfferEditorShell>
);

export default BumpEditor;

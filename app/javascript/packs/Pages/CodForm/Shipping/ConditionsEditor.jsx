import React, { useState } from "react";
import { BlockStack, InlineGrid, Select, Text, TextField } from "@shopify/polaris";
import CountryMultiSelect from "../components/CountryMultiSelect";
import MoneyField from "../components/MoneyField";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { splitEntries, toInt } from "../utils";
import { t } from "../i18n";

const PROVINCE_PATTERN = /^[A-Z]{2}-[A-Z0-9]{1,6}$/;

export const invalidProvinces = (provinces) =>
  (provinces || []).filter((entry) => !PROVINCE_PATTERN.test(entry));

/**
 * Rate conditions (SHP-2, SHP-6). All conditions are AND-ed; an empty
 * condition is ignored. Provinces are "<country>-<province code>" strings.
 */
const ConditionsEditor = ({ conditions, onChange }) => {
  const value = conditions || {};
  const products = value.products || { mode: "any", product_ids: [], collection_ids: [] };
  const set = (key, next) => onChange({ ...value, [key]: next });
  const bad = invalidProvinces(value.provinces);
  // Typed text is kept as typed; the parsed list is what is stored.
  const [provinceText, setProvinceText] = useState((value.provinces || []).join(", "));
  const rangeError = (min, max) =>
    min != null && max != null && Number(min) > Number(max)
      ? t("shipping.range_invalid", "The maximum must be higher than the minimum.")
      : undefined;

  return (
    <BlockStack gap="400">
      <Text as="h3" variant="headingSm">
        {t("shipping.conditions", "Conditions")}
      </Text>
      <Text as="p" variant="bodySm" tone="subdued">
        {t("shipping.conditions_help", "The rate is offered only when every condition you fill in is met. Leave a condition empty to ignore it.")}
      </Text>
      <CountryMultiSelect
        label={t("shipping.cond_country", "Countries")}
        value={value.countries}
        onChange={(codes) => set("countries", codes)}
        emptyText={t("shipping.cond_country_all", "All countries")}
      />
      <TextField
        label={t("shipping.cond_provinces", "States / provinces")}
        value={provinceText}
        onChange={(text) => {
          setProvinceText(text.toUpperCase());
          set("provinces", splitEntries(text.toUpperCase()));
        }}
        placeholder="HU-BU, HU-PE"
        helpText={t("shipping.cond_provinces_help", "Country code, a dash, then the province code, for example HU-BU. Separate entries with commas.")}
        error={bad.length ? t("shipping.cond_provinces_error", "Check these entries: %{entries}", { entries: bad.slice(0, 5).join(", ") }) : undefined}
        autoComplete="off"
      />
      <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
        <MoneyField
          label={t("shipping.cond_total_min", "Minimum order subtotal")}
          value={value.subtotal_min_cents}
          onChange={(cents) => set("subtotal_min_cents", cents)}
        />
        <MoneyField
          label={t("shipping.cond_total_max", "Maximum order subtotal")}
          value={value.subtotal_max_cents}
          onChange={(cents) => set("subtotal_max_cents", cents)}
          error={rangeError(value.subtotal_min_cents, value.subtotal_max_cents)}
        />
        <TextField
          label={t("shipping.cond_weight_min", "Minimum weight (grams)")}
          type="number"
          min={0}
          value={value.weight_min_grams == null ? "" : String(value.weight_min_grams)}
          onChange={(text) => set("weight_min_grams", toInt(text))}
          autoComplete="off"
        />
        <TextField
          label={t("shipping.cond_weight_max", "Maximum weight (grams)")}
          type="number"
          min={0}
          value={value.weight_max_grams == null ? "" : String(value.weight_max_grams)}
          onChange={(text) => set("weight_max_grams", toInt(text))}
          error={rangeError(value.weight_min_grams, value.weight_max_grams)}
          autoComplete="off"
        />
        <TextField
          label={t("shipping.cond_quantity_min", "Minimum quantity")}
          type="number"
          min={0}
          value={value.quantity_min == null ? "" : String(value.quantity_min)}
          onChange={(text) => set("quantity_min", toInt(text))}
          autoComplete="off"
        />
        <TextField
          label={t("shipping.cond_quantity_max", "Maximum quantity")}
          type="number"
          min={0}
          value={value.quantity_max == null ? "" : String(value.quantity_max)}
          onChange={(text) => set("quantity_max", toInt(text))}
          error={rangeError(value.quantity_min, value.quantity_max)}
          autoComplete="off"
        />
      </InlineGrid>
      <Select
        label={t("shipping.cond_products", "Products")}
        options={[
          { value: "any", label: t("shipping.products_any", "Any products") },
          { value: "only", label: t("shipping.products_only", "Only when every item is one of these") },
          { value: "exclude", label: t("shipping.products_exclude", "Not when the cart has one of these") },
        ]}
        value={products.mode || "any"}
        onChange={(mode) => set("products", { ...products, mode })}
      />
      {products.mode && products.mode !== "any" && (
        <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
          <ResourceTargetPicker
            type="product"
            label={t("common.products", "Products")}
            ids={products.product_ids}
            onChange={(ids) => set("products", { ...products, product_ids: ids })}
          />
          <ResourceTargetPicker
            type="collection"
            label={t("common.collections", "Collections")}
            ids={products.collection_ids}
            onChange={(ids) => set("products", { ...products, collection_ids: ids })}
          />
        </InlineGrid>
      )}
    </BlockStack>
  );
};

export default ConditionsEditor;

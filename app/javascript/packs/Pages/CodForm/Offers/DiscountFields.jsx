import React from "react";
import { InlineGrid, Select, TextField } from "@shopify/polaris";
import MoneyField from "../components/MoneyField";
import { toNumber } from "../utils";
import { t } from "../i18n";
import { discountTypeLabel } from "./offerMeta";

/**
 * Discount type + value. Percentages are 0–100; `fixed_amount` and
 * `unit_price` are integer cents (0.1).
 */
const DiscountFields = ({ types, type, value, onTypeChange, onValueChange, typeLabel, valueLabel, stacked }) => {
  const valueField =
    type === "none" ? null : type === "percentage" ? (
      <TextField
        label={valueLabel || t("offers.tier_value", "Discount")}
        type="number"
        min={0}
        max={100}
        suffix="%"
        value={value == null ? "" : String(value)}
        onChange={(text) => onValueChange(Math.min(100, Math.max(0, toNumber(text, 0))))}
        autoComplete="off"
      />
    ) : (
      <MoneyField
        label={
          valueLabel ||
          (type === "unit_price" ? t("offers.tier_unit_price", "Price per unit") : t("offers.tier_amount_off", "Amount off"))
        }
        value={value}
        onChange={(cents) => onValueChange(cents === null ? 0 : cents)}
        required
      />
    );
  const typeField = (
    <Select
      label={typeLabel || t("offers.tier_discount_type", "Discount type")}
      options={types.map((item) => ({ value: item, label: discountTypeLabel(item) }))}
      value={type}
      // Units differ between types (percent vs cents): the caller resets the value with the type.
      onChange={(next) => {
        if (next !== type) onTypeChange(next);
      }}
    />
  );
  if (stacked) {
    return (
      <>
        {typeField}
        {valueField}
      </>
    );
  }
  return (
    <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
      {typeField}
      {valueField}
    </InlineGrid>
  );
};

export default DiscountFields;

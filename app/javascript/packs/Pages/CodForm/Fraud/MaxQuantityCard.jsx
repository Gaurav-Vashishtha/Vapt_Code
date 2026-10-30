import React from "react";
import { BlockStack, Checkbox, InlineGrid, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { toInt } from "../utils";
import { t } from "../i18n";

/** Maximum quantity per order (FRD-3) and bot protection without CAPTCHA (FRD-4). */
const MaxQuantityCard = ({ fraud, onChange }) => (
  <SectionCard
    title={t("fraud.quantity_title", "Quantity and bot protection")}
    description={t("fraud.quantity_help", "Cap how much one order can contain, and filter automated submissions.")}
  >
    <BlockStack gap="400">
      <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
        <TextField
          label={t("fraud.max_quantity", "Maximum total quantity per order")}
          type="number"
          min={1}
          value={fraud.max_quantity_per_order == null ? "" : String(fraud.max_quantity_per_order)}
          onChange={(value) => {
            const number = toInt(value);
            onChange(["fraud", "max_quantity_per_order"], number === null ? null : Math.max(1, number));
          }}
          placeholder={t("fraud.max_quantity_placeholder", "No limit")}
          autoComplete="off"
        />
        <TextField
          label={t("fraud.min_submit_seconds", "Minimum seconds before submit")}
          type="number"
          min={0}
          max={30}
          value={String(fraud.min_submit_seconds == null ? "" : fraud.min_submit_seconds)}
          onChange={(value) => onChange(["fraud", "min_submit_seconds"], Math.min(30, Math.max(0, toInt(value, 0))))}
          helpText={t("fraud.min_submit_help", "A form sent faster than this is treated as a bot.")}
          autoComplete="off"
        />
      </InlineGrid>
      {fraud.max_quantity_per_order != null && (
        <TextField
          label={t("fraud.max_quantity_message", "Message when the quantity is too high")}
          value={fraud.max_quantity_message || ""}
          onChange={(value) => onChange(["fraud", "max_quantity_message"], value)}
          helpText={t("fraud.blocked_message_help", "Leave empty to use the default text of the form.")}
          maxLength={300}
          autoComplete="off"
        />
      )}
      <Checkbox
        label={t("fraud.honeypot", "Use a hidden field that only bots fill in")}
        checked={fraud.honeypot !== false}
        onChange={(value) => onChange(["fraud", "honeypot"], value)}
      />
    </BlockStack>
  </SectionCard>
);

export default MaxQuantityCard;

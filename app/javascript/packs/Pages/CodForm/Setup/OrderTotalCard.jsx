import React from "react";
import { BlockStack, InlineGrid, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import MoneyField from "../components/MoneyField";
import { t } from "../i18n";

/** Order total limits (VIS-4): minimum, maximum, optional message. */
const OrderTotalCard = ({ general, onChange }) => {
  const total = general.order_total || {};
  const invalid =
    total.min_cents != null && total.max_cents != null && Number(total.min_cents) > Number(total.max_cents);
  return (
    <SectionCard
      title={t("setup.order_total_title", "Order total limits")}
      description={t("setup.order_total_help", "Offer the COD Form only when the order total is in this range. Leave a field empty for no limit.")}
    >
      <BlockStack gap="400">
        <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
          <MoneyField
            label={t("setup.order_total_min", "Minimum order total")}
            value={total.min_cents}
            onChange={(value) => onChange(["order_total", "min_cents"], value)}
          />
          <MoneyField
            label={t("setup.order_total_max", "Maximum order total")}
            value={total.max_cents}
            onChange={(value) => onChange(["order_total", "max_cents"], value)}
            error={invalid ? t("setup.order_total_invalid", "The maximum must be higher than the minimum.") : undefined}
          />
        </InlineGrid>
        <TextField
          label={t("setup.order_total_message", "Message when the total is out of range (optional)")}
          value={total.message || ""}
          onChange={(value) => onChange(["order_total", "message"], value)}
          autoComplete="off"
          maxLength={200}
          showCharacterCount
        />
      </BlockStack>
    </SectionCard>
  );
};

export default OrderTotalCard;

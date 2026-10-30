import React from "react";
import { BlockStack, InlineGrid, Text, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import { toInt } from "../utils";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import VariantField from "./VariantField";
import DiscountFields from "./DiscountFields";

const validate = (offer) => {
  const config = offer.config || {};
  const problems = [];
  if (!config.variant_id) problems.push(t("offers.error_upsell_variant", "Select the product to offer."));
  if (!config.title || !config.title.default) problems.push(t("offers.error_offer_title", "Enter a title."));
  if (config.discount_type === "percentage" && !(Number(config.value) >= 0 && Number(config.value) <= 100)) {
    problems.push(t("offers.error_tier_percent", "A percentage must be between 0 and 100."));
  }
  return problems;
};

/** One-click upsell after the order (OFF-10). Accepting adds the line to the order just created. */
const UpsellEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate}>
    {({ config, setConfig, setData }) => (
      <SectionCard
        title={t("offers.upsell_title", "Upsell")}
        description={t("offers.upsell_help", "Shown once, right after the order is placed. One upsell per order: the matching offer with the best priority.")}
      >
        <BlockStack gap="400">
          <VariantField
            label={t("offers.upsell_variant", "Product to offer")}
            value={config.variant_id}
            onChange={(value) => setConfig("variant_id", value)}
          />
          <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
            <TextField
              label={t("offers.tier_quantity", "Quantity")}
              type="number"
              min={1}
              max={20}
              value={String(config.quantity == null ? 1 : config.quantity)}
              onChange={(value) => setConfig("quantity", Math.min(20, Math.max(1, toInt(value, 1))))}
              autoComplete="off"
            />
            <DiscountFields
              stacked
              types={["percentage", "fixed_amount"]}
              type={config.discount_type || "percentage"}
              value={config.value}
              onTypeChange={(type) => setData((current) => ({ ...current, config: { ...current.config, discount_type: type, value: 0 } }))}
              onValueChange={(value) => setConfig("value", value)}
            />
          </InlineGrid>
          <LocalizedTextField label={t("offers.offer_title", "Title")} value={config.title} onChange={(value) => setConfig("title", value)} maxLength={80} />
          <LocalizedTextField label={t("offers.offer_body", "Text (optional)")} value={config.body} onChange={(value) => setConfig("body", value)} maxLength={200} multiline={2} />
          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
            <LocalizedTextField label={t("offers.accept_label", "Accept button")} value={config.accept_label} onChange={(value) => setConfig("accept_label", value)} maxLength={40} />
            <LocalizedTextField label={t("offers.decline_label", "Decline button")} value={config.decline_label} onChange={(value) => setConfig("decline_label", value)} maxLength={40} />
          </InlineGrid>
          <TextField
            label={t("offers.timer", "On-screen timer (seconds, 0 for none)")}
            type="number"
            min={0}
            max={600}
            value={String(config.timer_seconds == null ? 0 : config.timer_seconds)}
            onChange={(value) => setConfig("timer_seconds", Math.min(600, Math.max(0, toInt(value, 0))))}
            autoComplete="off"
          />
          <Text as="p" variant="bodySm" tone="subdued">
            {t("offers.window", "The buyer can accept for a few minutes after ordering; set the window in Setup, under More options. The COD fee is not recalculated and no extra message is sent.")}
          </Text>
        </BlockStack>
      </SectionCard>
    )}
  </OfferEditorShell>
);

export default UpsellEditor;

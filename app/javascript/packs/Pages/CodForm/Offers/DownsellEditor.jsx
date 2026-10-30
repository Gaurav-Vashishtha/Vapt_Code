import React from "react";
import { BlockStack, InlineGrid, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import { toInt } from "../utils";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import DiscountFields from "./DiscountFields";

const validate = (offer) => {
  const config = offer.config || {};
  const problems = [];
  if (!config.title || !config.title.default) problems.push(t("offers.error_offer_title", "Enter a title."));
  if (!(Number(config.value) > 0)) problems.push(t("offers.error_downsell_value", "Enter a discount above 0."));
  if (config.discount_type === "percentage" && Number(config.value) > 100) {
    problems.push(t("offers.error_tier_percent", "A percentage must be between 0 and 100."));
  }
  return problems;
};

/** Downsell on close (OFF-7): shown once per session when the buyer closes the form. */
const DownsellEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate}>
    {({ config, setConfig, setData }) => (
      <SectionCard
        title={t("offers.downsell_title", "Downsell")}
        description={t("offers.downsell_help", "When the buyer tries to close the form, offer a discount to complete the order.")}
      >
        <BlockStack gap="400">
          <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
            <TextField
              label={t("offers.trigger_after_closes", "Show after this many close attempts")}
              type="number"
              min={1}
              max={5}
              value={String(config.trigger_after_closes == null ? 1 : config.trigger_after_closes)}
              onChange={(value) => setConfig("trigger_after_closes", Math.min(5, Math.max(1, toInt(value, 1))))}
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
        </BlockStack>
      </SectionCard>
    )}
  </OfferEditorShell>
);

export default DownsellEditor;

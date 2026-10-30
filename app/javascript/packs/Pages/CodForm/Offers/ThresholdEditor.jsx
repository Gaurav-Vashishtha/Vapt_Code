import React from "react";
import { BlockStack, ChoiceList, Text } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import MoneyField from "../components/MoneyField";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import VariantField from "./VariantField";

const validate = (offer) => {
  const config = offer.config || {};
  const problems = [];
  if (!(Number(config.threshold_cents) > 0)) problems.push(t("offers.error_threshold_amount", "Enter the order amount that unlocks the reward."));
  if (config.kind === "free_gift" && !config.gift_variant_id) problems.push(t("offers.error_threshold_gift", "Select the gift product."));
  return problems;
};

/** Free shipping / free gift threshold with a progress bar (OFF-11). */
const ThresholdEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate}>
    {({ config, setConfig, setData }) => (
      <SectionCard
        title={t("offers.threshold_title", "Threshold")}
        description={t("offers.threshold_help", "Reward buyers whose order reaches an amount. Add the progress bar block in Form designer to show it.")}
      >
        <BlockStack gap="400">
          <ChoiceList
            title={t("offers.threshold_kind", "Reward")}
            choices={[
              { label: t("offers.threshold_free_shipping", "Free shipping"), value: "free_shipping" },
              { label: t("offers.threshold_free_gift", "A free gift"), value: "free_gift" },
            ]}
            selected={[config.kind || "free_shipping"]}
            onChange={(value) =>
              setData((current) => ({
                ...current,
                config: { ...current.config, kind: value[0], gift_variant_id: value[0] === "free_gift" ? current.config.gift_variant_id : null },
              }))
            }
          />
          <MoneyField
            label={t("offers.threshold_amount", "Order amount to reach")}
            value={config.threshold_cents}
            onChange={(cents) => setConfig("threshold_cents", cents === null ? 0 : cents)}
            required
          />
          {config.kind === "free_gift" && (
            <VariantField
              label={t("offers.threshold_gift", "Gift product")}
              value={config.gift_variant_id}
              onChange={(value) => setConfig("gift_variant_id", value)}
              helpText={t("offers.threshold_gift_help", "One unit is added to the order at no charge.")}
            />
          )}
          <LocalizedTextField
            label={t("offers.threshold_text_progress", "Text while below the amount")}
            value={config.text_progress}
            onChange={(value) => setConfig("text_progress", value)}
            maxLength={120}
          />
          <LocalizedTextField
            label={t("offers.threshold_text_reached", "Text once reached")}
            value={config.text_reached}
            onChange={(value) => setConfig("text_reached", value)}
            maxLength={120}
          />
          <Text as="p" variant="bodySm" tone="subdued">
            {t("offers.threshold_variable", "Use {remaining} for the amount still missing.")}
          </Text>
        </BlockStack>
      </SectionCard>
    )}
  </OfferEditorShell>
);

export default ThresholdEditor;

import React from "react";
import { BlockStack, Button, Card, Checkbox, Divider, InlineGrid, InlineStack, RadioButton, Select, Text, TextField } from "@shopify/polaris";
import { DeleteMinor } from "@shopify/polaris-icons";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import { LIMITS } from "../constants";
import { newQuantityTier } from "../defaults";
import { toInt } from "../utils";
import { t } from "../i18n";
import OfferEditorShell from "./OfferEditorShell";
import DiscountFields from "./DiscountFields";

const validate = (offer) => {
  const problems = [];
  const tiers = (offer.config && offer.config.tiers) || [];
  if (tiers.length < 1) problems.push(t("offers.error_tiers_min", "Add at least one tier."));
  if (tiers.length > LIMITS.TIERS_PER_OFFER) problems.push(t("offers.error_tiers_max", "An offer can have up to 5 tiers."));
  const quantities = tiers.map((tier) => Number(tier.quantity));
  if (quantities.some((quantity) => !(quantity >= 1))) problems.push(t("offers.error_tier_quantity", "Each tier needs a quantity of 1 or more."));
  if (new Set(quantities).size !== quantities.length) problems.push(t("offers.error_tier_duplicate", "Two tiers have the same quantity."));
  if (tiers.some((tier) => tier.discount_type === "percentage" && !(Number(tier.value) >= 0 && Number(tier.value) <= 100))) {
    problems.push(t("offers.error_tier_percent", "A percentage must be between 0 and 100."));
  }
  if (tiers.some((tier) => tier.discount_type === "unit_price" && !(Number(tier.value) > 0))) {
    problems.push(t("offers.error_tier_unit_price", "A fixed unit price must be above 0."));
  }
  if (tiers.filter((tier) => tier.preselected).length > 1) problems.push(t("offers.error_tier_preselected", "Only one tier can be preselected."));
  return problems;
};

/** Quantity offer: tiers, layout, product-page widget (OFF-1..4). */
const QuantityOfferEditor = ({ segment, id }) => (
  <OfferEditorShell segment={segment} id={id} validate={validate}>
    {({ config, setConfig }) => {
      const tiers = config.tiers || [];
      const writeTiers = (next) => setConfig("tiers", next);
      const patchTier = (index, patch) => writeTiers(tiers.map((tier, i) => (i === index ? { ...tier, ...patch } : tier)));
      const sortTiers = () => writeTiers(tiers.slice().sort((a, b) => Number(a.quantity) - Number(b.quantity)));
      const addTier = () => {
        const highest = tiers.reduce((max, tier) => Math.max(max, Number(tier.quantity) || 0), 0);
        writeTiers([...tiers, newQuantityTier(highest + 1)]);
      };

      return (
        <>
          <SectionCard
            title={t("offers.tiers_title", "Tiers")}
            description={t("offers.tiers_help", "Up to 5 tiers. Each tier is a quantity with its own price. One tier can be preselected.")}
          >
            <BlockStack gap="400">
              {tiers.map((tier, index) => (
                <Card key={index} background="bg-surface-secondary">
                  <BlockStack gap="300">
                    <InlineStack align="space-between" blockAlign="center">
                      <Text as="h4" variant="headingSm">
                        {t("offers.tier_heading", "Tier %{number}", { number: index + 1 })}
                      </Text>
                      <Button
                        icon={DeleteMinor}
                        tone="critical"
                        accessibilityLabel={t("common.delete", "Delete")}
                        disabled={tiers.length <= 1}
                        onClick={() => writeTiers(tiers.filter((_, i) => i !== index))}
                      />
                    </InlineStack>
                    <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
                      <TextField
                        label={t("offers.tier_quantity", "Quantity")}
                        type="number"
                        min={1}
                        value={tier.quantity == null ? "" : String(tier.quantity)}
                        onChange={(value) => patchTier(index, { quantity: toInt(value, 1) })}
                        onBlur={sortTiers}
                        autoComplete="off"
                      />
                      <DiscountFields
                        stacked
                        types={["none", "percentage", "fixed_amount", "unit_price"]}
                        type={tier.discount_type || "none"}
                        value={tier.value}
                        onTypeChange={(type) => patchTier(index, { discount_type: type, value: 0 })}
                        onValueChange={(value) => patchTier(index, { value })}
                      />
                    </InlineGrid>
                    <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                      <LocalizedTextField
                        label={t("offers.tier_label", "Label")}
                        value={tier.label}
                        onChange={(value) => patchTier(index, { label: value })}
                        placeholder={t("offers.tier_label_placeholder", "2 packs")}
                        maxLength={60}
                      />
                      <LocalizedTextField
                        label={t("offers.tier_badge", "Badge (optional)")}
                        value={tier.badge}
                        onChange={(value) => patchTier(index, { badge: value })}
                        placeholder={t("offers.tier_badge_placeholder", "Most popular")}
                        maxLength={30}
                      />
                    </InlineGrid>
                    <TextField
                      label={t("offers.tier_image", "Image URL (optional)")}
                      value={tier.image_url || ""}
                      onChange={(value) => patchTier(index, { image_url: value.trim() })}
                      error={tier.image_url && !/^https:\/\//i.test(tier.image_url) ? t("designer.https_required", "Use a link that starts with https://") : undefined}
                      autoComplete="off"
                    />
                    <RadioButton
                      label={t("offers.tier_preselected", "Preselected")}
                      checked={!!tier.preselected}
                      name="codkf-tier-preselected"
                      onChange={() => writeTiers(tiers.map((item, i) => ({ ...item, preselected: i === index })))}
                    />
                  </BlockStack>
                </Card>
              ))}
              <InlineStack gap="200">
                <Button onClick={addTier} disabled={tiers.length >= LIMITS.TIERS_PER_OFFER}>
                  {t("offers.add_tier", "Add tier")}
                </Button>
                <Button variant="plain" onClick={() => writeTiers(tiers.map((tier) => ({ ...tier, preselected: false })))}>
                  {t("offers.clear_preselected", "No preselected tier")}
                </Button>
              </InlineStack>
              <Divider />
              <Checkbox
                label={t("offers.apply_to_higher", "Apply a tier to higher quantities too")}
                helpText={t("offers.apply_to_higher_help", "On: a buyer who orders 4 gets the 3-pack price. Off: a tier applies only to its exact quantity.")}
                checked={config.apply_to_higher_quantities !== false}
                onChange={(value) => setConfig("apply_to_higher_quantities", value)}
              />
            </BlockStack>
          </SectionCard>

          <SectionCard
            title={t("offers.widget_title", "How it looks")}
            description={t("offers.widget_help", "The same tiers show in the form and, if you want, on the product page above the buy buttons.")}
          >
            <BlockStack gap="400">
              <LocalizedTextField
                label={t("offers.offer_title", "Title")}
                value={config.title}
                onChange={(value) => setConfig("title", value)}
                maxLength={80}
              />
              <Select
                label={t("offers.layout", "Layout")}
                options={[
                  { value: "cards", label: t("offers.layout_cards", "Cards") },
                  { value: "list", label: t("offers.layout_list", "List") },
                  { value: "compact", label: t("offers.layout_compact", "Compact") },
                ]}
                value={config.layout || "cards"}
                onChange={(value) => setConfig("layout", value)}
              />
              <Checkbox
                label={t("offers.show_widget", "Show the tiers on the product page")}
                helpText={t("offers.show_widget_help", "The tier a buyer picks there is carried into the form, and the same price applies at Shopify checkout.")}
                checked={config.show_widget_on_product_page !== false}
                onChange={(value) => setConfig("show_widget_on_product_page", value)}
              />
            </BlockStack>
          </SectionCard>
        </>
      );
    }}
  </OfferEditorShell>
);

export default QuantityOfferEditor;

import React from "react";
import { BlockStack, ChoiceList, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { t } from "../i18n";

/** Placement of the COD button on the product page (BTN-2). */
const PlacementCard = ({ button, onChange }) => {
  const placement = button.placement || {};
  const position = placement.position || "below";
  return (
    <SectionCard
      title={t("buttons.placement_title", "Placement on the product page")}
      description={t("buttons.placement_help", "The button is added by the app embed. No theme code is edited.")}
    >
      <BlockStack gap="400">
        <ChoiceList
          title={t("buttons.placement_title", "Placement on the product page")}
          titleHidden
          choices={[
            { label: t("buttons.placement_below", "Below the theme's buy buttons"), value: "below" },
            { label: t("buttons.placement_above", "Above the theme's buy buttons"), value: "above" },
            { label: t("buttons.placement_custom", "Inside a custom element"), value: "custom" },
          ]}
          selected={[position]}
          onChange={(value) => onChange(["button", "placement", "position"], value[0])}
        />
        {position === "custom" && (
          <TextField
            label={t("buttons.selector", "CSS selector")}
            value={placement.selector || ""}
            onChange={(value) => onChange(["button", "placement", "selector"], value)}
            placeholder=".product-form__buttons"
            helpText={t("buttons.selector_help", "The button is appended inside the first element that matches.")}
            error={!placement.selector ? t("buttons.selector_required", "Enter a selector, or choose another placement.") : undefined}
            autoComplete="off"
          />
        )}
      </BlockStack>
    </SectionCard>
  );
};

export default PlacementCard;

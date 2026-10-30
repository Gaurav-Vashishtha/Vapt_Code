import React from "react";
import { BlockStack, Checkbox } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import { t } from "../i18n";

/** Sticky mobile button, shown when the main button is out of view (BTN-4). */
const StickyCard = ({ button, onChange }) => {
  const sticky = button.sticky || {};
  return (
    <SectionCard
      title={t("buttons.sticky_title", "Sticky button on mobile")}
      description={t("buttons.sticky_help", "Stays at the bottom of the screen when the main button scrolls out of view.")}
    >
      <BlockStack gap="400">
        <Checkbox
          label={t("buttons.sticky_enabled", "Show the sticky button")}
          checked={!!sticky.enabled}
          onChange={(value) => onChange(["button", "sticky", "enabled"], value)}
        />
        {sticky.enabled && (
          <LocalizedTextField
            label={t("buttons.sticky_label", "Sticky button label")}
            value={sticky.labels}
            onChange={(value) => onChange(["button", "sticky", "labels"], value)}
            maxLength={60}
          />
        )}
      </BlockStack>
    </SectionCard>
  );
};

export default StickyCard;

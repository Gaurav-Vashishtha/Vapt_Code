import React from "react";
import { BlockStack, Checkbox, Select, TextField, Button, InlineStack } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { navigateTo } from "../../../../utils/navigate";
import { PATHS } from "../constants";
import { t } from "../i18n";

/** Product-page quantity offer widget placement (OFF-3). The tiers themselves live in Offers. */
const QuantityWidgetCard = ({ widget, onChange }) => {
  const value = widget || {};
  return (
    <SectionCard
      title={t("buttons.widget_title", "Quantity offer widget")}
      description={t("buttons.widget_help", "Shows your quantity offer tiers on the product page. The tier a buyer picks carries into the form.")}
    >
      <BlockStack gap="400">
        <Checkbox
          label={t("buttons.widget_enabled", "Show the widget on products that have a quantity offer")}
          checked={value.enabled !== false}
          onChange={(checked) => onChange(["quantity_widget", "enabled"], checked)}
        />
        {value.enabled !== false && (
          <BlockStack gap="300">
            <Select
              label={t("buttons.widget_position", "Position")}
              options={[
                { label: t("buttons.widget_above_buttons", "Above the buy buttons"), value: "above_buttons" },
                { label: t("buttons.widget_below_buttons", "Below the buy buttons"), value: "below_buttons" },
                { label: t("buttons.widget_custom", "Inside a custom element"), value: "custom" },
              ]}
              value={value.position || "above_buttons"}
              onChange={(next) => onChange(["quantity_widget", "position"], next)}
            />
            {value.position === "custom" && (
              <TextField
                label={t("buttons.selector", "CSS selector")}
                value={value.selector || ""}
                onChange={(next) => onChange(["quantity_widget", "selector"], next)}
                autoComplete="off"
              />
            )}
          </BlockStack>
        )}
        <InlineStack>
          <Button onClick={() => navigateTo(`${PATHS.offers}/quantity`)}>
            {t("buttons.widget_manage", "Manage quantity offers")}
          </Button>
        </InlineStack>
      </BlockStack>
    </SectionCard>
  );
};

export default QuantityWidgetCard;

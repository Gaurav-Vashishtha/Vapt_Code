import React from "react";
import { BlockStack, Checkbox, TextField } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import { t } from "../i18n";

const Selector = ({ label, value, onChange }) => (
  <TextField
    label={label}
    value={value || ""}
    onChange={onChange}
    helpText={t("buttons.selector_optional_help", "Leave empty to place the button automatically.")}
    autoComplete="off"
  />
);

/** Quick-buy button and custom placement selectors (BTN-5, VIS-1). Rarely needed. */
const CartButtonsCard = ({ button, onChange }) => {
  const quickBuy = button.quick_buy || {};
  return (
    <SectionCard
      title={t("buttons.advanced_title", "Advanced")}
      description={t("buttons.advanced_help", "Only needed when your theme places a button in an unusual spot.")}
    >
      <BlockStack gap="400">
        <Checkbox
          label={t("buttons.quick_buy_title", "Quick-buy button on home and collection pages")}
          checked={!!quickBuy.enabled}
          onChange={(value) => onChange(["button", "quick_buy", "enabled"], value)}
        />
        {quickBuy.enabled && (
          <Selector
            label={t("buttons.quick_buy_selector", "Quick-buy CSS selector (optional)")}
            value={quickBuy.selector}
            onChange={(value) => onChange(["button", "quick_buy", "selector"], value)}
          />
        )}
        <Selector
          label={t("buttons.cart_selector", "Cart page CSS selector (optional)")}
          value={(button.cart || {}).selector}
          onChange={(value) => onChange(["button", "cart", "selector"], value)}
        />
        <Selector
          label={t("buttons.drawer_selector", "Cart drawer CSS selector (optional)")}
          value={(button.drawer || {}).selector}
          onChange={(value) => onChange(["button", "drawer", "selector"], value)}
        />
      </BlockStack>
    </SectionCard>
  );
};

export default CartButtonsCard;

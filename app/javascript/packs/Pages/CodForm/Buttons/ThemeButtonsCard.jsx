import React from "react";
import { BlockStack, Checkbox, Divider, InlineGrid, Text } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import LocalizedTextField from "../components/LocalizedTextField";
import { t } from "../i18n";

/* One button of a page: a Show switch and its label. */
const Row = ({ name, shown, onShow, label, onLabel, labelTitle, placeholder, helpText }) => (
  <InlineGrid columns={{ xs: 1, sm: "1fr 2fr" }} gap="300" alignItems="start">
    <Checkbox label={t("buttons.show_button", "Show %{name}", { name })} checked={shown} onChange={onShow} />
    <LocalizedTextField
      label={labelTitle || t("buttons.rename_button", "Rename %{name}", { name })}
      value={label}
      onChange={onLabel}
      placeholder={placeholder}
      helpText={helpText}
      disabled={!shown}
      maxLength={60}
    />
  </InlineGrid>
);

const Section = ({ title, children }) => (
  <BlockStack gap="300">
    <Text as="h4" variant="headingSm">
      {title}
    </Text>
    {children}
  </BlockStack>
);

/**
 * Which buttons each page shows, and what they say (BTN-5, BTN-8, BTN-9).
 * Product page: Add to cart, Buy now, COD button. Cart page and cart drawer:
 * the theme's Checkout button and the COD button.
 */
const ThemeButtonsCard = ({ button, theme, onChange }) => {
  const hide = theme.hide || {};
  const keep = t("buttons.rename_keep", "Leave empty to keep your theme's own text.");
  const cartSection = (title, surfaceKey, hideKey, renameKey) => {
    const surface = button[surfaceKey] || {};
    return (
      <Section title={title}>
        <Row
          name={t("buttons.name_checkout", "Checkout")}
          shown={!hide[hideKey]}
          onShow={(value) => onChange(["theme", "hide", hideKey], !value)}
          label={theme[renameKey]}
          onLabel={(value) => onChange(["theme", renameKey], value)}
          placeholder={t("buttons.preview_checkout", "Check out")}
          helpText={
            hide[hideKey] && !surface.enabled
              ? t("buttons.hide_checkout_needs_cod", "Checkout is only hidden while the COD button is shown, so buyers can always order.")
              : keep
          }
        />
        <Row
          name={t("buttons.name_cod", "COD button")}
          shown={!!surface.enabled}
          onShow={(value) => onChange(["button", surfaceKey, "enabled"], value)}
          label={surface.labels}
          onLabel={(value) => onChange(["button", surfaceKey, "labels"], value)}
          labelTitle={t("buttons.cod_label", "COD button text")}
          helpText={t("buttons.cart_total_help", "{total} shows the cart total.")}
        />
      </Section>
    );
  };

  return (
    <SectionCard
      title={t("buttons.pages_title", "Buttons on each page")}
      description={t("buttons.pages_help", "Show or hide each button and change its text.")}
    >
      <BlockStack gap="400">
        <Section title={t("buttons.preview_product", "Product page")}>
          <Row
            name={t("buttons.name_add_to_cart", "Add to cart")}
            shown={!hide.add_to_cart}
            onShow={(value) => onChange(["theme", "hide", "add_to_cart"], !value)}
            label={theme.rename_add_to_cart}
            onLabel={(value) => onChange(["theme", "rename_add_to_cart"], value)}
            placeholder={t("buttons.preview_add_to_cart", "Add to cart")}
            helpText={keep}
          />
          <Row
            name={t("buttons.name_buy_now", "Buy now")}
            shown={!hide.buy_now}
            onShow={(value) => onChange(["theme", "hide", "buy_now"], !value)}
            label={theme.rename_buy_now}
            onLabel={(value) => onChange(["theme", "rename_buy_now"], value)}
            placeholder={t("buttons.preview_buy_now", "Buy it now")}
            helpText={keep}
          />
          <Text as="p" variant="bodySm" tone="subdued">
            {t("buttons.cod_always", "The COD button is always shown on the product page. Its text and style are set above.")}
          </Text>
        </Section>
        <Divider />
        {cartSection(t("buttons.cart_page", "Cart page"), "cart", "checkout", "rename_checkout")}
        <Divider />
        {cartSection(t("buttons.cart_drawer", "Cart drawer"), "drawer", "drawer_checkout", "rename_drawer_checkout")}
      </BlockStack>
    </SectionCard>
  );
};

export default ThemeButtonsCard;

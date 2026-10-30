import React from "react";
import { BlockStack, Checkbox, ChoiceList, Divider, InlineGrid, Text } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { t } from "../i18n";

/** Page types (VIS-1), product / collection targeting (VIS-2), out of stock (VIS-5). */
const VisibilityCard = ({ general, onChange }) => {
  const pages = general.pages || {};
  const products = general.products || {};
  const selected = products.scope === "selected";

  return (
    <SectionCard
      title={t("setup.visibility_title", "Where the COD button shows")}
      description={t("setup.visibility_help", "Choose the pages and products that get the COD button.")}
    >
      <BlockStack gap="400">
        <InlineGrid columns={{ xs: 1, sm: 2 }} gap="200">
          <Checkbox
            label={t("setup.pages_product", "Product page")}
            checked={!!pages.product}
            onChange={(value) => onChange(["pages", "product"], value)}
          />
          <Checkbox
            label={t("setup.pages_cart", "Cart page")}
            checked={!!pages.cart}
            onChange={(value) => onChange(["pages", "cart"], value)}
          />
          <Checkbox
            label={t("setup.pages_drawer", "Cart drawer")}
            checked={!!pages.drawer}
            onChange={(value) => onChange(["pages", "drawer"], value)}
          />
          <Checkbox
            label={t("setup.pages_quick_buy", "Quick buy on home and collection pages")}
            checked={!!pages.quick_buy}
            onChange={(value) => onChange(["pages", "quick_buy"], value)}
          />
        </InlineGrid>

        <Divider />

        <ChoiceList
          title={t("setup.products_title", "Products")}
          choices={[
            { label: t("common.all_products", "All products"), value: "all" },
            { label: t("common.selected_products", "Selected products and collections"), value: "selected" },
          ]}
          selected={[selected ? "selected" : "all"]}
          onChange={(value) => onChange(["products", "scope"], value[0])}
        />

        {selected && (
          <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
            <ResourceTargetPicker
              type="product"
              label={t("setup.include_products", "Show on these products")}
              ids={products.include_product_ids}
              onChange={(ids) => onChange(["products", "include_product_ids"], ids)}
            />
            <ResourceTargetPicker
              type="collection"
              label={t("setup.include_collections", "Show on these collections")}
              ids={products.include_collection_ids}
              onChange={(ids) => onChange(["products", "include_collection_ids"], ids)}
            />
          </InlineGrid>
        )}

        <Text as="h4" variant="headingSm">
          {t("setup.exclude_title", "Never show on")}
        </Text>
        <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
          <ResourceTargetPicker
            type="product"
            label={t("setup.exclude_products", "Excluded products")}
            ids={products.exclude_product_ids}
            onChange={(ids) => onChange(["products", "exclude_product_ids"], ids)}
          />
          <ResourceTargetPicker
            type="collection"
            label={t("setup.exclude_collections", "Excluded collections")}
            ids={products.exclude_collection_ids}
            onChange={(ids) => onChange(["products", "exclude_collection_ids"], ids)}
          />
        </InlineGrid>

        <Divider />

        <Checkbox
          label={t("setup.hide_oos", "Hide the COD button for out-of-stock variants")}
          checked={!!general.hide_out_of_stock}
          onChange={(value) => onChange(["hide_out_of_stock"], value)}
        />
        <Text as="p" variant="bodySm" tone="subdued">
          {t("setup.rules_note", "Products that fail a Limit COD rule never get the COD button. Those rules are set once, in Limit COD.")}
        </Text>
      </BlockStack>
    </SectionCard>
  );
};

export default VisibilityCard;

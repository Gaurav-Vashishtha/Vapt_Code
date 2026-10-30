import React from "react";
import { Banner, BlockStack, ChoiceList, InlineGrid } from "@shopify/polaris";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { t } from "../i18n";

/** Offer targeting: all products, or selected products and collections (OFF-2, OFF-6). */
const OfferTargetingCard = ({ targeting, onChange, error, overlapNames }) => {
  const value = targeting || { scope: "all", product_ids: [], collection_ids: [] };
  const selected = value.scope === "selected";
  const empty = selected && (value.product_ids || []).length === 0 && (value.collection_ids || []).length === 0;
  return (
    <SectionCard
      title={t("offers.targeting_title", "Products")}
      description={t("offers.targeting_help", "Choose which products this offer applies to.")}
    >
      <BlockStack gap="400">
        <ChoiceList
          title={t("offers.targeting_title", "Products")}
          titleHidden
          choices={[
            { label: t("common.all_products", "All products"), value: "all" },
            { label: t("common.selected_products", "Selected products and collections"), value: "selected" },
          ]}
          selected={[selected ? "selected" : "all"]}
          onChange={(next) => onChange({ ...value, scope: next[0] })}
        />
        {selected && (
          <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
            <ResourceTargetPicker
              type="product"
              label={t("common.products", "Products")}
              ids={value.product_ids}
              onChange={(ids) => onChange({ ...value, product_ids: ids })}
            />
            <ResourceTargetPicker
              type="collection"
              label={t("common.collections", "Collections")}
              ids={value.collection_ids}
              onChange={(ids) => onChange({ ...value, collection_ids: ids })}
            />
          </InlineGrid>
        )}
        {empty && (
          <Banner tone="warning">
            <p>{t("offers.targeting_empty", "Select at least one product or collection, or choose all products.")}</p>
          </Banner>
        )}
        {(error || (overlapNames && overlapNames.length > 0)) && (
          <Banner tone="critical">
            <p>
              {t("offers.overlap_error", "A product can be in only one active quantity offer. Some of these products are already in another active offer.")}
              {overlapNames && overlapNames.length > 0 ? ` (${overlapNames.slice(0, 3).join(", ")})` : ""}
            </p>
          </Banner>
        )}
      </BlockStack>
    </SectionCard>
  );
};

export default OfferTargetingCard;

import React from "react";
import { BlockStack, InlineGrid, Text, TextField, Card } from "@shopify/polaris";
import ResourceTargetPicker from "../components/ResourceTargetPicker";
import { t } from "../i18n";

/** Name and product / collection targeting of a form (FRM-22). The default form catches everything else. */
const FormTargetingCard = ({ name, targeting, isDefault, onNameChange, onTargetingChange }) => {
  const value = targeting || {};
  return (
    <Card>
      <BlockStack gap="400">
        <TextField
          label={t("designer.form_name", "Form name")}
          value={name || ""}
          onChange={onNameChange}
          maxLength={80}
          error={!name ? t("designer.form_name_required", "Give the form a name.") : undefined}
          helpText={t("designer.form_name_help", "Only you see this name.")}
          autoComplete="off"
        />
        <Text as="h3" variant="headingSm">
          {t("designer.targeting_title", "Products that use this form")}
        </Text>
        {isDefault ? (
          <Text as="p" tone="subdued">
            {t("designer.targeting_default", "This is your default form. It is used for every product that has no other form.")}
          </Text>
        ) : (
          <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
            <ResourceTargetPicker
              type="product"
              label={t("common.products", "Products")}
              ids={value.product_ids}
              onChange={(ids) => onTargetingChange({ ...value, product_ids: ids })}
            />
            <ResourceTargetPicker
              type="collection"
              label={t("common.collections", "Collections")}
              ids={value.collection_ids}
              onChange={(ids) => onTargetingChange({ ...value, collection_ids: ids })}
            />
          </InlineGrid>
        )}
      </BlockStack>
    </Card>
  );
};

export default FormTargetingCard;

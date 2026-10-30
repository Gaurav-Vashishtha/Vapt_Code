import React from "react";
import {
  Card,
  FormLayout,
  BlockStack,
  Text,
  TextField,
  Checkbox,
  Button,
  Banner,
  Icon,
  Label,
  Tag,
  Tooltip,
} from "@shopify/polaris";
import { ProductsMajor } from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";

const HelpIcon = ({ content }) => (
  <Tooltip content={content}>
    <span
      style={{ display: "inline-flex", alignItems: "center", marginLeft: 4 }}
    >
      {/* <Icon source={QuestionMarkCircleIcon} tone="subdued" /> */}
    </span>
  </Tooltip>
);

const Placeholder = ({ children }) => (
  <div
    style={{
      maxWidth: "400px",
      padding: "16px",
      border: "1px dashed #C8C8CC",
      borderRadius: "8px",
      textAlign: "center",
      color: "#6D7175",
      fontSize: "14px",
    }}
  >
    {children}
  </div>
);

const ItemList = ({ items, onRemove }) => (
  <BlockStack vertical spacing="tight">
    {items.map((item) => (
      <div
        key={item}
        style={{
          background: "#F6F6F7",
          borderRadius: "6px",
          padding: "6px 8px",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <span>{item}</span>
        <Button plain onClick={() => onRemove(item)} icon={null}>
          {I18n.t("product_rules_card.remove")}
        </Button>
      </div>
    ))}
  </BlockStack>
);

export default function ProductRulesCard({
  setting,
  handleSettingChange,
  collectionsChecked,
  setCollectionsChecked,
  onItemRemoveHandler,
  openCollectionPicker,
  openResourcePicker,
  openVariantResourcePicker,
  resourcePickerError,
  setResourcePickerError,
  variantPickerError,
  setVariantPickerError,
}) {
  const selectedProductIds = setting.selectedProductIds?.split(",") || [];
  const showProductIds = setting.showProductIds?.split(",") || [];
  const selectedCollections = setting.selectedCollectionIds?.split(",") || [];
  const excludedCollections = setting.excludedCollectionIds?.split(",") || [];
  const variantIds = setting.hideProductVariantIds?.split(",") || [];

  return (
    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Icon source={ProductsMajor} tone="base" />
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.product_customer_rules_heading")}
        </Text>
      </BlockStack>

      <FormLayout>
        {/* COLLECTION RULES */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>{I18n.t("product_rules_card.hide_show_cod_for_specific_collections")}</span>
              <HelpIcon content={I18n.t("product_rules_card.show_or_hide_cash_on_delivery")} />
            </BlockStack>
          }
          checked={collectionsChecked}
          onChange={(checked) => {
            setCollectionsChecked(checked);
            if (!checked) {
              handleSettingChange("excludedCollectionIds")("");
              handleSettingChange("selectedCollectionIds")("");
            }
          }}
        />
        {collectionsChecked && (
          <BlockStack vertical spacing="tight">
            <Button
              onClick={() => openCollectionPicker("excludedCollectionIds")}
              disabled={!!setting.selectedCollectionIds}
            >
              {I18n.t("product_rules_card.exclude_collections")}
            </Button>
            {excludedCollections.length > 0 ? (
              <ItemList
                items={excludedCollections}
                onRemove={(item) =>
                  onItemRemoveHandler(item, "excludedCollectionIds")
                }
              />
            ) : (
              <Placeholder>{I18n.t("product_rules_card.no_excluded_collections")}</Placeholder>
            )}

            <Button
              onClick={() => openCollectionPicker("selectedCollectionIds")}
              disabled={!!setting.excludedCollectionIds}
            >
              {I18n.t("product_rules_card.include_collections")}
            </Button>
            {selectedCollections.length > 0 ? (
              <ItemList
                items={selectedCollections}
                onRemove={(item) =>
                  onItemRemoveHandler(item, "selectedCollectionIds")
                }
              />
            ) : (
              <Placeholder>{I18n.t("product_rules_card.no_included_collections")}</Placeholder>
            )}
          </BlockStack>
        )}

        {/* PRODUCT RULES */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>{I18n.t("product_rules_card.hide_show_cod_for_specific_products")}</span>
              <HelpIcon content={I18n.t("product_rules_card.control_cod_availability_per_product")} />
            </BlockStack>
          }
          checked={!!(selectedProductIds.length || showProductIds.length)}
          onChange={(checked) => {
            if (!checked) {
              handleSettingChange("selectedProductIds")("");
              handleSettingChange("showProductIds")("");
            }
          }}
        />
        {(selectedProductIds.length || showProductIds.length) > 0 && (
          <BlockStack spacing="tight" wrap>
            <BlockStack vertical>
              <Button
                onClick={() => openResourcePicker("selectedProductIds")}
                disabled={!!setting.showProductIds}
              >
                {I18n.t("product_rules_card.select_products_to_hide_cod")}
              </Button>
              {selectedProductIds.length > 0 ? (
                <ItemList
                  items={selectedProductIds}
                  onRemove={(item) =>
                    onItemRemoveHandler(item, "selectedProductIds")
                  }
                />
              ) : (
                <Placeholder>{I18n.t("product_rules_card.no_products_selected_to_hide")}</Placeholder>
              )}
            </BlockStack>
            <BlockStack vertical>
              <Button
                onClick={() => openResourcePicker("showProductIds")}
                disabled={!!setting.selectedProductIds}
              >
                {I18n.t("product_rules_card.select_products_to_show_cod")}
              </Button>
              {showProductIds.length > 0 ? (
                <ItemList
                  items={showProductIds}
                  onRemove={(item) =>
                    onItemRemoveHandler(item, "showProductIds")
                  }
                />
              ) : (
                <Placeholder>{I18n.t("product_rules_card.no_products_selected_to_show")}</Placeholder>
              )}
            </BlockStack>
          </BlockStack>
        )}

        {/* VARIANT RULES */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>{I18n.t("product_rules_card.hide_cod_for_specific_variants")}</span>
              <HelpIcon content={I18n.t("product_rules_card.useful_when_some_variants_e_g")} />
            </BlockStack>
          }
          checked={!!setting.hideProductVariantIds}
          onChange={(checked) => {
            if (!checked) handleSettingChange("hideProductVariantIds")("");
          }}
        />
        {setting.hideProductVariantIds && (
          <>
            <Button onClick={openVariantResourcePicker}>{I18n.t("product_rules_card.select_variants")}</Button>
            {variantIds.length > 0 ? (
              <ItemList
                items={variantIds}
                onRemove={(item) =>
                  onItemRemoveHandler(item, "hideProductVariantIds")
                }
              />
            ) : (
              <Placeholder>{I18n.t("product_rules_card.no_variants_selected")}</Placeholder>
            )}
          </>
        )}

        {/* CUSTOMER PHONE RULES */}
        <TextField
          label={I18n.t("product_rules_card.hide_cod_for_phone_numbers")}
          value={setting.phoneNumbers || ""}
          onChange={handleSettingChange("phoneNumbers")}
          placeholder="9920751234,9351234123"
          helpText={I18n.t("product_rules_card.enter_comma_separated_phone_numbers_to")}
        />

        {/* CUSTOMER EMAIL RULES */}
        <TextField
          label={I18n.t("product_rules_card.hide_cod_for_email_addresses")}
          value={setting.emailAddresses || ""}
          onChange={handleSettingChange("emailAddresses")}
          placeholder={I18n.t("product_rules_card.abc_example_com")}
          helpText={I18n.t("product_rules_card.enter_comma_separated_email_addresses_to")}
        />

        {/* ERROR BANNERS */}
        {resourcePickerError && (
          <Banner
            status="critical"
            onDismiss={() => setResourcePickerError(null)}
          >
            <p>{resourcePickerError}</p>
          </Banner>
        )}
        {variantPickerError && (
          <Banner
            status="critical"
            onDismiss={() => setVariantPickerError(null)}
          >
            <p>{variantPickerError}</p>
          </Banner>
        )}
      </FormLayout>
    </Card>
  );
}

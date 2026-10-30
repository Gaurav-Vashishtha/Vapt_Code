import React from "react";
import {
  Card,
  BlockStack,
  Checkbox,
  InlineStack,
  Button,
  Label,
  FormLayout,
  Banner,
  Text,
  Divider,
} from "@shopify/polaris";
import ItemList from "./codkiItemList";
import Placeholder from "./codkiPlaceholder";
import I18n from "../../i18n-lang";

function ProductCustomerRules({
  setting,
  handleSettingChange,
  renderTextField,
  renderTooltip,
  collectionsChecked,
  setCollectionsChecked,
  productIdChecked,
  variantChecked,
  checkedChangeHandler,
  setProductIdChecked,
  setVariantChecked,
  openCollectionPicker,
  openResourcePicker,
  openVariantResourcePicker,
  onItemRemoveHandler,
  resourcePickerError,
  variantPickerError,
  setResourcePickerError,
  setVariantPickerError,
  setContextualBar,
  disabled,
}) {
  return (
    <Card roundedAbove="sm" padding="400">
      <div
        style={{
          opacity: disabled ? 0.5 : 1,
          pointerEvents: disabled ? "none" : "auto",
        }}
      >
        <BlockStack gap="400">
          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide_detail.hide_payment_collections")}
              checked={collectionsChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) => {
                      setCollectionsChecked(checked);
                      if (!checked) {
                        handleSettingChange("excludedCollectionIds")("");
                        handleSettingChange("selectedCollectionIds")("");
                      }
                      setContextualBar(true);
                    }
              }
              disabled={disabled}
            />
          </InlineStack>

          {collectionsChecked && (
            <FormLayout>
              <Button
                onClick={() => openCollectionPicker("excludedCollectionIds")}
                disabled={!!setting.selectedCollectionIds || disabled}
              >
                {I18n.t("codki_product_customer_rules.select_collections_to_exclude")}
              </Button>
              <Label>{I18n.t("codki_product_customer_rules.collections_to_exclude_from_cash_on")}</Label>
              {renderTooltip(
                "COD will be hidden for customers buying from these collections."
              )}
              {setting.excludedCollectionIds ? (
                <ItemList
                  items={setting.excludedCollectionIds.split(",")}
                  onRemove={(item) =>
                    onItemRemoveHandler(item, "excludedCollectionIds")
                  }
                  disabled={disabled}
                />
              ) : (
                <Placeholder isDisabled={disabled}>
                  {I18n.t("codki_product_customer_rules.no_excluded_collections_selected")}
                </Placeholder>
              )}

              <Button
                onClick={() => openCollectionPicker("selectedCollectionIds")}
                disabled={!!setting.excludedCollectionIds || disabled}
              >
                {I18n.t("codki_product_customer_rules.select_collections_to_include")}
              </Button>
              <Label>{I18n.t("codki_product_customer_rules.collections_to_show_cash_on_delivery")}</Label>
              {renderTooltip(
                "COD will only be shown for customers buying from these collections."
              )}
              {setting.selectedCollectionIds ? (
                <ItemList
                  items={setting.selectedCollectionIds.split(",")}
                  onRemove={(item) =>
                    onItemRemoveHandler(item, "selectedCollectionIds")
                  }
                  disabled={disabled}
                />
              ) : (
                <Placeholder isDisabled={disabled}>
                  {I18n.t("codki_product_customer_rules.no_included_collections_selected")}
                </Placeholder>
              )}
            </FormLayout>
          )}

          {resourcePickerError && (
            <Banner
              tone="critical"
              onDismiss={() => setResourcePickerError(null)}
            >
              <Text as="p" variant="bodyMd">
                {resourcePickerError}
              </Text>
            </Banner>
          )}

          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide.hide_show_based_on_products_label")}
              checked={productIdChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) =>
                      checkedChangeHandler(
                        checked,
                        setProductIdChecked,
                        "productIdChecked"
                      )
              }
              disabled={disabled}
            />
          </InlineStack>

          {productIdChecked && (
            <BlockStack gap="400">
              <FormLayout>
                <Button
                  onClick={() => openResourcePicker("selectedProductIds")}
                  disabled={
                    (setting.showProductIds &&
                      setting.showProductIds.length > 0) ||
                    disabled
                  }
                >
                  {I18n.t("cod_show_hide.select_products_to_hide_button")}
                </Button>
                <Label>{I18n.t("cod_show_hide.products_to_hide_label")}</Label>
                {renderTooltip(
                  I18n.t("cod_show_hide.products_to_hide_tooltip")
                )}
                {setting.selectedProductIds ? (
                  <ItemList
                    items={setting.selectedProductIds.split(",")}
                    onRemove={(item) =>
                      onItemRemoveHandler(item, "selectedProductIds")
                    }
                    disabled={disabled}
                  />
                ) : (
                  <Placeholder isDisabled={disabled}>
                    {I18n.t("cod_show_hide.no_products_selected_message")}
                  </Placeholder>
                )}

                <Button
                  onClick={() => openResourcePicker("showProductIds")}
                  disabled={
                    (setting.selectedProductIds &&
                      setting.selectedProductIds.length > 0) ||
                    disabled
                  }
                >
                  {I18n.t("cod_show_hide.select_products_to_show_button")}
                </Button>
                <Label>{I18n.t("cod_show_hide.products_to_show_label")}</Label>
                {renderTooltip(
                  I18n.t("cod_show_hide.products_to_show_tooltip")
                )}
                {setting.showProductIds ? (
                  <ItemList
                    items={setting.showProductIds.split(",")}
                    onRemove={(item) =>
                      onItemRemoveHandler(item, "showProductIds")
                    }
                    disabled={disabled}
                  />
                ) : (
                  <Placeholder isDisabled={disabled}>
                    {I18n.t("cod_show_hide.no_products_selected_message")}
                  </Placeholder>
                )}
              </FormLayout>

              <Text as="p" variant="bodySm" fontWeight="bold">
                {I18n.t("cod_show_hide.important_label")}:
              </Text>
              <Text as="p" variant="bodySm">
                {I18n.t("cod_show_hide.product_limit_message")}
              </Text>
            </BlockStack>
          )}

          {variantPickerError && (
            <Banner
              tone="critical"
              onDismiss={() => setVariantPickerError(null)}
            >
              <Text as="p" variant="bodyMd">
                {variantPickerError}
              </Text>
            </Banner>
          )}

          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide.hide_show_based_on_variants_label")}
              checked={variantChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) =>
                      checkedChangeHandler(
                        checked,
                        setVariantChecked,
                        "variantChecked"
                      )
              }
              disabled={disabled}
            />
          </InlineStack>

          {variantChecked && (
            <BlockStack gap="400">
              <Button
                onClick={() => openVariantResourcePicker()}
                disabled={disabled}
              >
                {I18n.t("cod_show_hide.select_variants_button")}
              </Button>
              <Label>{I18n.t("cod_show_hide.variants_to_hide_label")}</Label>
              {renderTooltip(I18n.t("cod_show_hide.variants_to_hide_tooltip"))}
              {setting.hideProductVariantIds ? (
                <ItemList
                  items={setting.hideProductVariantIds.split(",")}
                  onRemove={(item) =>
                    onItemRemoveHandler(item, "hideProductVariantIds")
                  }
                  disabled={disabled}
                />
              ) : (
                <Placeholder isDisabled={disabled}>
                  {I18n.t("cod_show_hide.no_variants_selected_message")}
                </Placeholder>
              )}
            </BlockStack>
          )}

          <Divider />

          {renderTextField(
            I18n.t("cod_show_hide.phone_numbers_to_hide_label"),
            setting.phoneNumbers,
            handleSettingChange("phoneNumbers"),
            I18n.t("cod_show_hide.phone_numbers_help_text"),
            I18n.t("cod_show_hide.phone_numbers_placeholder"),
            "9920751234,9351234123",
            3
          )}

          {renderTextField(
            I18n.t("cod_show_hide.email_addresses_to_hide_label"),
            setting.emailAddresses,
            handleSettingChange("emailAddresses"),
            I18n.t("cod_show_hide.email_addresses_help_text"),
            I18n.t("cod_show_hide.email_addresses_placeholder"),
            "abc@example.com",
            3
          )}
        </BlockStack>
      </div>
    </Card>
  );
}

export default ProductCustomerRules;

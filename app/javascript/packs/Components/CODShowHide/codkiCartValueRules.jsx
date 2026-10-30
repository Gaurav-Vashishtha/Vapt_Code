import React from "react";
import { Card, BlockStack, Checkbox, InlineStack } from "@shopify/polaris";
import I18n from "../../i18n-lang";

function CartValueRules({
  setting,
  handleSettingChange,
  renderTextField,
  orderTotalChecked,
  setOrderTotalChecked,
  hideVendorsChecked,
  showVendorsChecked,
  setHideVendorsChecked,
  setShowVendorsChecked,
  toggleChangeHandler,
  checkedChangeHandler,
  disabled,
  shop,
}) {
  const hideVendorsField = renderTextField(
    I18n.t("cod_show_hide.hide_vendors_text_label"),
    setting.hideVendors,
    handleSettingChange("hideVendors"),
    I18n.t("cod_show_hide.hide_vendors_help_text"),
    null,
    I18n.t("cod_show_hide.hide_vendors_placeholder"),
    3,
    false,
    "400px"
  );

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
              label={I18n.t("cod_show_hide.hide_based_on_order_total_label")}
              checked={orderTotalChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) =>
                      checkedChangeHandler(
                        checked,
                        setOrderTotalChecked,
                        "orderTotalChecked"
                      )
              }
              disabled={disabled}
            />
          </InlineStack>

          <BlockStack
            style={{ display: orderTotalChecked ? "block" : "none" }}
            gap="400"
          >
            {renderTextField(
              I18n.t("cod_show_hide.min_order_total_label", {
                currency: shop.currency,
              }),
              setting.minCartTotal,
              handleSettingChange("minCartTotal"),
              I18n.t("cod_show_hide.min_order_total_help_text"),
              I18n.t("cod_show_hide.min_order_total_placeholder"),
              "0",
              false,
              false,
              false
            )}
            {renderTextField(
              I18n.t("cod_show_hide.max_order_total_label", {
                currency: shop.currency,
              }),
              setting.maxCartTotal,
              handleSettingChange("maxCartTotal"),
              I18n.t("cod_show_hide.max_order_total_help_text"),
              I18n.t("cod_show_hide.max_order_total_placeholder"),
              "0",
              false,
              false,
              false
            )}
          </BlockStack>

          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide.hide_for_vendors_label")}
              checked={hideVendorsChecked}
              onChange={
                disabled
                  ? () => {}
                  : (checked) => {
                      setHideVendorsChecked(checked);
                      toggleChangeHandler(checked, "hideVendorsChecked");
                    }
              }
              disabled={disabled}
            />
          </InlineStack>

          <BlockStack
            style={{ display: hideVendorsChecked ? "block" : "none" }}
          >
            {hideVendorsField}
          </BlockStack>

          <InlineStack align="start" gap="100" blockAlign="center" wrap>
            <Checkbox
              label={I18n.t("cod_show_hide_detail.enable_show_vendors")}
              checked={showVendorsChecked}
              onChange={
                disabled
                  ? () => {}
                  : (val) => {
                      setShowVendorsChecked(val);
                      toggleChangeHandler(val, "showVendorsChecked");
                    }
              }
              disabled={disabled}
            />
          </InlineStack>

          <BlockStack
            style={{ display: showVendorsChecked ? "block" : "none" }}
          >
            {renderTextField(
              I18n.t("cod_show_hide.show_vendors_text_label"),
              setting.showVendors,
              handleSettingChange("showVendors"),
              I18n.t("cod_show_hide.show_vendors_help_text"),
              null,
              I18n.t("cod_show_hide.show_vendors_placeholder"),
              3,
              false,
              "400px"
            )}
          </BlockStack>
        </BlockStack>
      </div>
    </Card>
  );
}

export default CartValueRules;

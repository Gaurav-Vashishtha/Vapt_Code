import React from "react";
import {
  Card,
  FormLayout,
  BlockStack,
  Text,
  TextField,
  Checkbox,
  Icon,
  Tooltip,
} from "@shopify/polaris";
import { CartMajor } from "@shopify/polaris-icons";
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

export default function OrderRulesCard({
  setting,
  handleSettingChange,
  orderTotalChecked,
  setOrderTotalChecked,
  hideVendorsChecked,
  setHideVendorsChecked,
  showVendorsChecked,
  setShowVendorsChecked,
  shop,
}) {
  const handleCheckboxChange = (checked, key) => {
    if (!checked) {
      if (key === "orderTotalChecked") {
        handleSettingChange("minCartTotal")("");
        handleSettingChange("maxCartTotal")("");
      } else if (key === "hideVendorsChecked") {
        handleSettingChange("hideVendors")("");
      } else if (key === "showVendorsChecked") {
        handleSettingChange("showVendors")("");
      }
    }
    if (key === "orderTotalChecked") setOrderTotalChecked(checked);
    if (key === "hideVendorsChecked") {
      setHideVendorsChecked(checked);
      if (checked) {
        handleSettingChange("showVendors")("");
        setShowVendorsChecked(false);
      }
    }
    if (key === "showVendorsChecked") {
      setShowVendorsChecked(checked);
      if (checked) {
        handleSettingChange("hideVendors")("");
        setHideVendorsChecked(false);
      }
    }
  };

  return (
    /* Cart value and vendor rules are two cards: together they can put six
       controls on screen, one past what Built for Shopify allows in a card. */
    <BlockStack gap="400">
    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Icon source={CartMajor} tone="base" />
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.cart_value_rules_heading")}
        </Text>
      </BlockStack>

      <FormLayout>
        {/* Order total based rules */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>
                {I18n.t("cod_show_hide.hide_based_on_order_total_label")}
              </span>
              <HelpIcon
                content={I18n.t(
                  "cod_show_hide.hide_based_on_order_total_tooltip"
                )}
              />
            </BlockStack>
          }
          checked={orderTotalChecked}
          onChange={(checked) =>
            handleCheckboxChange(checked, "orderTotalChecked")
          }
        />
        {orderTotalChecked && (
          <BlockStack spacing="loose">
            <TextField
              label={I18n.t("cod_show_hide.min_order_total_label", {
                currency: shop.currency,
              })}
              type="number"
              value={setting.minCartTotal || ""}
              onChange={handleSettingChange("minCartTotal")}
              placeholder="0"
              helpText={I18n.t("cod_show_hide.min_order_total_help_text")}
            />
            <TextField
              label={I18n.t("cod_show_hide.max_order_total_label", {
                currency: shop.currency,
              })}
              type="number"
              value={setting.maxCartTotal || ""}
              onChange={handleSettingChange("maxCartTotal")}
              placeholder="0"
              helpText={I18n.t("cod_show_hide.max_order_total_help_text")}
            />
          </BlockStack>
        )}
      </FormLayout>
    </Card>

    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.vendor_rules_heading", {
            defaultValue: "Vendor rules",
          })}
        </Text>
      </BlockStack>

      <FormLayout>
        {/* Hide for Vendors */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>{I18n.t("cod_show_hide.hide_for_vendors_label")}</span>
              <HelpIcon
                content={I18n.t("cod_show_hide.hide_for_vendors_tooltip")}
              />
            </BlockStack>
          }
          checked={hideVendorsChecked}
          onChange={(checked) =>
            handleCheckboxChange(checked, "hideVendorsChecked")
          }
        />
        {hideVendorsChecked && (
          <TextField
            label={I18n.t("cod_show_hide.hide_vendors_text_label")}
            value={setting.hideVendors || ""}
            onChange={handleSettingChange("hideVendors")}
            multiline
            placeholder={I18n.t("cod_show_hide.hide_vendors_placeholder")}
            helpText={I18n.t("cod_show_hide.hide_vendors_help_text")}
          />
        )}

        {/* Show for Vendors */}
        <Checkbox
          label={
            <BlockStack alignment="center">
              <span>{I18n.t("cod_show_hide.show_for_vendors_label")}</span>
              <HelpIcon
                content={I18n.t("cod_show_hide.show_for_vendors_tooltip")}
              />
            </BlockStack>
          }
          checked={showVendorsChecked}
          onChange={(checked) =>
            handleCheckboxChange(checked, "showVendorsChecked")
          }
        />
        {showVendorsChecked && (
          <TextField
            label={I18n.t("cod_show_hide.show_vendors_text_label")}
            value={setting.showVendors || ""}
            onChange={handleSettingChange("showVendors")}
            multiline
            placeholder={I18n.t("cod_show_hide.show_vendors_placeholder")}
            helpText={I18n.t("cod_show_hide.show_vendors_help_text")}
          />
        )}
      </FormLayout>
    </Card>
    </BlockStack>
  );
}

import React from "react";
import {
  Card,
  BlockStack,
  Text,
  Checkbox,
  Tooltip,
  Icon,
  Select,
  TextField,
  Button,
  Banner,
} from "@shopify/polaris";
// import { QuestionMarkCircleIcon } from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";

// For Tooltip Icon
const HelpIcon = ({ content }) => (
  <Tooltip content={content}>
    <span
      style={{ display: "inline-flex", alignItems: "center", marginLeft: 4 }}
    >
      {/* <Icon source={QuestionMarkCircleIcon} tone="subdued" /> */}
    </span>
  </Tooltip>
);

export default function GeneralSettingsCard({
  setting,
  handleSettingChange,
  plan,
  shop,
  setTab,
  isPrepaidEnabled,
  paymentMethods = [],
}) {
  // Show Banner if plan is Free or feature is locked
  const renderBanner = () => {
    if (plan?.name === "Free" || !shop?.charge_id) {
      return (
        <Banner
          tone="warning"
          title={I18n.t("cod_show_hide.banner_test_mode_title")}
          action={{
            content: I18n.t("cod_show_hide.upgrade_now_button"),
            onAction: () => setTab(isPrepaidEnabled ? 8 : 7),
          }}
        >
          <Text as="span" variant="bodyMd">
            {I18n.t("cod_show_hide.banner_test_mode_body")}
          </Text>
        </Banner>
      );
    }
    if (setting?.lockPaidFeature) {
      return (
        <Banner
          tone="warning"
          title={I18n.t("cod_show_hide.banner_locked_title")}
          action={{
            content: I18n.t("cod_show_hide.upgrade_now_button"),
            onAction: () => setTab(isPrepaidEnabled ? 8 : 7),
          }}
        >
          <Text as="span" variant="bodyMd">
            {I18n.t("cod_show_hide.banner_locked_body")}
          </Text>
        </Banner>
      );
    }
    return null;
  };

  return (
    <Card>
      {renderBanner()}

      <BlockStack gap="2">
        {/* <Icon source={CashIcon} tone="base" /> */}
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.payment_rules_heading")}
        </Text>

        <BlockStack gap="4">
          <Select
            label={
              <BlockStack gap="1">
                <span>
                  {I18n.t("cod_show_hide.select_payment_method_label")}
                </span>
                <HelpIcon
                  content={I18n.t(
                    "cod_show_hide.select_payment_method_help_text"
                  )}
                />
              </BlockStack>
            }
            options={paymentMethods.map((method) => ({
              label: method.label,
              value: method.value,
            }))}
            value={setting.paymentMethodName || ""}
            onChange={handleSettingChange("paymentMethodName")}
            disabled={setting.lockPaidFeature}
          />

          <Checkbox
            label={
              <BlockStack gap="1">
                <span>
                  {I18n.t("cod_show_hide.hide_shipping_method_label")}
                </span>
                <HelpIcon
                  content={I18n.t("cod_show_hide.hide_shipping_method_tooltip")}
                />
              </BlockStack>
            }
            checked={!!setting.hideShippingMethod}
            onChange={handleSettingChange("hideShippingMethod")}
            helpText={I18n.t("cod_show_hide.hide_shipping_method_help_text")}
            disabled={setting.lockPaidFeature}
          />

          {setting.hideShippingMethod && (
            <TextField
              label={
                <BlockStack gap="1">
                  <span>{I18n.t("cod_show_hide.shipping_keyword_label")}</span>
                  <HelpIcon
                    content={I18n.t(
                      "cod_show_hide.shipping_keyword_placeholder"
                    )}
                  />
                </BlockStack>
              }
              value={setting.codFeeShippingKeyword || ""}
              onChange={handleSettingChange("codFeeShippingKeyword")}
              helpText={I18n.t("cod_show_hide.shipping_keyword_help_text")}
              placeholder={I18n.t("cod_show_hide.shipping_keyword_placeholder")}
              autoComplete="off"
              disabled={setting.lockPaidFeature}
            />
          )}

          <Checkbox
            label={
              <BlockStack gap="1">
                <span>{I18n.t("cod_show_hide.hide_for_gift_cards_label")}</span>
                <HelpIcon
                  content={I18n.t("cod_show_hide.hide_for_gift_cards_tooltip")}
                />
              </BlockStack>
            }
            checked={!!setting.hideGiftCards}
            onChange={handleSettingChange("hideGiftCards")}
            helpText={I18n.t("cod_show_hide.hide_for_gift_cards_help_text")}
            disabled={setting.lockPaidFeature}
          />
        </BlockStack>
      </BlockStack>
    </Card>
  );
}

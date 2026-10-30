import React, { useCallback } from "react";
import { Card, BlockStack, Checkbox, InlineStack, Box } from "@shopify/polaris";
import MultiSelect from "./codkiMultiSelect";
import I18n from "../../i18n-lang";

function PaymentRules({
  setting,
  handleSettingChange,
  renderTextField,
  renderTooltip,
  renderMultiSelect,
  disabled,
  paymentMethods,
}) {
  const codShippingKeywordField = renderTextField(
    I18n.t("cod_show_hide.shipping_keyword_label"),
    setting.codFeeShippingKeyword,
    handleSettingChange("codFeeShippingKeyword"),
    I18n.t("cod_show_hide.shipping_keyword_help_text"),
    I18n.t("cod_show_hide.shipping_keyword_placeholder"),
    "",
    false,
    false
  );

  const handleHideShippingMethodChange = useCallback(
    (checked) => {
      if (disabled) return;
      handleSettingChange("hideShippingMethod")(checked);
    },
    [disabled, handleSettingChange]
  );

  return (
    <Card roundedAbove="sm">
      <div
        style={{
          opacity: disabled ? 0.5 : 1,
          pointerEvents: disabled ? "none" : "auto",
        }}
      >
        <BlockStack gap="400">
          {renderMultiSelect(
            "paymentMethodName",
            I18n.t("cod_show_hide.select_payment_method_label"),
            paymentMethods?.paymentMethods?.map((method) => ({
              value: method.value,
              label: method.label,
            })) || [],
            I18n.t("cod_show_hide.select_payment_method_help_text"),
            false
          )}

          <InlineStack align="start" gap="100">
            <Checkbox
              label={I18n.t("cod_show_hide.hide_shipping_method_label")}
              checked={setting.hideShippingMethod}
              onChange={handleHideShippingMethodChange}
              disabled={disabled}
            />
            {renderTooltip(
              I18n.t("cod_show_hide.hide_shipping_method_tooltip")
            )}
          </InlineStack>

          {setting.hideShippingMethod && (
            <BlockStack gap="200">{codShippingKeywordField}</BlockStack>
          )}

          <InlineStack align="start" gap="100">
            <Checkbox
              label={I18n.t("cod_show_hide.hide_for_gift_cards_label")}
              checked={setting.hideGiftCards}
              onChange={
                disabled ? () => {} : handleSettingChange("hideGiftCards")
              }
              disabled={disabled}
            />
            {renderTooltip(I18n.t("cod_show_hide.hide_for_gift_cards_tooltip"))}
          </InlineStack>
        </BlockStack>
      </div>
    </Card>
  );
}

export default PaymentRules;

import React from "react";
import {
  Card,
  FormLayout,
  Text,
  BlockStack,
  Icon,
  Select,
  Tag,
  Tooltip,
  Button,
  Checkbox,
} from "@shopify/polaris";
import { ShipmentMajor } from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";

// Reusable tooltip icon
const HelpIcon = ({ content }) => (
  <Tooltip content={content}>
    <span
      style={{ display: "inline-flex", alignItems: "center", marginLeft: 4 }}
    >
      {/* <Icon source={QuestionMarkCircleIcon} tone="subdued" /> */}
    </span>
  </Tooltip>
);

const deliveryOptions = [
  { get label() {
      return I18n.t("cod_show_hide.local_delivery_label");
    }, value: "LOCAL" },
  { get label() {
      return I18n.t("cod_show_hide.pickup_point_label");
    }, value: "PICKUP_POINT" },
  { get label() {
      return I18n.t("cod_show_hide.pickup_label");
    }, value: "PICK_UP" },
  { get label() {
      return I18n.t("cod_show_hide.retail_label");
    }, value: "RETAIL" },
  { get label() {
      return I18n.t("cod_show_hide.shipping_label");
    }, value: "SHIPPING" },
];

export default function DeliveryMethodsCard({ setting, handleSettingChange }) {
  const selectedValues = setting.hideDeliveryMethod
    ? setting.hideDeliveryMethod.split(",")
    : [];

  const onChange = (newValues) => {
    handleSettingChange("hideDeliveryMethod")(newValues);
  };

  return (
    <Card>
      <BlockStack alignment="center" spacing="tight">
        <Icon source={ShipmentMajor} tone="base" />
        <Text as="h2" variant="headingSm">
          {I18n.t("cod_show_hide.delivery_methods_heading")}
        </Text>
      </BlockStack>

      <FormLayout>
        <div style={{ maxWidth: 400 }}>
          <BlockStack alignment="center">
            <span>{I18n.t("cod_show_hide.select_delivery_methods_label")}</span>
            <HelpIcon
              content={I18n.t(
                "cod_show_hide.select_delivery_methods_help_text"
              )}
            />
          </BlockStack>

          <Select
            label=""
            options={deliveryOptions}
            value={selectedValues}
            onChange={onChange}
            multiple
          />

          {selectedValues.length > 0 && (
            <BlockStack spacing="tight" wrap>
              {selectedValues.map((method) => {
                const label =
                  deliveryOptions.find((opt) => opt.value === method)?.label ||
                  method;
                return <Tag key={method}>{label}</Tag>;
              })}
            </BlockStack>
          )}
        </div>
      </FormLayout>
    </Card>
  );
}

import React from "react";
import { Card, BlockStack } from "@shopify/polaris";
import I18n from "../../i18n-lang";

function DeliveryMethods({ renderMultiSelect, disabled }) {
  return (
    <Card roundedAbove="sm" padding="400">
      <div
        style={{
          opacity: disabled ? 0.5 : 1,
          pointerEvents: disabled ? "none" : "auto",
        }}
      >
        <BlockStack gap="400">
          {renderMultiSelect(
            "hideDeliveryMethod",
            I18n.t("cod_show_hide.select_delivery_methods_label"),
            [
              {
                label: I18n.t("cod_show_hide.local_delivery_label"),
                value: "LOCAL",
              },
              {
                label: I18n.t("cod_show_hide.pickup_point_label"),
                value: "PICKUP_POINT",
              },
              {
                label: I18n.t("cod_show_hide.pickup_label"),
                value: "PICK_UP",
              },
              {
                label: I18n.t("cod_show_hide.retail_label"),
                value: "RETAIL",
              },
              {
                label: I18n.t("cod_show_hide.shipping_label"),
                value: "SHIPPING",
              },
            ],
            I18n.t("cod_show_hide.select_delivery_methods_help_text")
          )}
        </BlockStack>
      </div>
    </Card>
  );
}

export default DeliveryMethods;

import React, { useContext } from "react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  Badge,
} from "@shopify/polaris";
import { StoreContext } from "../../../Context/Store";
import I18n from "../../../i18n-lang";

const FeatureSummaryCard = () => {
  const {
    setting: [setting],
  } = useContext(StoreContext);

  const s = setting || {};

  const featureList = [
    {
      label: I18n.t("summary_v2.features.otp", { defaultValue: "OTP" }),
      enabled: !!(s.sms || s.enablePreOrderOtp),
    },
    {
      label: I18n.t("summary_v2.features.partial_payment", { defaultValue: "Partial Payment" }),
      enabled: !!s.partialPaymentEnabled,
    },
    {
      label: I18n.t("summary_v2.features.cod_fees", { defaultValue: "COD Fees" }),
      enabled: !!(s.codFeeEnabled || s.enableShippingCodFees),
    },
    {
      label: I18n.t("summary_v2.features.cod_to_prepaid", { defaultValue: "COD → Prepaid" }),
      enabled: !!s.prepaidEnabled,
    },
    {
      label: I18n.t("summary_v2.features.abandoned_cart", { defaultValue: "Abandoned Cart" }),
      enabled: !!(s.abandonedCartEnabled || s.acWhatsapp),
    },
    {
      label: I18n.t("summary_v2.features.whatsapp", { defaultValue: "WhatsApp" }),
      enabled: !!(
        s.confirmationWhatsapp ||
        s.fulfilmentWhatsapp ||
        s.acWhatsapp ||
        s.sendVerificationLinkOnly
      ),
    },
  ];

  return (
    <Card>
      <BlockStack gap="300">
        <Text as="h3" variant="headingSm">
          {I18n.t("summary_v2.features.title", { defaultValue: "Features" })}
        </Text>
        <BlockStack gap="200">
          {featureList.map((f) => (
            <InlineStack key={f.label} align="space-between" blockAlign="center">
              <Text as="span" variant="bodySm">
                {f.label}
              </Text>
              <Badge
                tone={f.enabled ? "success" : "attention"}
                progress={f.enabled ? "complete" : "incomplete"}
              >
                {f.enabled
                  ? I18n.t("admin.enabled", { defaultValue: "Enabled" })
                  : I18n.t("admin.disabled", { defaultValue: "Disabled" })}
              </Badge>
            </InlineStack>
          ))}
        </BlockStack>
      </BlockStack>
    </Card>
  );
};

export default FeatureSummaryCard;

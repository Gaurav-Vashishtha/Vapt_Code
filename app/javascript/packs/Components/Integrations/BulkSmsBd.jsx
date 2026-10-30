import React, { useState, useEffect, useContext } from "react";
import { Card, TextField, FormLayout, Link, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const BulkSmsBd = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);
  const [showHelp, setShowHelp] = useState(false);

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleSettingChange = (key) => (value) => {
    setSetting({
      ...setting,
      [key]: value,
    });
    !contextualBar && setContextualBar(true);
  };

  return (
    <Card title={I18n.t("admin.x_configuration", { brand: "BulkSMSBD" })} sectioned>
      {/* {providerConfigurationError && (
        <Banner title={I18n.t("network_settings.config_issue")} tone="critical">
          <Text variant="bodySm" as="p" breakWord>
            {providerConfigurationError}
          </Text>
        </Banner>
      )} */}
      <FormLayout>
        <FormLayout.Group>
          <RevealTextField
            label={I18n.t("integrations.api_key")}
            value={setting.providerApiKey || ""}
            onChange={handleSettingChange("providerApiKey")}
            placeholder={I18n.t("bulk_sms_bd.kn")}
            type="password"
            helpText={I18n.t("integrations.api_key_dashboard_help", { brand: "BulkSMSBD" })}
            error={fieldError(setting.providerApiKey, I18n.t("integrations.api_key"))}
          />
          <TextField
            label={I18n.t("integrations.sender_id")}
            value={setting.providerSenderId || ""}
            onChange={handleSettingChange("providerSenderId")}
            placeholder="8809617628***"
            onFocus={() => setShowHelp(true)}
            helpText={I18n.t("integrations.sender_id_delivery_help")}
            error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
          />
        </FormLayout.Group>
        
        {showHelp && (
          <Banner
            title={I18n.t("integrations.setup_help_title", { brand: "BulkSMSBD" })}
            status="info"
            onDismiss={() => setShowHelp(false)}
          >
            <p>
              <strong>{I18n.t("integrations.api_key")}:</strong> {I18n.t("integrations.api_key_found_help", { brand: "BulkSMSBD" })}
            </p>
            <p>
              <strong>{I18n.t("integrations.sender_id")}:</strong> {I18n.t("integrations.sender_id_provided_help", { brand: "BulkSMSBD" })}
            </p>
            <p>
              {I18n.t("integrations.need_help_visit")}{" "}
              <Link url="http://bulksmsbd.net" external>
                {I18n.t("integrations.provider_documentation", { brand: "BulkSMSBD" })}
              </Link>
            </p>
          </Banner>
        )}
      </FormLayout>
    </Card>
  );
};

export default BulkSmsBd;
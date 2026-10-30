import React, { useState, useEffect, useContext } from "react";
import { Card, TextField, FormLayout, Link, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";

const ThaiBulkSMS = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const [showHelp, setShowHelp] = useState(false);

  const apiKey = setting.providerApiKey || "";

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleChange = (key) => (value) => {
    if (key === "apiKey") {
      setSetting({
        ...setting,
        providerApiKey: value,
      });
    } else {
      setSetting({
        ...setting,
        [key]: value,
      });
    }
    !contextualBar && setContextualBar(true);
  };

  useEffect(() => {
    if (setting.providerApiKey === "Basic Og==") {
      setSetting({
        ...setting,
        providerApiKey: "",
      });
    }
  }, [setting.providerApiKey]);

  return (
    <Card title={I18n.t("admin.x_configuration", { brand: "ThaiBulkSMS" })} sectioned>
      {/* {providerConfigurationError && (
        <Banner title={I18n.t("network_settings.config_issue")} tone="critical">
          <Text variant="bodySm" as="p" breakWord>
            {providerConfigurationError}
          </Text>
        </Banner>
      )} */}
      <FormLayout>
        <FormLayout.Group>
          <TextField
            label={I18n.t("integrations.api_key_auth_header")}
            value={apiKey}
            onChange={handleChange("apiKey")}
            placeholder={I18n.t("thai_bulk_sms.paste_the_exact_value_from_thaibulksms")}
            error={fieldError(apiKey, I18n.t("integrations.api_key_auth_header"))}
          />
          <TextField
            label={I18n.t("integrations.sender_id")}
            value={setting.providerSenderId}
            onChange={handleChange("providerSenderId")}
            placeholder={I18n.t("thai_bulk_sms.your_brand_name_or_sender_id")}
            onFocus={() => setShowHelp(true)}
            error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
          />
        </FormLayout.Group>
        {showHelp && (
          <div style={{ fontSize: "13px", color: "#666" }}>
            {I18n.t("integrations.sender_id_register_help", { brand: "ThaiBulkSMS" })}
          </div>
        )}
      </FormLayout>
    </Card>
  );
};

export default ThaiBulkSMS;

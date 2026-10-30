import React, { useState, useEffect, useContext } from "react";
import { Card, TextField, FormLayout, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const SmsMisr = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const parts = setting.providerApiKey?.split(":") || [];
  const [username, password, templateId, environment] = [
    parts[0] || "",
    parts[1] || "",
    parts[2] || "",
    parts[3] || "",
  ];

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleSettingChange = (field) => (value) => {
    let newParts = [username, password, templateId, environment];
    switch (field) {
      case "username":
        newParts[0] = value;
        break;
      case "password":
        newParts[1] = value;
        break;
      case "templateId":
        newParts[2] = value;
        break;
      case "environment":
        newParts[3] = value;
        break;
    }

    setSetting({
      ...setting,
      providerApiKey: newParts.join(":"),
    });

    !contextualBar && setContextualBar(true);
  };

  const handleSenderChange = (value) => {
    setSetting({
      ...setting,
      providerSenderId: value,
    });
    !contextualBar && setContextualBar(true);
  };

  useEffect(() => {
    if (setting.providerApiKey === ":::" || setting.providerApiKey === "") {
      setSetting({
        ...setting,
        providerApiKey: "",
      });
    }
  }, [setting.providerApiKey]);

  return (
    <Card title={I18n.t("admin.x_configuration", { brand: "SMSMisr" })} sectioned>
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
            label={I18n.t("integrations.username")}
            value={username}
            onChange={handleSettingChange("username")}
            placeholder={I18n.t("sms_misr.your_api_username")}
            error={fieldError(username, I18n.t("integrations.username"))}
          />
          <RevealTextField
            label={I18n.t("integrations.password")}
            value={password}
            onChange={handleSettingChange("password")}
            placeholder={I18n.t("sms_misr.api_password")}
            type="password"
            error={fieldError(password, I18n.t("integrations.password"))}
          />
        </FormLayout.Group>
        <FormLayout.Group>
          <TextField
            label={I18n.t("integrations.template_id")}
            value={templateId}
            onChange={handleSettingChange("templateId")}
            placeholder={I18n.t("sms_misr.dlt_approved_template_id")}
            error={fieldError(templateId, I18n.t("integrations.template_id"))}
          />
          <TextField
            label={I18n.t("integrations.environment")}
            value={environment}
            onChange={handleSettingChange("environment")}
            placeholder={I18n.t("sms_misr.1_live_0_test")}
            error={fieldError(environment, I18n.t("integrations.environment"))}
          />
        </FormLayout.Group>
        <TextField
          label={I18n.t("integrations.sender_id")}
          value={setting.providerSenderId}
          onChange={handleSenderChange}
          placeholder={I18n.t("sms_misr.your_sender_id_case_sensitive")}
          error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
        />
      </FormLayout>
    </Card>
  );
};

export default SmsMisr;

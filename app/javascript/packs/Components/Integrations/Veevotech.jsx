import React, { useContext } from "react";
import { Card, TextField, FormLayout, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const Veevotech = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

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
    <Card
      title={I18n.t("admin.x_configuration", { brand: "Veevotech" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "Veevotech" }),
          external: true,
          url: "https://veevotech.com/vt_sms_api",
        },
      ]}
    >
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
            value={setting.providerApiKey}
            onChange={handleSettingChange("providerApiKey")}
            placeholder={I18n.t("veevotech.1f0asdas01313sdas0asdasas13asa")}
            type="password"
            error={fieldError(setting.providerApiKey, I18n.t("integrations.api_key"))}
          />
          <TextField
            label={I18n.t("integrations.sender_id")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder="8583"
            error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default Veevotech;

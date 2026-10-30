import React, { useContext } from "react";
import { Card, TextField, FormLayout, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const ChatApi = ({ providerConfigurationError, showFieldErrors }) => {
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
      title={I18n.t("admin.x_configuration", { brand: "Chat API" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "Chat API" }),
          external: true,
          url: "https://chat-api.com/en/",
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
          <TextField
            label={I18n.t("integrations.instance_id")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder="12345"
            error={fieldError(setting.providerSenderId, I18n.t("integrations.instance_id"))}
          />
          <RevealTextField
            label={I18n.t("integrations.token")}
            value={setting.providerApiKey}
            onChange={handleSettingChange("providerApiKey")}
            placeholder={I18n.t("chat_api.r0asdas01313sdas0asdasas13asa")}
            type="password"
            error={fieldError(setting.providerApiKey, I18n.t("integrations.token"))}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default ChatApi;

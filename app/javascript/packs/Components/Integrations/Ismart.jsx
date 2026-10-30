import React, { useContext } from "react";
import { Card, TextField, FormLayout, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const Ismart = ({ providerConfigurationError, showFieldErrors }) => {
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
      title={I18n.t("admin.x_configuration", { brand: "iSmart" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "iSmart" }),
          external: true,
          url: "https://ismartsms.net/",
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
            placeholder={I18n.t("ismart.1f0asdas01313sdas0asdasas13asa")}
            type="password"
            error={fieldError(setting.providerApiKey, I18n.t("integrations.api_key"))}
          />
          <TextField
            label={I18n.t("integrations.sender_id")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder={I18n.t("ismart.yourbrand")}
            error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default Ismart;

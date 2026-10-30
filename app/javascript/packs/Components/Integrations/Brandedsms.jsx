import React, { useEffect, useContext } from "react";
import { Card, TextField, FormLayout, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const BrandedSMS = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const sid = setting.providerApiKey?.split(":")[0];
  const token = setting.providerApiKey?.split(":")[1];

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleSettingChange = (key) => (value) => {
    if (key === "sid") {
      setSetting({
        ...setting,
        providerApiKey: `${value}:${token}`,
      });
    } else if (key === "token") {
      setSetting({
        ...setting,
        providerApiKey: `${sid}:${value}`,
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
    if (setting.providerApiKey === ":") {
      setSetting({
        ...setting,
        providerApiKey: "",
      });
    }
  }, [setting.providerApiKey]);

  return (
    <Card
      title={I18n.t("admin.x_configuration", { brand: "Branded SMS" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "Branded SMS" }),
          external: true,
          url: "https://brandedsmspakistan.com",
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
            label={I18n.t("integrations.email")}
            value={sid}
            onChange={handleSettingChange("sid")}
            placeholder={I18n.t("brandedsms.abc_xyz_com")}
            error={fieldError(sid, I18n.t("integrations.email"))}
          />
          <RevealTextField
            label={I18n.t("integrations.api_key")}
            value={token}
            onChange={handleSettingChange("token")}
            placeholder={I18n.t("brandedsms.1f0asdas01313sdas0asdasas13asa")}
            type="password"
            error={fieldError(token, I18n.t("integrations.api_key"))}
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

export default BrandedSMS;

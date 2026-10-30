import React, { useState, useEffect, useContext } from "react";
import { Card, TextField, FormLayout, Link, Banner, Text } from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const ESms = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);
  const key = setting.providerApiKey?.split(":")[0];
  const secret = setting.providerApiKey?.split(":")[1];

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleSettingChange = (key) => (value) => {
    if (key === "key") {
      setSetting({
        ...setting,
        providerApiKey: `${value}:${secret}`,
      });
    } else if (key === "secret") {
      setSetting({
        ...setting,
        providerApiKey: `${key}:${value}`,
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
      title={I18n.t("admin.x_configuration", { brand: "eSMS" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "eSMS" }),
          external: true,
          url: "https://esms.vn",
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
            label={I18n.t("integrations.api_key")}
            value={key}
            onChange={handleSettingChange("key")}
            placeholder={I18n.t("esms.acbhahsah3h1hasdh1h12hdshahadhahsha71")}
            error={fieldError(key, I18n.t("integrations.api_key"))}
          />
          <RevealTextField
            label={I18n.t("integrations.api_secret")}
            value={secret}
            onChange={handleSettingChange("secret")}
            placeholder={I18n.t("esms.1f0asdas01313sdas0asdasas13asa")}
            type="password"
            error={fieldError(secret, I18n.t("integrations.api_secret"))}
          />
          <TextField
            label={I18n.t("integrations.sender_id")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder={I18n.t("esms.your_brand_name")}
            error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default ESms;

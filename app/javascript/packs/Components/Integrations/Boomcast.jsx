import React, { useState, useEffect, useContext } from "react";
import {
  Card,
  TextField,
  FormLayout,
  Link,
  Banner,
  Text,
} from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const Boomcast = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);
  const [showHelp, setShowHelp] = useState(false);
  const sid = setting.providerApiKey?.split(":")[0];
  const token = setting.providerApiKey?.split(":")[1];

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim())
      return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim())
      return I18n.t("integrations.field_check_save", { field: label });
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
      title={I18n.t("admin.x_configuration", { brand: "Boomcast" })}
      sectioned
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
            label={I18n.t("integrations.username")}
            value={sid}
            onChange={handleSettingChange("sid")}
            placeholder={I18n.t("boomcast.abctst")}
            error={fieldError(sid, I18n.t("integrations.username"))}
          />
          <RevealTextField
            label={I18n.t("integrations.password")}
            value={token}
            onChange={handleSettingChange("token")}
            placeholder={I18n.t("boomcast.1f0asdas01313sdas0asdasas13asa")}
            type="password"
            error={fieldError(token, I18n.t("integrations.password"))}
          />
          <TextField
            label={I18n.t("integrations.masking")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder={I18n.t("boomcast.your_brand_sender_id_case_sensitive")}
            onFocus={() => setShowHelp(true)}
            error={fieldError(
              setting.providerSenderId,
              I18n.t("integrations.masking"),
            )}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default Boomcast;

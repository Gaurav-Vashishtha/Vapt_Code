import React, { useState, useEffect, useContext } from "react";
import {
  Card,
  TextField,
  FormLayout,
  Text,
  Link,
  Page,
  BlockStack,
  InlineGrid,
  Box,
  Divider,
  Banner,
} from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const Twilio = ({ providerConfigurationError, showFieldErrors }) => {
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
    <Page
      title={I18n.t("admin.x_configuration", { brand: "Twilio" })}
      divider
      primaryAction={{
        content: I18n.t("admin.create_x_account", { brand: "Twilio" }),
        url: "https://www.twilio.com/try-twilio?promo=1CwBKG",
        external: true,
      }}
      secondaryActions={[
        {
        content: I18n.t("integrations.steps_to_add_account", { brand: "Twilio" }),
        url: "https://busy-decision-cb2.notion.site/Steps-to-configure-your-own-Twilio-account-in-COD-King-d54bc669787e4426ad8f36e28f8ff25f",
        external: true,
      },
      ]}
    >
      <BlockStack gap={{ xs: "800", sm: "400" }}>
        <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
          {/* Left Info */}
          <Box
            as="section"
            paddingInlineStart={{ xs: 400, sm: 0 }}
            paddingInlineEnd={{ xs: 400, sm: 0 }}
          >
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("integrations.provider_credentials", { brand: "Twilio" })}
              </Text>
              <Text variant="bodyMd" as="p">
                {I18n.t("integrations.credentials_connect_desc", { brand: "Twilio" })}
              </Text>
            </BlockStack>
          </Box>

          {/* Right Input Form */}
          <Card roundedAbove="sm">
            <BlockStack gap="400">
              {/* {providerConfigurationError && (
                <Banner title={I18n.t("network_settings.config_issue")} tone="critical">
                  <Text variant="bodySm" as="p" breakWord>
                    {providerConfigurationError}
                  </Text>
                </Banner>
              )} */}
              <TextField
                label={I18n.t("integrations.account_sid")}
                value={sid}
                onChange={handleSettingChange("sid")}
                placeholder={I18n.t("twilio.acbhahsah3h1hasdh1h12hdshahadhahsha71")}
                error={fieldError(sid, I18n.t("integrations.account_sid"))}
              />
              <RevealTextField
                label={I18n.t("integrations.auth_token")}
                value={token}
                onChange={handleSettingChange("token")}
                placeholder={I18n.t("twilio.1f0asdas01313sdas0asdasas13asa")}
                type="password"
                error={fieldError(token, I18n.t("integrations.auth_token"))}
              />
              <TextField
                label={I18n.t("integrations.sender_id")}
                value={setting.providerSenderId}
                onChange={handleSettingChange("providerSenderId")}
                placeholder={I18n.t("twilio.13829xxxxxxx")}
                onFocus={() => setShowHelp(true)}
                error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
                helpText={
                  showHelp && (
                    <Link
                      external
                      url="https://www.twilio.com/console/phone-numbers/search?isoCountry=US&types[]=Local&types[]=Tollfree&capabilities[]=Voice&capabilities[]=Sms"
                    >
                      {I18n.t("admin.phone_number")}
                    </Link>
                  )
                }
              />
            </BlockStack>
          </Card>
        </InlineGrid>

        <Divider />
      </BlockStack>
    </Page>
  );
  return (
    <Card
      title={I18n.t("admin.x_configuration", { brand: "Twilio" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "Twilio" }),
          external: true,
          url: "https://www.twilio.com/try-twilio?promo=1CwBKG",
        },
        {
          content: I18n.t("integrations.steps_to_add_account", { brand: "Twilio" }),
          external: true,
          url: "https://busy-decision-cb2.notion.site/Steps-to-configure-your-own-Twilio-account-in-COD-King-d54bc669787e4426ad8f36e28f8ff25f",
        },
      ]}
    >
      <TextField
        label={I18n.t("integrations.account_sid")}
        value={sid}
        onChange={handleSettingChange("sid")}
        placeholder={I18n.t("twilio.acbhahsah3h1hasdh1h12hdshahadhahsha71")}
      />
      <RevealTextField
        label={I18n.t("integrations.auth_token")}
        value={token}
        onChange={handleSettingChange("token")}
        placeholder={I18n.t("twilio.1f0asdas01313sdas0asdasas13asa")}
        type="password"
      />
      <TextField
        label={I18n.t("integrations.sender_id")}
        value={setting.providerSenderId}
        onChange={handleSettingChange("providerSenderId")}
        placeholder={I18n.t("twilio.13829xxxxxxx")}
        onFocus={() => setShowHelp(true)}
        helpText={
          showHelp && (
            <Link
              external
              url="https://www.twilio.com/console/phone-numbers/search?isoCountry=US&types[]=Local&types[]=Tollfree&capabilities[]=Voice&capabilities[]=Sms&searchTerm=&searchFilter=left&searchType=number"
            >
              {I18n.t("admin.phone_number")}
            </Link>
          )
        }
      />
    </Card>
  );
};

export default Twilio;

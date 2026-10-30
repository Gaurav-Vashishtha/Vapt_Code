import React, { useEffect, useContext } from "react";
import {
  Card,
  TextField,
  FormLayout,
  Page,
  Text,
  BlockStack,
  InlineGrid,
  Box,
  Divider,
  Banner,
} from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import I18n from "../../i18n-lang";

const Wavecell = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const sid = setting.providerApiKey?.split(":")[0] ?? "";
  const token = setting.providerApiKey?.split(":")[1] ?? "";

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleSettingChange = (key) => (value) => {
    if (key === "sid") {
      setSetting({
        ...setting,
        providerApiKey: `${value ?? ""}:${token}`,
      });
    } else if (key === "token") {
      setSetting({
        ...setting,
        providerApiKey: `${sid}:${value ?? ""}`,
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
      title={I18n.t("admin.x_configuration", { brand: "Wavecell" })}
      divider
      primaryAction={{
        content: I18n.t("admin.create_x_account", { brand: "Wavecell" }),
        url: "https://8x8.wavecell.com/vid-sms-8x8connect#talk-to-an-expert",
        external: true,
      }}
    >
      <BlockStack gap={{ xs: "800", sm: "400" }}>
        <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
          {/* Info Section */}
          <Box
            as="section"
            paddingInlineStart={{ xs: 400, sm: 0 }}
            paddingInlineEnd={{ xs: 400, sm: 0 }}
          >
            <BlockStack gap="400">
              <Text as="h3" variant="headingMd">
                {I18n.t("integrations.wavecell_credentials")}
              </Text>
              <Text as="p" variant="bodyMd">
                {I18n.t("integrations.wavecell_credentials_desc")}
              </Text>
            </BlockStack>
          </Box>

          {/* Input Form Section */}
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
                label={I18n.t("integrations.sub_account_id")}
                value={sid}
                onChange={handleSettingChange("sid")}
                placeholder={I18n.t("wavecell.shq_321_otaz")}
                error={fieldError(sid, I18n.t("integrations.sub_account_id"))}
              />
              <RevealTextField
                label={I18n.t("integrations.api_key")}
                value={token}
                onChange={handleSettingChange("token")}
                placeholder={I18n.t("wavecell.1f0asdas01313sdas0asdasas13asa")}
                type="password"
                error={fieldError(token, I18n.t("integrations.api_key"))}
              />
              <TextField
                label={I18n.t("integrations.sender_id")}
                value={setting.providerSenderId}
                onChange={handleSettingChange("providerSenderId")}
                placeholder={I18n.t("wavecell.yourbrand")}
                error={fieldError(setting.providerSenderId, I18n.t("integrations.sender_id"))}
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
      title={I18n.t("admin.x_configuration", { brand: "Wavecell" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", { brand: "Wavecell" }),
          external: true,
          url: "https://8x8.wavecell.com/vid-sms-8x8connect#talk-to-an-expert",
        },
      ]}
    >
      <FormLayout>
        <FormLayout.Group>
          <TextField
            label={I18n.t("integrations.sub_account_id")}
            value={sid}
            onChange={handleSettingChange("sid")}
            placeholder={I18n.t("wavecell.shq_321_otaz")}
          />
          <RevealTextField
            label={I18n.t("integrations.api_key")}
            value={token}
            onChange={handleSettingChange("token")}
            placeholder={I18n.t("wavecell.1f0asdas01313sdas0asdasas13asa")}
            type="password"
          />
          <TextField
            label={I18n.t("integrations.sender_id")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder={I18n.t("wavecell.yourbrand")}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default Wavecell;

import React, { useContext, useState } from "react";
import {
  Card,
  TextField,
  FormLayout,
  Button,
  Banner,
  Text,
} from "@shopify/polaris";
import { StoreContext } from "../../Context/Store";
import RevealTextField from "../RevealTextField";
import useApi from "../../Hooks/useApi";
import I18n from "../../i18n-lang";

const Smsshare = ({ providerConfigurationError, showFieldErrors }) => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    twilioPricing,
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);

  const [setup, setSetup] = useState({
    login: "",
    password: "",
  });

  const [setupError, setSetupError] = useState("");

  const [{ loading, error }, requestAccessToken] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/get_sms_share_token`,
      method: "POST",
      data: setup,
    },
    { manual: true }
  );

  const fieldError = (value, label) => {
    if (showFieldErrors && !value?.trim()) return I18n.t("integrations.field_required");
    if (providerConfigurationError && value?.trim()) return I18n.t("integrations.field_check_save", { field: label });
    return undefined;
  };

  const handleSetupChange = (key) => (value) => {
    setSetup({
      ...setup,
      [key]: value,
    });
  };

  const handleSettingChange = (key) => (value) => {
    setSetting({
      ...setting,
      [key]: value,
    });
    !contextualBar && setContextualBar(true);
  };

  const onRequestAccessToken = () => {
    requestAccessToken()
      .then((resp) => {
        if (resp.status === 200 && resp?.data?.token) {
          // setSetup({login: '', password: ''})
          setSetting({
            ...setting,
            providerApiKey: resp.data.token,
          });
          !contextualBar && setContextualBar(true);
        } else {
          setSetupError(resp.data.error);
        }
      })
      .catch((error) => {
        setSetupError(error);
      });
  };

  return (
    <Card
      title={I18n.t("admin.x_configuration", { brand: "ProWebSms (smshare)" })}
      sectioned
      actions={[
        {
          content: I18n.t("admin.create_x_account", {
            brand: "ProWebSms (smshare)",
          }),
          external: true,
          url: "https://www.prowebsms.com/",
        },
      ]}
    >
      {/* {providerConfigurationError && (
        <>
          <Banner title={I18n.t("network_settings.config_issue")} tone="critical">
            <Text variant="bodySm" as="p" breakWord>
              {providerConfigurationError}
            </Text>
          </Banner>
          <br />
        </>
      )} */}
      {(error || setupError) && (
        <>
          <Banner
            title={I18n.t("admin.bulk_processing_error")}
            status="critical"
          >
            <p>{setupError || I18n.t("admin.something_went_wrong")}</p>
          </Banner>
          <br />
        </>
      )}
      <FormLayout>
        <FormLayout.Group>
          <TextField
            label={I18n.t("integrations.login_id")}
            value={setup.login}
            onChange={handleSetupChange("login")}
            error={fieldError(setup.login, I18n.t("integrations.login_id"))}
          />
          <RevealTextField
            label={I18n.t("integrations.password")}
            value={setup.password}
            onChange={handleSetupChange("password")}
            type="password"
            error={fieldError(setup.password, I18n.t("integrations.password"))}
          />
          <Button loading={loading} onClick={onRequestAccessToken}>
            {I18n.t("admin.get_access_token")}
          </Button>
        </FormLayout.Group>
        <FormLayout.Group>
          <TextField
            label={I18n.t("integrations.access_token")}
            value={setting.providerApiKey}
            onChange={handleSettingChange("providerApiKey")}
            placeholder={I18n.t("smsshare.1f0asdas01313sdas0asdasas13asa")}
            type="text"
            error={fieldError(setting.providerApiKey, I18n.t("integrations.access_token"))}
          />
          <TextField
            label={I18n.t("integrations.gateway_uuid")}
            value={setting.providerSenderId}
            onChange={handleSettingChange("providerSenderId")}
            placeholder={I18n.t("smsshare.1f0asdas01313sdas0asdasas13asa")}
            type="text"
            error={fieldError(setting.providerSenderId, I18n.t("integrations.gateway_uuid"))}
          />
        </FormLayout.Group>
      </FormLayout>
    </Card>
  );
};

export default Smsshare;

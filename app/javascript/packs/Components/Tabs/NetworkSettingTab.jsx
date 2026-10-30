import React, {
  useContext,
  useEffect,
  useRef,
  useState,
  useCallback,
} from "react";
import {
  Layout,
  Card,
  FormLayout,
  Select,
  Icon,
  Text,
  Link,
  BlockStack,
  InlineStack,
  Box,
  Divider,
  Page,
  Banner,
  List,
  Button,
  TextField,
  Badge,
} from "@shopify/polaris";
// 1. Correct Import for App Bridge v4
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  CircleInformationMajor,
  PaymentsMajor,
} from "@shopify/polaris-icons";
import I18n from "../../i18n-lang";
import FeatureCallout from "../FeatureCallout";

const LOCAL_SMS_GATEWAY_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.15_PM.jpg?v=1791392724";
import useApi from "../../Hooks/useApi";
import Api from "../../Services/Api.js";
import Twilio from "../Integrations/Twilio";
import Wavecell from "../Integrations/Wavecell";
import ChatApi from "../Integrations/ChatApi";
import SmsShare from "../Integrations/Smsshare";
import Veevotech from "../Integrations/Veevotech";
import BrandedSms from "../Integrations/Brandedsms";
import Ismart from "../Integrations/Ismart";
import Winsms from "../Integrations/Winsms";
import Esms from "../Integrations/Esms";
import PalPigeon from "../Integrations/PalPigeon";
import Movider from "../Integrations/Movider";
import ThaiBulkSMS from "../Integrations/ThaiBulkSMS";
import Boomcast from "../Integrations/Boomcast";
import SmsMisr from "../Integrations/SmsMisr";
import { StoreContext } from "../../Context/Store";
import { navigateTo } from "../../../utils/navigate";
import BulkSmsBd from "../Integrations/BulkSmsBd";

const providers = [
  { get label() {
      return I18n.t("network_setting_tab.cod_king");
    }, value: "" },
  { get label() {
      return I18n.t("network_setting_tab.twilio_global");
    }, value: "SmsServices::TwilioSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.wavecell_global");
    }, value: "SmsServices::WavecellSmsService" },
  {
    get label() {
      return I18n.t("network_setting_tab.chat_api_whatsapp_global");
    },
    value: "WhatsappServices::ChatapiWhatsappService",
  },
  {
    get label() {
      return I18n.t("network_setting_tab.prowebsms_smshare_global");
    },
    value: "SmsServices::SmsshareSmsService",
  },
  { get label() {
      return I18n.t("network_setting_tab.veevotech_pakistan");
    }, value: "SmsServices::VeevotechSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.branded_sms_pakistan");
    }, value: "SmsServices::BrandedSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.ismart_oman");
    }, value: "SmsServices::IsmartSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.winsmspro_tunisia");
    }, value: "SmsServices::WinsmsproSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.esms_vietnam");
    }, value: "SmsServices::ESmsService" },
  { get label() {
      return I18n.t("network_setting_tab.palpigeon_turkey");
    }, value: "SmsServices::PalPigeonSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.movider_philippines");
    }, value: "SmsServices::MoviderSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.boomcast_bangladesh");
    }, value: "SmsServices::BoomcastSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.smsmisr_egypt");
    }, value: "SmsServices::MisrSmsService" },
  { get label() {
      return I18n.t("network_setting_tab.thaibulksms_thailand");
    }, value: "SmsServices::ThaiSmsService" },
  {
    get label() {
      return I18n.t("network_setting_tab.bulksmsbdservice_bangladesh");
    },
    value: "SmsServices::BulkSmsBdService",
  },
];

const integrationsMap = {
  "SmsServices::TwilioSmsService": Twilio,
  "SmsServices::WavecellSmsService": Wavecell,
  "WhatsappServices::ChatapiWhatsappService": ChatApi,
  "SmsServices::SmsshareSmsService": SmsShare,
  "SmsServices::VeevotechSmsService": Veevotech,
  "SmsServices::BrandedSmsService": BrandedSms,
  "SmsServices::IsmartSmsService": Ismart,
  "SmsServices::WinsmsproSmsService": Winsms,
  "SmsServices::ESmsService": Esms,
  "SmsServices::PalPigeonSmsService": PalPigeon,
  "SmsServices::MoviderSmsService": Movider,
  "SmsServices::BoomcastSmsService": Boomcast,
  "SmsServices::MisrSmsService": SmsMisr,
  "SmsServices::ThaiSmsService": ThaiBulkSMS,
  "SmsServices::BulkSmsBdService": BulkSmsBd,
};

const NetworkSettingTab = () => {
  const shopify = useAppBridge(); // Initialize App Bridge v4
  const settingRef = useRef();
  const [testPhone, setTestPhone] = useState("");
  const [testPhoneError, setTestPhoneError] = useState("");
  const [testSmsLoading, setTestSmsLoading] = useState(false);
  const [showFieldErrors, setShowFieldErrors] = useState(false);
  const [providerConfigurationError, setProviderConfigurationError] =
    useState("");
  const [testSmsBanner, setTestSmsBanner] = useState({
    active: false,
    status: "info",
    text: "",
  });
  const [localProviders, setLocalProviders] = useState([]);
  const [loadingLocalProviders, setLoadingLocalProviders] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  const {
    contextualBar: [contextualBar, setContextualBar],
    plan: [plan],
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
  } = useContext(StoreContext);

  const [isDirty, setIsDirty] = useState(false);

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  const planNameForPremium = plan?.name?.toLowerCase() || "";
  const isPremiumOrEnterprise = /premium|enterprise|india_budget/i.test(
    planNameForPremium,
  );

  const [{}, saveSettings] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings`,
      method: "POST",
    },
    { manual: true },
  );

  const extractResponseMessage = (response) => {
    if (typeof response === "string") {
      return response;
    }
    if (typeof response === "object" && response !== null) {
      if (response.sid) {
        return I18n.t("network_settings_missing.sms_sent_success", {
          sid: response.sid,
        });
      }
      if (response.table && response.table.sid) {
        return I18n.t("network_settings_missing.sms_sent_success", {
          sid: response.table.sid,
        });
      }
      try {
        return JSON.stringify(response, null, 2);
      } catch (e) {
        return I18n.t("network_settings_missing.test_sms_completed");
      }
    }
    return I18n.t("network_settings_missing.test_sms_completed");
  };

  const extractProviderConfigurationError = (
    response,
    fallbackMessage = "",
  ) => {
    const extractFromText = (text) => {
      if (!text) return "";
      const doubleQuoteMatch = text.match(/"error"\s*:\s*"([^"]+)"/i);
      if (doubleQuoteMatch?.[1]) return doubleQuoteMatch[1];
      const singleQuoteMatch = text.match(/'error'\s*:\s*'([^']+)'/i);
      if (singleQuoteMatch?.[1]) return singleQuoteMatch[1];
      return text;
    };

    if (typeof response === "string" && response.trim() !== "") {
      return extractFromText(response.trim());
    }
    if (typeof response === "object" && response !== null) {
      if (typeof response.error === "string" && response.error.trim() !== "") {
        return extractFromText(response.error.trim());
      }
      if (
        response.table &&
        typeof response.table.error === "string" &&
        response.table.error.trim() !== ""
      ) {
        return extractFromText(response.table.error.trim());
      }
    }
    if (fallbackMessage && fallbackMessage.trim() !== "") {
      return extractFromText(fallbackMessage.trim());
    }
    return I18n.t("admin.something_went_wrong");
  };

  const isErrorResponse = (response, messageText) => {
    // If it's a string, check for error keywords
    if (typeof response === "string") {
      const lowerResponse = response.toLowerCase();
      return (
        lowerResponse.includes("missing") ||
        lowerResponse.includes("error") ||
        lowerResponse.includes("fail") ||
        lowerResponse.includes("invalid") ||
        lowerResponse.includes("authentication") ||
        lowerResponse.includes("unauthorized")
      );
    }
    // If it's an object, check for error indicators
    if (typeof response === "object" && response !== null) {
      // Direct error field
      if (response.error) return true;
      // Nested error in table
      if (response.table && response.table.error) return true;
      // No sid usually means error
      if (response.table && response.table.sid === null) return true;
    }
    // Check the extracted message text
    if (messageText) {
      const lowerMessage = messageText.toLowerCase();
      return (
        lowerMessage.includes("missing") ||
        lowerMessage.includes("error") ||
        lowerMessage.includes("fail") ||
        lowerMessage.includes("invalid") ||
        lowerMessage.includes("authentication") ||
        lowerMessage.includes("unauthorized")
      );
    }
    return false;
  };

  const handleSettingChange = (key) => (value) => {
    setSetting({
      ...setting,
      [key]: value,
    });
    if (!contextualBar) setContextualBar(true);
  };

  const handleSubmit = async () => {
    setIsSaving(true);
    try {
      const resp = await saveSettings({ data: settingRef.current });
      if (resp?.status === 200) {
        setIsDirty(false);
        setContextualBar(false);
        // Update setting from response if available
        if (resp.data) {
          setSetting(resp.data);
          setOriginalSetting(resp.data);
        } else {
          setOriginalSetting(settingRef.current);
        }
        shopify.toast.show(I18n.t("admin.settings_saved"));
      }
    } catch (e) {
      shopify.toast.show(I18n.t("admin.something_went_wrong"), {
        isError: true,
      });
    } finally {
      setIsSaving(false);
    }
  };

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setIsDirty(false);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  const handleTestSms = async () => {
    // Clear previous banner
    setTestSmsBanner({ active: false, status: "info", text: "" });
    setProviderConfigurationError("");
    setShowFieldErrors(true);
    if (!testPhone || testPhone.trim() === "") {
      setTestPhoneError(I18n.t("network_settings.enter_phone_to_test"));
      return;
    }
    setTestPhoneError("");

    setTestSmsLoading(true);
    Api.post("/settings/test_operator_sms", {
      phone: testPhone,
      provider: setting.provider,
    })
      .then((res) => {
        console.log("Test SMS Response:", res.data);
        const responseData = res.data.response;
        const messageText = extractResponseMessage(responseData);
        const hasError = isErrorResponse(responseData, messageText);
        if (hasError) {
          setProviderConfigurationError(
            extractProviderConfigurationError(responseData, messageText),
          );
          setTestSmsBanner({ active: false, status: "info", text: "" });
        } else {
          setTestSmsBanner({
            active: true,
            status: hasError ? "critical" : "success",
            text: messageText,
          });
        }
        // Clear phone number only on success
        if (!hasError) {
          setTestPhone("");
        }
      })
      .catch((error) => {
        console.error("Test SMS error:", error);
        // Try to extract error message from response
        const errorResponse = error.response?.data?.response;
        const errorMessage = errorResponse
          ? extractResponseMessage(errorResponse)
          : I18n.t("network_settings_missing.error_sending_test_sms");
        setProviderConfigurationError(
          extractProviderConfigurationError(errorResponse, errorMessage),
        );
        setTestSmsBanner({ active: false, status: "info", text: "" });
      })
      .finally(() => {
        setTestSmsLoading(false);
      });
  };

  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  useEffect(() => {
    setProviderConfigurationError("");
    setShowFieldErrors(false);
  }, [setting.provider]);

  useEffect(() => {
    if (providerConfigurationError) {
      const section = document.getElementById("provider-configuration-section");
      section?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }, [providerConfigurationError]);

  useEffect(() => {
    if (!shop?.country_code) return;
    setLoadingLocalProviders(true);
    Api.get("/settings/local_providers", {
      params: { country_code: shop.country_code },
    })
      .then((response) => {
        const providers =
          response?.data?.providers || response?.providers || [];
        setLocalProviders(providers);
        setLoadingLocalProviders(false);
      })
      .catch((error) => {
        console.error("[LOCAL_PROVIDERS] Load failed:", error);
        setLocalProviders([]);
        setLoadingLocalProviders(false);
      });
  }, [shop?.country_code]);

  const hasSelectedProvider = setting.provider && setting.provider !== "";
  const planNameForCheck = plan?.name?.toLowerCase() || "";
  const isEnterpriseOrIndiaBudget =
    planNameForCheck.includes("enterprise") ||
    planNameForCheck.includes("india_budget");
  const hasLocalProviders = localProviders.length > 0;
  const showUpgradeBanner = hasLocalProviders && !isEnterpriseOrIndiaBudget;

  const selectedIntegration = (() => {
    if (!hasSelectedProvider) return null;
    const SelectedIntegration = integrationsMap[setting.provider];
    if (!SelectedIntegration) return null;
    return (
      <SelectedIntegration
        providerConfigurationError={providerConfigurationError}
        showFieldErrors={showFieldErrors}
      />
    );
  })();

  return (
    <Page
      title={I18n.t("network_settings.page_title")}
      subtitle={I18n.t("network_settings.page_subtitle")}
      fullWidth={true}
    >
      {/* 2. Declarative SaveBar Component */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={isSaving ? "" : undefined}
          disabled={isSaving}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          <FeatureCallout
            illustration="widget"
            image={LOCAL_SMS_GATEWAY_CALLOUT_IMAGE}
            title={I18n.t("network_settings.page_title")}
            description={I18n.t("network_settings.page_subtitle")}
            docsUrl="https://codking.tech/documentation/"
            showChat
          />
        </Layout.Section>

        {/* The pricing pitch that used to head this banner is gone: the
            callout above introduces the feature, and the pitch repeated it.
            What is left is the part a merchant acts on. */}
        {showUpgradeBanner && (
          <Layout.Section>
            <Banner
              title={I18n.t(
                "network_settings_missing.recommended_local_providers",
                { country: shop?.country_name || shop?.country_code },
              )}
              tone="info"
              icon={CircleInformationMajor}
            >
              <BlockStack gap="200">
                <List type="bullet">
                  {localProviders.map((provider, index) => (
                    <List.Item key={index}>
                      <Text variant="bodyMd" fontWeight="medium">
                        {provider.label}
                        {provider.supported_countries &&
                          provider.supported_countries.length > 0 && (
                            <Text variant="bodySm" tone="subdued" as="span">
                              {" "}
                              ({provider.supported_countries.join(", ")})
                            </Text>
                          )}
                      </Text>
                    </List.Item>
                  ))}
                </List>
                <Text variant="bodyMd" as="p" tone="subdued">
                  {I18n.t("network_settings_missing.upgrade_description")}
                </Text>
                <Box paddingBlockStart="200">
                  <Button
                    variant="primary"
                    onClick={() => navigateTo("/subscription")}
                  >
                    {I18n.t("network_settings_missing.upgrade_to_enterprise")}
                  </Button>
                </Box>
              </BlockStack>
            </Banner>
          </Layout.Section>
        )}

        {/* Provider Selection */}
        <Layout.Section>
          <Card>
            <BlockStack gap="400">
              <BlockStack gap="200">
                <Text variant="headingMd" as="h2">
                  {I18n.t("admin.network_provider_integration")}
                </Text>
                <Text variant="bodySm" as="p" tone="subdued">
                  {I18n.t("network_settings.available_all_regions")}
                </Text>
              </BlockStack>
              <Divider />
              <FormLayout>
                <Select
                  label={I18n.t("admin.network_provider")}
                  options={providers}
                  onChange={handleSettingChange("provider")}
                  value={setting.provider || ""}
                  helpText={I18n.t("network_settings.select_operator_help")}
                />

                {hasSelectedProvider && (
                  <Box
                    padding="600"
                    background="bg-surface-secondary"
                    borderRadius="200"
                  >
                    <BlockStack gap="300">
                      <InlineStack gap="200" blockAlign="center">
                        <Icon source={PaymentsMajor} tone="base" />
                        <Text variant="headingSm" as="h3">
                          {I18n.t("network_settings.billing_structure")}
                        </Text>
                      </InlineStack>
                      <List type="bullet">
                        <List.Item>
                          <Text variant="bodySm" as="span">
                            <Text
                              variant="bodySm"
                              as="span"
                              fontWeight="semibold"
                            >
                              {I18n.t("network_settings.sms_charges")}
                            </Text>{" "}
                            {I18n.t("network_settings.billed_by_operator", {
                              operator:
                                providers.find(
                                  (p) => p.value === setting.provider,
                                )?.label || "the operator",
                            })}
                          </Text>
                        </List.Item>
                        <List.Item>
                          <Text variant="bodySm" as="span">
                            <Text
                              variant="bodySm"
                              as="span"
                              fontWeight="semibold"
                            >
                              {I18n.t("network_settings.cod_king_subscription")}
                            </Text>{" "}
                            {I18n.t("network_settings.separate_fee")}
                          </Text>
                        </List.Item>
                        <List.Item>
                          <Text variant="bodySm" as="span">
                            <Text
                              variant="bodySm"
                              as="span"
                              fontWeight="semibold"
                            >
                              {I18n.t("network_settings.benefit")}
                            </Text>{" "}
                            {I18n.t("network_settings.no_hidden_markups")}
                          </Text>
                        </List.Item>
                      </List>
                    </BlockStack>
                  </Box>
                )}

                {!isPremiumOrEnterprise && hasSelectedProvider ? (
                  <>
                    <Banner
                      title={I18n.t("network_settings.enterprise_required")}
                      tone="warning"
                    >
                      <Text variant="bodySm" as="p">
                        {I18n.t("network_settings.direct_operator_available")}{" "}
                        <Link onClick={() => navigateTo("/subscription")}>
                          {" "}
                          {I18n.t("network_settings.upgrade_now")}
                        </Link>{" "}
                        {I18n.t("network_settings.unlock_feature")}
                      </Text>
                    </Banner>
                    <Box opacity={0.5} pointerEvents="none">
                      <div id="provider-configuration-section">
                        {selectedIntegration}
                      </div>
                    </Box>
                  </>
                ) : (
                  <div id="provider-configuration-section">
                    {selectedIntegration}
                  </div>
                )}
              </FormLayout>
            </BlockStack>
          </Card>
        </Layout.Section>

        {/* Test SMS Section */}
        {hasSelectedProvider && isPremiumOrEnterprise && (
          <Layout.Section>
            <Card>
              <BlockStack gap="400">
                <BlockStack gap="200">
                  <Text variant="headingMd" as="h2">
                    {I18n.t("network_settings.test_integration")}
                  </Text>
                  <Text variant="bodySm" as="p" tone="subdued">
                    {I18n.t("network_settings.test_integration_desc")}
                  </Text>
                </BlockStack>
                <Divider />
                {/* Test SMS Response Banner */}
                {testSmsBanner.active && (
                  <Banner
                    title={
                      testSmsBanner.status === "success"
                        ? I18n.t("network_settings.test_sms_success")
                        : testSmsBanner.status === "warning"
                          ? I18n.t("network_settings.config_issue")
                          : I18n.t("network_settings.test_failed")
                    }
                    tone={testSmsBanner.status}
                    onDismiss={() =>
                      setTestSmsBanner({
                        active: false,
                        status: "info",
                        text: "",
                      })
                    }
                  >
                    <Box>
                      <Text variant="bodySm" as="p" breakWord>
                        {testSmsBanner.text}
                      </Text>
                    </Box>
                  </Banner>
                )}
                <FormLayout>
                  <TextField
                    label={I18n.t("network_settings.phone_number")}
                    type="tel"
                    value={testPhone}
                    onChange={(value) => {
                      setTestPhone(value);
                      if (testPhoneError) {
                        setTestPhoneError("");
                      }
                    }}
                    placeholder="+1234567890"
                    helpText={I18n.t("network_settings.enter_phone_help")}
                    autoComplete="tel"
                    error={testPhoneError || undefined}
                  />
                  <InlineStack gap="300">
                    <Button
                      variant="primary"
                      onClick={handleTestSms}
                      loading={testSmsLoading}
                      disabled={!testPhone || testPhone.trim() === ""}
                    >
                      {I18n.t("network_settings.send_test_sms")}
                    </Button>
                    {testPhone && (
                      <Button
                        onClick={() => {
                          setTestPhone("");
                          setTestPhoneError("");
                        }}
                        disabled={testSmsLoading}
                      >
                        {I18n.t("network_settings.clear")}
                      </Button>
                    )}
                  </InlineStack>
                </FormLayout>
                <Box
                  padding="300"
                  background="bg-surface-secondary"
                  borderRadius="200"
                >
                  <BlockStack gap="200">
                    <Text variant="bodySm" as="p" fontWeight="semibold">
                      {I18n.t("network_settings_detail.testing_tips")}
                    </Text>
                    <List type="bullet">
                      <List.Item>
                        <Text variant="bodySm" as="span">
                          {I18n.t(
                            "network_settings_detail.ensure_credentials_saved",
                          )}
                        </Text>
                      </List.Item>
                      <List.Item>
                        <Text variant="bodySm" as="span">
                          {I18n.t("network_settings_detail.use_valid_number")}
                        </Text>
                      </List.Item>
                      <List.Item>
                        <Text variant="bodySm" as="span">
                          {I18n.t("network_settings_detail.check_balance")}
                        </Text>
                      </List.Item>
                    </List>
                  </BlockStack>
                </Box>
              </BlockStack>
            </Card>
          </Layout.Section>
        )}

        {/* Next Steps Section */}
        {hasSelectedProvider && isPremiumOrEnterprise && (
          <Layout.Section>
            <Card>
              <BlockStack gap="300">
                <Text variant="headingSm" as="h3">
                  {I18n.t("network_settings_missing.next_steps")}
                </Text>
                <List type="number">
                  <List.Item>
                    {I18n.t("network_settings_detail.configure_credentials")}
                  </List.Item>
                  <List.Item>
                    {I18n.t("network_settings_detail.test_integration")}
                  </List.Item>
                  <List.Item>
                    {I18n.t("network_settings_detail.create_account", {
                      operator:
                        providers.find((p) => p.value === setting.provider)
                          ?.label || "the operator",
                    })}
                  </List.Item>
                  <List.Item>
                    {I18n.t("network_settings_detail.monitor_usage")}
                  </List.Item>
                </List>
                <Box paddingBlockStart="200">
                  <Text variant="bodySm" as="p" tone="subdued">
                    {I18n.t("network_settings_detail.need_help_contact")}
                  </Text>
                </Box>
              </BlockStack>
            </Card>
          </Layout.Section>
        )}
      </Layout>
    </Page>
  );
};

export default NetworkSettingTab;

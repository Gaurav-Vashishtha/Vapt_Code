import React, {
  useState,
  useCallback,
  useContext,
  useEffect,
  useRef,
} from "react";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  Page,
  Layout,
  Card,
  Button,
  Checkbox,
  Select,
  TextField,
  Icon,
  Text,
  Box,
  BlockStack,
  InlineStack,
  Banner,
  Badge,
  Divider,
  Spinner,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import {
  ExternalMinor,
} from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import I18n from "../i18n-lang";
import useApi from "../Hooks/useApi";
import StepProgress from "./StepProgress";
import PostOrderOTPWizard from "./PostOrderOTPWizard";
import FreeWalletBalance from "./FreeWalletBalance";
import QuickBilling from "./QuickBilling";
import FeatureCallout from "./FeatureCallout";
import { SectionCard, SettingRow } from "./SettingsPrimitives";
import QuickCurrentStep from "./QuickCurrentStep";
import { hasNoChargeId } from "../utils/shopUtils";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import styled from "styled-components";

// Shown in the callout panel at 290x210.
const POST_ORDER_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-10_at_12.44.26_PM.jpg?v=1789024842";

/* Fields on the left, the sample beside them — no card around the preview, and
   it follows the fields down while there is room. */
const OtpFormGrid = styled.div`
  display: grid;
  grid-template-columns: minmax(0, 1fr) 340px;
  gap: 24px;
  align-items: start;

  @media (max-width: 900px) {
    grid-template-columns: minmax(0, 1fr);
  }
`;

const OtpFormPreview = styled.div`
  position: sticky;
  top: 16px;

  @media (max-width: 900px) {
    position: static;
    order: -1;
    max-width: 340px;
  }
`;

const Settings = ({ onBackToSettings, isOnboardingFlow }) => {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    contextualBar: [contextualBar, setContextualBar],
    loading: [loading, setLoading],
    banner: [, setBanner],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  // State management
  const [isDirty, setIsDirty] = useState(false);
  const [inlineError, setInlineError] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isCheckingTheme, setIsCheckingTheme] = useState(false);
  const [themeCheckInterval, setThemeCheckInterval] = useState(null);
  const [isExtensionEnabled, setIsExtensionEnabled] = useState(false);
  const [onBoardingFlow, setOnBoardingFlow] = useState(!!isOnboardingFlow);
  const checkCountRef = useRef(0);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // Profile API
  const [{ data: profileData }, getCheckoutProfile] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/get_published_checkout_profile`,
      method: "GET",
    },
    { manual: true }
  );

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  // Function to check theme integration status
  const checkThemeIntegration = useCallback(async () => {
    try {
      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shop.shopify_domain}`
      );
      const data = await response.json();
      if (data.assetEnabled !== isExtensionEnabled) {
        setIsExtensionEnabled(data.assetEnabled);
        if (data.assetEnabled) {
          setIsCheckingTheme(false);
          if (themeCheckInterval) {
            clearInterval(themeCheckInterval);
            setThemeCheckInterval(null);
          }
        }
      }
      return data.assetEnabled;
    } catch (error) {
      console.error("Error checking theme integration:", error);
      return false;
    }
  }, [shop.shopify_domain, isExtensionEnabled, setBanner, themeCheckInterval]);

  // Start monitoring theme integration after user clicks the theme button
  const startThemeMonitoring = useCallback(() => {
    setIsCheckingTheme(true);
    checkCountRef.current = 0;
    const interval = setInterval(async () => {
      checkCountRef.current += 1;
      const isEnabled = await checkThemeIntegration();
      // Stop checking after 2 minutes (24 checks at 5-second intervals) or if enabled
      if (isEnabled || checkCountRef.current >= 24) {
        clearInterval(interval);
        setThemeCheckInterval(null);
        setIsCheckingTheme(false);
        if (!isEnabled && checkCountRef.current >= 24) {
          setBanner({
            active: true,
            status: "info",
            text: I18n.t("pre_order.still_waiting_theme"),
          });
        }
      }
    }, 5000); // Check every 5 seconds
    setThemeCheckInterval(interval);
  }, [checkThemeIntegration, setBanner]);

  // Settings change handler
  const handleSettingChange = (key) => (value) => {
    if (key === "retry" || key === "autoCancel") {
      value = parseInt(value);
    }
    if (key === "retry" && value > setting.autoCancel) {
      setInlineError(I18n.t("settings_detail.retry_time_error"));
      value = setting.autoCancel;
      return;
    } else {
      setInlineError("");
    }
    setSetting({
      ...setting,
      [key]: value,
    });
    !isDirty && setIsDirty(true);
    if (!contextualBar) setContextualBar(true);
  };

  // Initial data fetch
  useEffect(() => {
    Promise.all([checkThemeIntegration(), getCheckoutProfile()]).finally(() => {
      setIsLoading(false);

      // Track page load if in onboarding flow
      if (onBoardingFlow) {
        journeyTracker.trackPageLoad({
          step: 2,
          feature: "post-order-otp",
          isOnboardingFlow: true,
        });
      }
    });
  }, [checkThemeIntegration, getCheckoutProfile, onBoardingFlow]);

  // Cleanup interval on unmount
  useEffect(() => {
    return () => {
      if (themeCheckInterval) {
        clearInterval(themeCheckInterval);
      }
    };
  }, [themeCheckInterval]);

  // Handle theme integration button click
  const handleThemeIntegrationClick = () => {
    // Track theme integration click
    journeyTracker.trackButtonClick("theme_integration", {
      step: 2,
      feature: "post-order-otp",
      isOnboardingFlow: onBoardingFlow,
      shopDomain: shop.shopify_domain,
    });

    startThemeMonitoring();
    window.open(
      `https://${shop.shopify_domain}/admin/themes/current/editor?context=apps&template=order-status&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`,
      "_blank"
    );
  };

  // API options
  const options = [
    { label: I18n.t("admin.dont_send"), value: -1 },
    { label: I18n.t("admin.5_minutes"), value: 5 },
    { label: I18n.t("admin.15_minutes"), value: 15 },
    { label: I18n.t("admin.30_minutes"), value: 30 },
    { label: I18n.t("admin.60_minutes"), value: 60 },
    { label: I18n.t("admin.24_hours"), value: 1440 },
  ];

  // Submit handler
  const handleSubmit = useCallback(() => {
    if (inlineError) return;
    setLoading(true);
    Api.post("/settings", { setting })
      .then((res) => {
        setSetting(res.data);
        setOriginalSetting(res.data);
        setIsDirty(false);
        setContextualBar(false);
        shopify.toast.show(I18n.t("admin.settings_saved"));
        setBanner({
          active: true,
          status: "success",
          text: I18n.t("admin.settings_saved"),
        });
      })
      .catch(() => {
        setIsDirty(true);
        setContextualBar(false);
        setLoading(true);
        shopify.toast.show(I18n.t("admin.settings_error"), { isError: true });
        setBanner({
          active: true,
          status: "critical",
          text: I18n.t("admin.settings_error"),
        });
      })
      .finally(() => {
        setLoading(false);
        setContextualBar(false);
        setIsDirty(false);
      });
  }, [
    setting,
    inlineError,
    setSetting,
    setOriginalSetting,
    setBanner,
    setContextualBar,
    shopify,
  ]);

  const handleDiscard = useCallback(() => {
    setSetting(JSON.parse(JSON.stringify(originalSetting)));
    setIsDirty(false);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  // Render functions
  // The callout introduces the feature; turning it on is a decision of its own,
  // so it gets its own row rather than riding on the illustration card.
  const renderOtpActivationCard = () => (
    <SectionCard>
      <SettingRow
        title={I18n.t("post_order.activate_otp_verification")}
        description={I18n.t("post_order.activate_otp_help")}
        control={
          <Checkbox
            label={I18n.t("post_order.activate_otp_verification")}
            labelHidden
            checked={setting.sms || false}
            onChange={handleSettingChange("sms")}
          />
        }
      />
    </SectionCard>
  );

  const renderActivateTab = () => (
    <BlockStack gap="400">
      {/* Theme setup: the OTP box has to be added to the thank-you page. */}
      {setting.sms && (
        <Card>
          <Box padding="300">
            <BlockStack gap="300">
              <InlineStack align="space-between" blockAlign="center">
                <InlineStack gap="200" blockAlign="center">
                  <div>
                    <Text variant="headingMd" as="h3">
                      {I18n.t("post_order.boost_performance")}
                    </Text>
                    {/* <Text variant="bodyMd" tone="subdued">
                      {setting.isCheckoutDone
                        ? I18n.t("post_order.done_this")
                        : I18n.t("post_order.boost_performance")}
                    </Text> */}
                  </div>
                </InlineStack>
                <Badge tone="info">{I18n.t("admin.required")}</Badge>
              </InlineStack>
              {/* <Box paddingBlockStart="200">
                <Checkbox
                  label={
                    <span
                      dangerouslySetInnerHTML={{
                        __html: I18n.t("post_order.done_this"),
                      }}
                    />
                  }
                  checked={setting.isCheckoutDone || false}
                  onChange={handleSettingChange("isCheckoutDone")}
                />
              </Box> */}
              <Box paddingBlockStart="200">
                <Text variant="headingMd" as="h4">
                  {I18n.t("post_order.setup_guide")}
                </Text>
                <Box paddingBlockStart="100">
                  <PostOrderOTPWizard />
                </Box>
              </Box>
            </BlockStack>
          </Box>
        </Card>
      )}
    </BlockStack>
  );

  const renderOtpFaq = () => (
    <Card padding="600">
      <BlockStack gap="400">
        <Text variant="headingMd" as="h3">
          {I18n.t("post_order.faq_title")}
        </Text>
        <BlockStack gap="300">
          <BlockStack gap="100">
            <Text variant="headingSm" as="h4">
              {I18n.t("post_order.faq_q1")}
            </Text>
            <Text variant="bodyMd" tone="subdued" as="p">
              {I18n.t("post_order.faq_a1")}
            </Text>
          </BlockStack>
          <BlockStack gap="100">
            <Text variant="headingSm" as="h4">
              {I18n.t("post_order.faq_q2")}
            </Text>
            <Text variant="bodyMd" tone="subdued" as="p">
              {I18n.t("post_order.faq_a2")}
            </Text>
          </BlockStack>
        </BlockStack>
      </BlockStack>
    </Card>
  );

  const renderOtpFormSettings = () => (
    <BlockStack gap="400">
      <OtpFormGrid>
        {/* Two cards rather than one: Built for Shopify allows five fields
            in a card, and the wording for this form runs to nine. */}
        <BlockStack gap="400">
          <Card padding="600">
            <BlockStack gap="400">
              <BlockStack gap="100">
                <Text variant="headingMd" as="h3">
                  {I18n.t("post_order.configure_heading")}
                </Text>
                <Text variant="bodyMd" tone="subdued" as="p">
                  {I18n.t("post_order.configure_description")}
                </Text>
              </BlockStack>
              <TextField
                label={I18n.t("post_order.otp_box_heading_text")}
                value={setting.otpExtHeading || ""}
                onChange={handleSettingChange("otpExtHeading")}
                placeholder={I18n.t("post_order.otp_box_heading_text")}
              />
              <TextField
                label={I18n.t("post_order.otp_sent_text")}
                value={setting.otpExtEnterOtpSentOn || ""}
                onChange={handleSettingChange("otpExtEnterOtpSentOn")}
                placeholder={I18n.t("post_order.otp_sent_text")}
              />
              <TextField
                label={I18n.t("post_order.sending_otp_text")}
                value={setting.otpExtSendingOtp || ""}
                onChange={handleSettingChange("otpExtSendingOtp")}
                placeholder={I18n.t("post_order.sending_otp_text")}
              />
              <TextField
                label={I18n.t("post_order.resend_otp_text")}
                value={setting.otpExtResendOtpIn || ""}
                onChange={handleSettingChange("otpExtResendOtpIn")}
                placeholder={I18n.t("post_order.resend_otp_text")}
              />
              <TextField
                label={I18n.t("pre_order.whatsapp_button_text")}
                value={setting.otpExtGetCodeInWhatsapp || ""}
                onChange={handleSettingChange("otpExtGetCodeInWhatsapp")}
                placeholder={I18n.t("pre_order.whatsapp_button_text")}
              />
            </BlockStack>
          </Card>

          <Card padding="600">
            <BlockStack gap="400">
              <Text variant="headingMd" as="h3">
                {I18n.t("post_order.configure_buttons_heading", {
                  defaultValue: "Buttons and confirmation",
                })}
              </Text>
              <TextField
                label={I18n.t("post_order.verify_button_text")}
                value={setting.otpExtVerifyOtp || ""}
                onChange={handleSettingChange("otpExtVerifyOtp")}
                placeholder={I18n.t("post_order.verify_button_text")}
              />
              <TextField
                label={I18n.t("post_order.successful_text")}
                value={setting.otpExtSuccessful || ""}
                onChange={handleSettingChange("otpExtSuccessful")}
                placeholder={I18n.t("post_order.successful_text")}
              />
              <TextField
                label={I18n.t("post_order.change_button_text")}
                value={setting.otpExtChange || ""}
                onChange={handleSettingChange("otpExtChange")}
                placeholder={I18n.t("post_order.change_button_text")}
              />
              <TextField
                label={I18n.t("post_order.submit_button_text")}
                value={setting.otpExtSubmit || ""}
                onChange={handleSettingChange("otpExtSubmit")}
                placeholder={I18n.t("post_order.submit_button_text")}
              />
            </BlockStack>
          </Card>
          {/* The cards below the form share its column, so every card keeps
              the form's width instead of widening once the preview ends. */}
          {renderOtpAdvancedSettings()}
          {setting.sms && renderOtpFaq()}
        </BlockStack>

        <OtpFormPreview>
          <Card padding="400">
              <BlockStack gap="200">
                <Text variant="bodySm" tone="subdued" as="p">
                  {I18n.t("post_order.sample_preview")}
                </Text>
                {/* Drawn from the settings beside it rather than a screenshot,
                    so it stays sharp and updates as the fields are edited. */}
                <div
                  style={{
                    border: "1px solid #e3e3e3",
                    borderRadius: 10,
                    background: "#f6f6f7",
                    padding: 16,
                    fontSize: 14,
                    lineHeight: "20px",
                    color: "#202223",
                  }}
                >
                  <div style={{ fontWeight: 650, marginBottom: 12 }}>
                    {setting.otpExtHeading || "Verify OTP for faster delivery"}
                  </div>

                  <div
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 8,
                      background: "#fff",
                      border: "1px solid #e3e3e3",
                      borderRadius: 8,
                      padding: "10px 12px",
                      marginBottom: 12,
                    }}
                  >
                    <span style={{ color: "#6d7175", flex: 1 }}>
                      {setting.otpExtEnterOtpSentOn ||
                        "Please enter the OTP sent on"}{" "}
                      +9199****1234
                    </span>
                    <span style={{ color: "#2c6ecb", whiteSpace: "nowrap" }}>
                      {setting.otpExtChange || "change"}
                    </span>
                  </div>

                  <div
                    style={{
                      background: "#fff",
                      border: "1px solid #e3e3e3",
                      borderRadius: 8,
                      padding: "12px",
                      color: "#8c9196",
                      marginBottom: 12,
                    }}
                  >
                    {I18n.t("post_order.enter_otp", {
                      defaultValue: "Enter OTP",
                    })}
                  </div>

                  <div style={{ color: "#2c6ecb", marginBottom: 6 }}>
                    {setting.otpExtResendOtpIn || "Resend OTP"}
                  </div>
                  <div style={{ color: "#2c6ecb", marginBottom: 14 }}>
                    {setting.otpExtGetCodeInWhatsapp || "Get code on WhatsApp"}
                  </div>

                  <div
                    style={{
                      background: "#2c6ecb",
                      color: "#fff",
                      borderRadius: 8,
                      padding: "12px 16px",
                      textAlign: "center",
                      fontWeight: 650,
                    }}
                  >
                    {setting.otpExtSubmit ||
                      setting.otpExtVerifyOtp ||
                      "Verify OTP"}
                  </div>
                </div>
              </BlockStack>
          </Card>
        </OtpFormPreview>
      </OtpFormGrid>
    </BlockStack>
  );

  const renderOtpAdvancedSettings = () => (
    <BlockStack gap="400">
      <Card>
        <Box padding="400">
          <BlockStack gap="400">
            <Text variant="headingMd" as="h3">
              {I18n.t("admin.otp_settings")}
            </Text>
            <BlockStack gap="300">
              <TextField
                label={I18n.t("admin.max_retries")}
                value={setting.maxRetries ? "" + setting.maxRetries : "5"}
                onChange={handleSettingChange("maxRetries")}
                type="number"
                min={1}
                max={5}
                step={1}
                helpText={I18n.t("admin.max_retries_help")}
              />
              <TextField
                label={I18n.t("post_order.wait_between_retries")}
                helpText={I18n.t("post_order.wait_between_retries_help")}
                value={setting.otpWaitTime ? "" + setting.otpWaitTime : "30"}
                onChange={handleSettingChange("otpWaitTime")}
                type="number"
                min={10}
                max={180}
                step={10}
              />
              <TextField
                label={I18n.t("admin.otp_fallback_text")}
                value={setting.otpFallbackText || ""}
                onChange={handleSettingChange("otpFallbackText")}
                multiline={2}
                helpText={I18n.t("admin.otp_fallback_text_help")}
              />
              <TextField
                label={I18n.t("post_order.include_product_ids")}
                helpText={I18n.t("post_order.include_product_ids_help")}
                value={setting.postOrderIncludeProductIds || ""}
                onChange={handleSettingChange("postOrderIncludeProductIds")}
                multiline={2}
                placeholder="123456789, 987654321"
              />
            </BlockStack>
          </BlockStack>
        </Box>
      </Card>
      <Card>
        <Box padding="400">
          <BlockStack gap="400">
            <Text variant="headingMd" as="h3">
              {I18n.t("post_order.more_settings")}
            </Text>
            <BlockStack gap="300">
              <Select
                label={I18n.t("post_order.auto_cancel_orders")}
                helpText={I18n.t("post_order.auto_cancel_orders_help")}
                options={options}
                onChange={handleSettingChange("autoCancel")}
                value={setting.autoCancel || -1}
              />
              <Checkbox
                label={I18n.t("post_order.notify_customer_cancel")}
                helpText={I18n.t("post_order.notify_customer_cancel_help")}
                checked={setting.cancelNotifEnabled || false}
                onChange={handleSettingChange("cancelNotifEnabled")}
                disabled={parseInt(setting.autoCancel) < 0}
              />
              <Checkbox
                label={I18n.t("post_order.delete_order")}
                helpText={I18n.t("post_order.delete_order_help")}
                checked={setting.autoDelete || false}
                onChange={handleSettingChange("autoDelete")}
                disabled={parseInt(setting.autoCancel) < 0}
              />
              <Select
                label={I18n.t("post_order.retry_verification_label")}
                options={options}
                onChange={handleSettingChange("retry")}
                value={setting.retry || -1}
                helpText={I18n.t("post_order.retry_verification_help")}
                error={inlineError || undefined}
              />
              <TextField
                label={I18n.t("admin.message_template")}
                helpText={I18n.t("post_order.sms_template_help")}
                value={setting.template || ""}
                onChange={handleSettingChange("template")}
                multiline={2}
                maxLength={140}
                placeholder={I18n.t(
                  "settings.order_verification_code_placeholder"
                )}
              />
            </BlockStack>
          </BlockStack>
        </Box>
      </Card>
      <Card>
        <Box padding="400">
          <BlockStack gap="400">
            <Text variant="headingMd" as="h3">
              {I18n.t("post_order.custom_script_title")}
            </Text>
            <TextField
              label={I18n.t("post_order.custom_script_label")}
              value={setting.customScript || ""}
              onChange={handleSettingChange("customScript")}
              placeholder={I18n.t("settings.debuglog_hello")}
              multiline={5}
              helpText={I18n.t("post_order.custom_script_help")}
            />
          </BlockStack>
        </Box>
      </Card>
    </BlockStack>
  );

  // Loading skeleton – one full-width column of cards, same as the screen.
  if (isLoading) {
    return (
      <SkeletonPage primaryAction>
        <Layout>
          <Layout.Section>
            <BlockStack gap="400">
              <Card padding="600">
                <BlockStack gap="300">
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={2} />
                </BlockStack>
              </Card>
              <Card padding="600">
                <BlockStack gap="300">
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={4} />
                </BlockStack>
              </Card>
              <Card padding="600">
                <BlockStack gap="300">
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={3} />
                </BlockStack>
              </Card>
            </BlockStack>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  return (
    <Page fullWidth={true}>
      {/* App Bridge v4 SaveBar */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={loading ? "" : undefined}
          disabled={loading}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>
          {I18n.t("admin.discard")}
        </button>
      </SaveBar>
      <Layout>
        <Layout.Section>
          <BlockStack gap="400">
            <FeatureCallout
              illustration="widget"
              title={I18n.t("post_order.page_title")}
              description={I18n.t("post_order.setup_subtitle")}
              image={POST_ORDER_CALLOUT_IMAGE}
              badge={
                setting.sms ? (
                  <Badge tone="success" progress="complete">
                    {I18n.t("admin.active")}
                  </Badge>
                ) : (
                  <Badge tone="attention" progress="incomplete">
                    {I18n.t("pre_order.inactive")}
                  </Badge>
                )
              }
              docsUrl="https://codking.notion.site/Step-By-Step-Guide-for-setting-up-OTP-Verification-Post-Order-f002088f1ee640f797b051ce058f658d"
              videos={[
                {
                  url: "https://www.youtube.com/watch?v=e3zYWQpMhlQ",
                  label: I18n.t("post_order.setup_guide"),
                },
                {
                  url: "https://youtu.be/kmPI6KACLRc?si=2p8gEO1bTFXkMOxB",
                  label: I18n.t("post_order.second_video_title"),
                },
              ]}
              showChat
            />
            {renderOtpActivationCard()}

            <FreeWalletBalance />
            {onBoardingFlow && <QuickCurrentStep currentStep={2} />}
            {onBoardingFlow && hasNoChargeId(shop) && (
              <QuickBilling navigationSource="onboarding-otp-post" />
            )}

            {renderActivateTab()}
            {renderOtpFormSettings()}
          </BlockStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default Settings;

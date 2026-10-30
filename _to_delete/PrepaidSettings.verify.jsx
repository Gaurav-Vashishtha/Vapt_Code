import React, {
  useState,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useMemo,
  memo,
} from "react";
import useApi from "../Hooks/useApi";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../Context/Store";
import {
  Page,
  InlineStack,
  Checkbox,
  Banner,
  TextField,
  Button,
  Select,
  Text,
  Tooltip,
  Icon,
  Link,
  Form,
  List,
  InlineGrid,
  Card,
  Divider,
  Tabs,
  Badge,
  Spinner,
  Layout,
  Box,
  BlockStack,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import HexColorPicker from "./HexColorPicker";
import Api from "../Services/Api";
import I18n from "../i18n-lang";
import { debugLog } from "../Modal/utilities/otpUtils";
import { navigateTo } from "../../utils/navigate";
import PostOrderOTPWizard from "./PostOrderOTPWizard";
import PrepaidReminders from "./PrepaidReminders";

// Step 1: Main Component
const PrepaidSettings = () => {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    loading: [loading, setLoading],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    shop: [shop],
    contextualBar: [contextualBar, setContextualBar],
  } = useContext(StoreContext);
  const [isDirty, setIsDirty] = useState(false);
  const [justChanged, setJustChanged] = useState(false);
  const [resendToast, setResendToast] = useState(false);
  const [currentStep, setCurrentStep] = useState(0);
  const [selectedTab, setSelectedTab] = useState(0);
  const [paymentErrors, setPaymentErrors] = useState({
    apiKey: null,
    apiSecret: null,
  });
  const [testLink, setTestLink] = useState({ loading: false, result: null });
  const paymentSectionRef = useRef(null);

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  // Payment validation errors are set only in validatePaymentSettings when Save is clicked
  // (not when toggling prepaid on). Clear errors when prepaid is turned off.
  useEffect(() => {
    if (!setting?.prepaidEnabled) {
      setPaymentErrors({ apiKey: null, apiSecret: null });
    }
  }, [setting?.prepaidEnabled]);

  // Scroll to payment section when validation errors are shown (after Save attempt)
  useEffect(() => {
    if (!paymentErrors.apiKey && !paymentErrors.apiSecret) return;
    const id = requestAnimationFrame(() => {
      paymentSectionRef.current?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    });
    return () => cancelAnimationFrame(id);
  }, [paymentErrors.apiKey, paymentErrors.apiSecret]);

  // Options (unchanged)
  const paymentProviderOptions = [
    { label: I18n.t("prepaid.providers.RAZORPAY"), value: "RAZORPAY" },
    { label: I18n.t("prepaid.providers.PHONEPE"), value: "PHONEPE" },
    { label: I18n.t("prepaid.providers.PAYMOB"), value: "PAYMOB" },
    { label: I18n.t("prepaid.providers.GE_IDEA"), value: "GE_IDEA" },
    { label: I18n.t("prepaid.providers.PAYU"), value: "PAYU" },
    { label: I18n.t("prepaid.providers.CASHFREE"), value: "CASHFREE" },
  ];

  // Settings change handler - same pattern as PreOrderSetting
  const handleSettingChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => ({ ...prev, [key]: value }));
      !contextualBar && setContextualBar(true);
      // Clear payment field errors when user types in those fields
      if (key === "paymentProviderApiKey")
        setPaymentErrors((e) => ({ ...e, apiKey: null }));
      if (key === "paymentProviderApiSecret")
        setPaymentErrors((e) => ({ ...e, apiSecret: null }));
    },
    [contextualBar, setSetting, setContextualBar],
  );

  // Client-side validation: payment credentials required when COD prepaid is enabled
  const validatePaymentSettings = useCallback(() => {
    if (!setting?.prepaidEnabled) {
      setPaymentErrors({ apiKey: null, apiSecret: null });
      return true;
    }
    const apiKey = (setting.paymentProviderApiKey || "").toString().trim();
    const apiSecret = (setting.paymentProviderApiSecret || "").toString().trim();
    let apiKeyMissing = !apiKey;
    let apiSecretMissing = !apiSecret;
    if (setting.paymentProvider === "PAYU") {
      const ak = apiKey.split(":");
      const as = apiSecret.split(":");
      apiKeyMissing =
        !(ak[0] || "").trim() || !(ak[1] || "").trim() || !(ak[2] || "").trim();
      apiSecretMissing = !(as[0] || "").trim() || !(as[1] || "").trim();
    }
    setPaymentErrors({
      apiKey: apiKeyMissing ? I18n.t("prepaid.payment.validation.api_key_required") : null,
      apiSecret: apiSecretMissing ? I18n.t("prepaid.payment.validation.api_secret_required") : null,
    });
    if (apiKeyMissing || apiSecretMissing) {
      shopify.toast.show(I18n.t("prepaid.payment.validation.save_blocked"), {
        isError: true,
      });
      return false;
    }
    return true;
  }, [setting?.prepaidEnabled, setting?.paymentProviderApiKey, setting?.paymentProviderApiSecret, shopify]);

  // Submit handler - same pattern as PreOrderSetting
  const handleSubmit = useCallback(async () => {
    if (!validatePaymentSettings()) return;
    try {
      const response = await Api.post("/settings", { setting });
      setSetting(response.data);
      setOriginalSetting(response.data);
      setContextualBar(false);
      setIsDirty(false);
      setJustChanged(false);
      setPaymentErrors({ apiKey: null, apiSecret: null });
      shopify.toast.show(I18n.t("admin.settings_saved"));
    } catch (error) {
      setResendToast(true);
      shopify.toast.show(I18n.t("admin.settings_error"), { isError: true });
      debugLog(error);
    }
  }, [setting, setSetting, setOriginalSetting, setContextualBar, shopify, validatePaymentSettings]);

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setContextualBar(false);
    setIsDirty(false);
  }, [originalSetting, setSetting, setContextualBar]);

  const handleTestPaymentLink = useCallback(async () => {
    setTestLink({ loading: true, result: null });
    try {
      const response = await Api.post("/settings/test_payment_link", {
        provider: setting.paymentProvider,
        apiKey: setting.paymentProviderApiKey,
        apiSecret: setting.paymentProviderApiSecret,
      });
      setTestLink({ loading: false, result: { ...response.data, ok: true } });
    } catch (error) {
      const data = error?.response?.data || {};
      setTestLink({
        loading: false,
        result: {
          ok: false,
          message:
            data.message ||
            I18n.t("prepaid.payment.test_link.generic_error"),
        },
      });
    }
  }, [
    setting?.paymentProvider,
    setting?.paymentProviderApiKey,
    setting?.paymentProviderApiSecret,
  ]);

  const handleDismissTestLink = useCallback(
    () => setTestLink((s) => ({ ...s, result: null })),
    [],
  );

  const toggleResendActive = useCallback(
    () => setResendToast((active) => !active),
    [],
  );

  // Steps
  const tabs = [
    {
      id: "wizard",
      content: I18n.t("prepaid.tabs.wizard"),
      panelID: "wizard-content",
    },
    {
      id: "banner",
      content: I18n.t("prepaid.tabs.banner_settings"),
      panelID: "banner-content",
    },
    {
      id: "preview",
      content: I18n.t("prepaid.tabs.preview"),
      panelID: "preview-content",
    },
  ];

  const ActivateFeature = ({ setting, handleSettingChange }) => (
    <Form>
      <BlockStack gap="300">
        <Text>{I18n.t("prepaid.activate.title")}</Text>
        <Checkbox
          label={I18n.t("prepaid.activate.checkbox_label")}
          helpText={I18n.t("prepaid.activate.help_text")}
          checked={setting.prepaidEnabled}
          onChange={handleSettingChange("prepaidEnabled")}
        />
      </BlockStack>
    </Form>
  );

  const PaymentSettings = ({
    setting,
    handleSettingChange,
    paymentProviderOptions,
    paymentErrors: errors = {},
    testLink = { loading: false, result: null },
    onTestLink,
    onDismissTest,
  }) => {
    const isPayu = setting.paymentProvider === "PAYU";
    const akParts = (setting.paymentProviderApiKey || "").split(":");
    const asParts = (setting.paymentProviderApiSecret || "").split(":");
    const payu = {
      merchantKey: akParts[0] || "",
      clientId: akParts[1] || "",
      merchantId: akParts[2] || "",
      salt: asParts[0] || "",
      clientSecret: asParts[1] || "",
    };
    const packApiKey = (next) => {
      const parts = [next.merchantKey || "", next.clientId || ""];
      if ((next.merchantId || "").trim() !== "") parts.push(next.merchantId);
      return parts.join(":");
    };
    const packApiSecret = (next) =>
      [next.salt || "", next.clientSecret || ""].join(":");
    const onPayuKeyPart = (field) => (value) =>
      handleSettingChange("paymentProviderApiKey")(
        packApiKey({ ...payu, [field]: value }),
      );
    const onPayuSecretPart = (field) => (value) =>
      handleSettingChange("paymentProviderApiSecret")(
        packApiSecret({ ...payu, [field]: value }),
      );

    return (
      <BlockStack gap="300">
        <Select
          label={I18n.t("prepaid.payment.account_type")}
          options={paymentProviderOptions}
          value={setting.paymentProvider}
          onChange={handleSettingChange("paymentProvider")}
          helpText={
            <div>
              <p>{I18n.t("prepaid.payment.select_provider_help")}</p>
              <Link
                url={
                  setting.paymentProvider === "PHONEPE"
                    ? "https://www.notion.so/codking/0feef35c0ec64875a1ecb9ec24de92e3?v=9ecb40d565f84b1a9e7e8c2d1656fc6f&p=736d218166b44270af3d45129eec17bf&pm=s"
                    : setting.paymentProvider === "PAYMOB"
                      ? "https://codking.notion.site/Step-By-Step-Guide-to-convert-your-COD-orders-to-Prepaid-using-Paymob-in-Egypt-2066e71a63f980699f15f30075c19c60"
                      : setting.paymentProvider === "GE_IDEA"
                        ? "https://codking.notion.site/Step-By-Step-Guide-to-convert-your-COD-orders-to-Prepaid-using-Geidea-in-Egypt-2066e71a63f980699f15f30075c19c60"
                        : setting.paymentProvider === "PAYU"
                          ? "https://payu.in/business/developer/api"
                          : setting.paymentProvider === "CASHFREE"
                            ? "https://www.cashfree.com/docs/api-reference/payments/latest/payment-links/create"
                            : "https://codking.notion.site/How-to-integrate-Razorpay-with-COD-King-e4db8894e53d4130870236ac2542675e"
                }
                external
              >
                {I18n.t("prepaid.payment.integration_steps_link", {
                  provider: setting.paymentProvider,
                })}
              </Link>
            </div>
          }
        />
        {isPayu ? (
          <BlockStack gap="300">
            <TextField
              label={I18n.t("prepaid.payment.labels.payu_merchant_key")}
              value={payu.merchantKey}
              onChange={onPayuKeyPart("merchantKey")}
              error={errors.apiKey}
              autoComplete="off"
              helpText={I18n.t("prepaid.payment.helps.payu_merchant_key")}
            />
            <TextField
              label={I18n.t("prepaid.payment.labels.payu_merchant_id")}
              value={payu.merchantId}
              onChange={onPayuKeyPart("merchantId")}
              error={errors.apiKey}
              autoComplete="off"
              helpText={I18n.t("prepaid.payment.helps.payu_merchant_id")}
            />
            <TextField
              label={I18n.t("prepaid.payment.labels.payu_client_id")}
              value={payu.clientId}
              onChange={onPayuKeyPart("clientId")}
              error={errors.apiKey}
              autoComplete="off"
              helpText={I18n.t("prepaid.payment.helps.payu_client_id")}
            />
            <TextField
              label={I18n.t("prepaid.payment.labels.payu_salt")}
              value={payu.salt}
              onChange={onPayuSecretPart("salt")}
              error={errors.apiSecret}
              autoComplete="off"
              helpText={I18n.t("prepaid.payment.helps.payu_salt")}
            />
            <TextField
              label={I18n.t("prepaid.payment.labels.payu_client_secret")}
              value={payu.clientSecret}
              onChange={onPayuSecretPart("clientSecret")}
              error={errors.apiSecret}
              autoComplete="off"
              helpText={I18n.t("prepaid.payment.helps.payu_client_secret")}
            />
          </BlockStack>
        ) : (
          <>
            <TextField
              label={
                setting.paymentProvider === "PHONEPE"
                  ? I18n.t("prepaid.payment.labels.merchant_id")
                  : setting.paymentProvider === "PAYMOB"
                    ? I18n.t("prepaid.payment.labels.api_secret")
                    : setting.paymentProvider === "GE_IDEA"
                      ? I18n.t("prepaid.payment.labels.api_key")
                      : setting.paymentProvider === "CASHFREE"
                        ? I18n.t("prepaid.payment.labels.cashfree_app_id")
                        : I18n.t("prepaid.payment.labels.api_key")
              }
              value={setting.paymentProviderApiKey}
              onChange={handleSettingChange("paymentProviderApiKey")}
              error={errors.apiKey}
              autoComplete="off"
              helpText={
                setting.paymentProvider === "PHONEPE"
                  ? I18n.t("prepaid.payment.helps.merchant_id")
                  : setting.paymentProvider === "PAYMOB"
                    ? I18n.t("prepaid.payment.helps.api_secret_paymob")
                    : setting.paymentProvider === "GE_IDEA"
                      ? I18n.t("prepaid.payment.helps.api_key_geidea")
                      : setting.paymentProvider === "CASHFREE"
                        ? I18n.t("prepaid.payment.helps.cashfree_app_id")
                        : I18n.t("prepaid.payment.helps.api_key_razorpay")
              }
            />
            <TextField
              label={
                setting.paymentProvider === "PHONEPE"
                  ? I18n.t("prepaid.payment.labels.salt_index")
                  : setting.paymentProvider === "PAYMOB"
                    ? I18n.t("prepaid.payment.labels.methods_csv")
                    : setting.paymentProvider === "GE_IDEA"
                      ? I18n.t("prepaid.payment.labels.api_secret")
                      : setting.paymentProvider === "CASHFREE"
                        ? I18n.t("prepaid.payment.labels.cashfree_secret_key")
                        : I18n.t("prepaid.payment.labels.api_secret")
              }
              value={setting.paymentProviderApiSecret}
              onChange={handleSettingChange("paymentProviderApiSecret")}
              error={errors.apiSecret}
              autoComplete="off"
              helpText={
                setting.paymentProvider === "PHONEPE"
                  ? I18n.t("prepaid.payment.helps.salt_index")
                  : setting.paymentProvider === "PAYMOB"
                    ? I18n.t("prepaid.payment.helps.methods_csv")
                    : setting.paymentProvider === "GE_IDEA"
                      ? I18n.t("prepaid.payment.helps.api_secret_geidea")
                      : setting.paymentProvider === "CASHFREE"
                        ? I18n.t("prepaid.payment.helps.cashfree_secret_key")
                        : I18n.t("prepaid.payment.helps.api_secret_razorpay")
              }
            />
          </>
        )}
        <Divider />
        <BlockStack gap="200">
          <InlineStack gap="300" blockAlign="center" wrap>
            <Button
              onClick={onTestLink}
              loading={testLink.loading}
              disabled={testLink.loading}
            >
              {I18n.t("prepaid.payment.test_link.button")}
            </Button>
            <Text as="span" variant="bodySm" tone="subdued">
              {I18n.t("prepaid.payment.test_link.hint")}
            </Text>
          </InlineStack>
          {testLink.result && (
            <Banner
              tone={testLink.result.ok ? "success" : "critical"}
              onDismiss={onDismissTest}
              title={
                testLink.result.ok
                  ? I18n.t("prepaid.payment.test_link.success_title")
                  : I18n.t("prepaid.payment.test_link.error_title")
              }
            >
              <BlockStack gap="150">
                <Text as="p">{testLink.result.message}</Text>
                {testLink.result.ok && testLink.result.link && (
                  <Link url={testLink.result.link} external>
                    {I18n.t("prepaid.payment.test_link.open_link")}
                  </Link>
                )}
                {testLink.result.mode && (
                  <Text as="p" variant="bodySm" tone="subdued">
                    {I18n.t("prepaid.payment.test_link.mode", {
                      mode: testLink.result.mode,
                    })}
                  </Text>
                )}
              </BlockStack>
            </Banner>
          )}
        </BlockStack>
      </BlockStack>
    );
  };

  const DiscountSettings = ({ setting, handleSettingChange }) => (
    <BlockStack gap="300">
      <Banner status="warning" title={I18n.t("prepaid.discount.banner.title")}>
        <Text>
          {I18n.t("prepaid.discount.banner.body")}
          <Link
            url="https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-message-templates#per-user-marketing-template-message-limits"
            external
          >
            {I18n.t("prepaid.discount.banner.link")}
          </Link>
        </Text>
      </Banner>
      <Select
        label={I18n.t("prepaid.discount.type_label")}
        options={[
          { label: I18n.t("prepaid.discount.type_flat"), value: "FLAT" },
          {
            label: I18n.t("prepaid.discount.type_percentage"),
            value: "PERCENTAGE",
          },
        ]}
        value={setting.prepaidDiscountType}
        onChange={handleSettingChange("prepaidDiscountType")}
        helpText={I18n.t("prepaid.discount.type_help")}
      />
      <TextField
        label={I18n.t("prepaid.discount.value_label")}
        type="number"
        value={setting.prepaidDiscount + ""}
        onChange={handleSettingChange("prepaidDiscount")}
        helpText={I18n.t("prepaid.discount.value_help")}
        required
      />
      <PrepaidReminders
        shopDefaults={{
          discount: setting?.prepaidDiscount,
          discountType: setting?.prepaidDiscountType,
          templateKey: setting?.whatsappPrepaidTemplateName,
          language: setting?.whatsappLanguageCode,
        }}
      />
    </BlockStack>
  );

  const BannerSettings = ({ setting, handleSettingChange }) => (
    <>
      <BlockStack gap={{ xs: "800", sm: "400" }}>
        <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
          <Box
            as="section"
            paddingInlineStart={{ xs: 400, sm: 0 }}
            paddingInlineEnd={{ xs: 400, sm: 0 }}
          >
            <BlockStack gap="400">
              <Text as="h3" variant="headingMd">
                {I18n.t("prepaid.banner.title")}
              </Text>
              <Text as="p" variant="bodyMd">
                {I18n.t("prepaid.banner.subtitle")}
              </Text>
            </BlockStack>
          </Box>
          <Card roundedAbove="sm">
            <BlockStack gap="400">
              <TextField
                label={I18n.t("prepaid.banner.heading_label")}
                placeholder={I18n.t("prepaid.banner.heading_placeholder")}
                value={setting.prepaidHeading}
                onChange={handleSettingChange("prepaidHeading")}
                helpText={I18n.t("prepaid.banner.heading_help")}
              />
              <TextField
                label={I18n.t("prepaid.banner.subheading_label")}
                placeholder={I18n.t("prepaid.banner.subheading_placeholder")}
                value={setting.prepaidSubHeading}
                onChange={handleSettingChange("prepaidSubHeading")}
                helpText={I18n.t("prepaid.banner.subheading_help")}
              />
            </BlockStack>
          </Card>
        </InlineGrid>
      </BlockStack>
    </>
  );

  const Preview = () => (
    <>
      <BlockStack gap={{ xs: "800", sm: "400" }}>
        <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
          <Box
            as="section"
            paddingInlineStart={{ xs: 400, sm: 0 }}
            paddingInlineEnd={{ xs: 400, sm: 0 }}
          >
            <BlockStack gap="400">
              <Text as="h3" variant="headingMd">
                {I18n.t("prepaid.preview.thankyou_title")}
              </Text>
              <Text as="p" variant="bodyMd">
                {I18n.t("prepaid.preview.thankyou_subtitle")}
              </Text>
            </BlockStack>
          </Box>
          <Card roundedAbove="sm">
            <BlockStack gap="400">
              <img
                src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/Screenshot_2025-07-25_at_1.14.19_PM.png?v=1753429574"
                alt={I18n.t("prepaid.preview.banner_preview")}
                style={{
                  width: "100%",
                  height: "auto",
                  objectFit: "contain",
                  aspectRatio: "16/9",
                }}
              />
            </BlockStack>
          </Card>
        </InlineGrid>
        <Divider />
        <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
          <Box
            as="section"
            paddingInlineStart={{ xs: 400, sm: 0 }}
            paddingInlineEnd={{ xs: 400, sm: 0 }}
          >
            <BlockStack gap="400">
              <Text as="h3" variant="headingMd">
                {I18n.t("prepaid.preview.message_title")}
              </Text>
              <Text as="p" variant="bodyMd">
                {I18n.t("prepaid.preview.message_subtitle")}
              </Text>
            </BlockStack>
          </Box>
          <Card roundedAbove="sm">
            <BlockStack gap="400">
              <img
                src="https://cdn.shopify.com/s/files/1/0743/3119/3628/files/WhatsApp_Image_2024-06-26_at_11.10.28_AM.jpg?v=1719380476"
                alt={I18n.t("prepaid.preview.message_preview")}
                style={{
                  width: "100%",
                  height: "auto",
                  objectFit: "contain",
                  aspectRatio: "16/9",
                }}
              />
            </BlockStack>
          </Card>
        </InlineGrid>
      </BlockStack>
    </>
  );

  const [selected, setSelected] = useState(0);
  const handleTabChange = useCallback(
    (selectedTabIndex) => setSelected(selectedTabIndex),
    [],
  );

  function CodKingFooter() {
    return (
      <Box paddingBlock="400" paddingInline="300">
        <BlockStack align="center" gap="200">
          <InlineStack align="center" gap="100">
            <Text as="p" variant="bodySm" tone="subdued">
              {I18n.t("prepaid.footer_copyright")}
            </Text>
          </InlineStack>
        </BlockStack>
      </Box>
    );
  }

  // Loading skeleton – matches PrepaidSettings: Tabs (wizard, banner, preview) + 2fr 5fr sections
  if (!setting) {
    return (
      <SkeletonPage primaryAction>
        <Card padding="2">
          <Tabs
            tabs={[
              { id: "s1", content: <SkeletonBodyText lines={1} /> },
              { id: "s2", content: <SkeletonBodyText lines={1} /> },
              { id: "s3", content: <SkeletonBodyText lines={1} /> },
            ]}
            selected={0}
          >
            <BlockStack gap="400">
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box as="section" paddingInlineStart={{ xs: 400, sm: 0 }} paddingInlineEnd={{ xs: 400, sm: 0 }}>
                  <BlockStack gap="200">
                    <SkeletonDisplayText size="small" />
                    <SkeletonBodyText lines={1} />
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <Box padding="400">
                    <BlockStack gap="200">
                      <SkeletonBodyText lines={1} />
                      <SkeletonBodyText lines={1} />
                    </BlockStack>
                  </Box>
                </Card>
              </InlineGrid>
              <Divider />
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box as="section" paddingInlineStart={{ xs: 400, sm: 0 }} paddingInlineEnd={{ xs: 400, sm: 0 }}>
                  <BlockStack gap="200">
                    <SkeletonDisplayText size="small" />
                    <SkeletonBodyText lines={1} />
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <Box padding="400">
                    <BlockStack gap="200">
                      <SkeletonBodyText lines={2} />
                    </BlockStack>
                  </Box>
                </Card>
              </InlineGrid>
            </BlockStack>
          </Tabs>
        </Card>
      </SkeletonPage>
    );
  }

  return (
    <Page
      title={I18n.t("prepaid.title")}
      padding="2"
      backAction={{
        content: I18n.t("admin.back_to_features"),
        onAction: () => {
          if (isDirty || contextualBar) return;
          navigateTo("/features");
        },
      }}
    >
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
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>
      {resendToast && (
        <Banner
          title={I18n.t("admin.settings_error")}
          status="critical"
          onDismiss={toggleResendActive}
        />
      )}
      <Card padding="2">
        <Tabs
          tabs={tabs}
          selected={selected}
          onSelect={handleTabChange}
          fitted
        ></Tabs>
      </Card>
      <br />
      <br />
      <BlockStack>
        {selected === 0 && (
          <BlockStack gap={{ xs: "800", sm: "400" }}>
            <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
              <Box
                as="section"
                paddingInlineStart={{ xs: 400, sm: 0 }}
                paddingInlineEnd={{ xs: 400, sm: 0 }}
              >
                <BlockStack gap="400">
                  <Text as="h3" variant="headingMd">
                    {I18n.t("prepaid.sections.general.title")}
                  </Text>
                  <Text as="p" variant="bodyMd">
                    {I18n.t("prepaid.sections.general.subtitle")}
                  </Text>
                </BlockStack>
              </Box>
              <Card roundedAbove="sm">
                <BlockStack gap="400">
                  {ActivateFeature({ setting, handleSettingChange })}
                </BlockStack>
              </Card>
            </InlineGrid>
            <Divider />
            {/* === Payment - Configure your payment gateway (below activate, before theme enablement) === */}
            <Box ref={paymentSectionRef}>
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <Text as="h3" variant="headingMd">
                      {I18n.t("prepaid.sections.payment.title")}
                    </Text>
                    <Text as="p" variant="bodyMd">
                      {I18n.t("prepaid.sections.payment.subtitle")}
                    </Text>
                  </BlockStack>
                </Box>
                <Card roundedAbove="sm">
                  <BlockStack gap="400">
                    {PaymentSettings({
                      setting,
                      handleSettingChange,
                      paymentProviderOptions,
                      paymentErrors,
                      testLink,
                      onTestLink: handleTestPaymentLink,
                      onDismissTest: handleDismissTestLink,
                    })}
                  </BlockStack>
                </Card>
              </InlineGrid>
            </Box>
            <Divider />
            {/* === Activate in theme (annotated form: same as Payment and Discount) === */}
            <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
              <Box
                as="section"
                paddingInlineStart={{ xs: 400, sm: 0 }}
                paddingInlineEnd={{ xs: 400, sm: 0 }}
              >
                <BlockStack gap="200">
                  <InlineStack gap="200" blockAlign="center" wrap={false}>
                    <Text as="h3" variant="headingMd">
                      {I18n.t("prepaid.activate_in_theme")}
                    </Text>
                    <Badge tone="info">{I18n.t("admin.required")}</Badge>
                  </InlineStack>
                  <Text as="p" variant="bodyMd" tone="subdued">
                    {I18n.t("prepaid.activate_in_theme_badge")}
                  </Text>
                </BlockStack>
              </Box>
              <Card roundedAbove="sm">
                <BlockStack gap="400">
                  <PostOrderOTPWizard
                    badgeText={I18n.t("prepaid.activate_in_theme_badge")}
                  />
                </BlockStack>
              </Card>
            </InlineGrid>
            <Divider />
            <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
              <Box
                as="section"
                paddingInlineStart={{ xs: 400, sm: 0 }}
                paddingInlineEnd={{ xs: 400, sm: 0 }}
              >
                <BlockStack gap="400">
                  <Text as="h3" variant="headingMd">
                    {I18n.t("prepaid.discount_settings_title")}
                  </Text>
                  <Text as="p" variant="bodyMd">
                    {I18n.t("prepaid.discount_settings_subtitle")}
                  </Text>
                </BlockStack>
              </Box>
              <Card roundedAbove="sm">
                <BlockStack gap="400">
                  {DiscountSettings({
                    setting,
                    handleSettingChange,
                    paymentProviderOptions,
                  })}
                </BlockStack>
              </Card>
            </InlineGrid>
          </BlockStack>
        )}
        {selected === 1 && (
          <BlockStack gap="400">
            <BannerSettings
              setting={setting}
              handleSettingChange={handleSettingChange}
            />
          </BlockStack>
        )}
        {selected === 2 && (
          <BlockStack gap="400">
            <Preview />
          </BlockStack>
        )}
        <CodKingFooter />
      </BlockStack>
    </Page>
  );
};

export default PrepaidSettings;

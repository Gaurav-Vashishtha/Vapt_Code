import React, { useState, useCallback, useContext, useEffect } from "react";
import {
  Card,
  Button,
  BlockStack,
  Text,
  TextField,
  Checkbox,
  ContextualSaveBar,
  Page,
  Layout,
  FormLayout,
  Form,
  Select,
  Banner,
  Link,
  Icon,
  Tooltip,
  Modal,
  InlineStack,
  Box,
  Badge,
  Divider,
  ProgressBar,
  List,
  Bleed,
  Collapsible,
  MediaCard,
  VideoThumbnail,
} from "@shopify/polaris";

// Icon imports - only using icons available in @shopify/polaris-icons
import {
  CircleInformationMajor,
  ExternalSmallMinor,
  CircleTickMinor,
} from "@shopify/polaris-icons";

import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import useApi from "../Hooks/useApi";
// Removed navigateTo import - using handleRedirect pattern instead
import I18n from "../i18n-lang";
import QuickCurrentStep from "./QuickCurrentStep";
import QuickBilling from "./QuickBilling";
import FeatureCallout from "./FeatureCallout";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import { hasNoChargeId } from "../utils/shopUtils";

export default function QuickOnboardingCodFees() {
  const {
    loading: [loading, setLoading],
    plan: [plan],
    shop: [shop],
    setting: [setting, setSetting],
    contextualBar: [, setStoreContextualBar],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [, setTab],
  } = useContext(StoreContext);

  /**
   * App Bridge v4 Navigation Interceptor
   * Prevents full page reload and syncs with Shopify Admin
   */
  const handleRedirect = (e, path) => {
    if (e) e.preventDefault();

    // 1. Update the address bar without hitting the server
    window.history.pushState({}, '', path);

    // 2. Dispatch event so StoreProvider/Router can update the view
    const navEvent = new PopStateEvent('popstate');
    window.dispatchEvent(navEvent);

    // 3. If your StoreContext uses a setTab function for routing, call it here
    if (typeof setTab === 'function') {
      setTab(path);
    }
  };

  const [isDirty, setIsDirty] = useState(false);
  useEffect(() => {
    setStoreContextualBar(isDirty);
  }, [isDirty, setStoreContextualBar]);
  const [videoModalActive, setVideoModalActive] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [isGuideOpen, setIsGuideOpen] = useState(false);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // Handle Esc key press to close video modal
  const handleKeyDown = useCallback(
    (event) => {
      if (event.key === "Escape" && videoModalActive) {
        setVideoModalActive(false);
      }
    },
    [videoModalActive]
  );

  // Add event listener for Esc key
  useEffect(() => {
    if (videoModalActive) {
      document.addEventListener("keydown", handleKeyDown);
      // Prevent body scroll when modal is open
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "unset";
    }

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "unset";
    };
  }, [videoModalActive, handleKeyDown]);

  const [
    { data: paymentMethods, loading: paymentMethodsLoading },
    getPaymentMethods,
  ] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/payment_methods`,
      method: "GET",
    },
    { manual: true }
  );

  useEffect(() => {
    if (!paymentMethods) getPaymentMethods();
  }, [paymentMethods, getPaymentMethods]);

  // Track page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: 2,
      feature: "cod-fees",
    });
  }, []);

  const handleSettingChange = useCallback(
    (key) => (value) => {
      const oldValue = setting[key];
      setSetting((prev) => ({
        ...prev,
        [key]: key === "isPercentage" ? value === "true" : value,
      }));
      setIsDirty(true);
      setSaveSuccess(false);

      // Track setting change
      journeyTracker.trackSettingChange(key, oldValue, value, {
        step: 2,
        feature: "cod-fees",
      });
    },
    [setSetting, setting]
  );

  const handleSubmit = useCallback(() => {
    setLoading(true);
    Api.post("/settings", setting)
      .then((res) => {
        setIsDirty(false);
        setSetting(res.data);
        setOriginalSetting(res.data);
        setSaveSuccess(true);
        setTimeout(() => setSaveSuccess(false), 3000);

        // Track successful form submission
        journeyTracker.trackFormSubmit("cod_fees_settings", setting, {
          step: 2,
          feature: "cod-fees",
        });
      })
      .catch((error) => {
        // Track form submission error
        journeyTracker.trackError("form_submission_error", error.message, {
          step: 2,
          feature: "cod-fees",
        });
      })
      .finally(() => setLoading(false));
  }, [setting, setLoading, setSetting, setOriginalSetting]);

  const isConfigured =
    setting.paymentMethodName &&
    setting.codFeeShippingKeyword &&
    setting.enableShippingCodFees;

  const StepIndicator = ({ stepNumber, isActive, isCompleted }) => (
    <Box
      padding="150"
      background={
        isCompleted
          ? "surface-success"
          : isActive
          ? "surface-primary"
          : "surface-neutral-subdued"
      }
      borderRadius="full"
      minWidth="28px"
      minHeight="28px"
    >
      {isCompleted ? (
        <Icon source={CircleTickMinor} tone="success" />
      ) : (
        <Text
          variant="bodySm"
          fontWeight="bold"
          alignment="center"
          tone={isActive ? "text-primary" : "subdued"}
        >
          {stepNumber}
        </Text>
      )}
    </Box>
  );

  return (
    <Page
      title={I18n.t("quick_onboarding_cod_fees.page_title")}
      subtitle={I18n.t("quick_onboarding_cod_fees.page_subtitle")}
      backAction={{
        content: I18n.t("quick_onboarding_cod_fees.back_to_onboarding"),
        onAction: (e) => {
          if (isDirty) return;
          journeyTracker.trackButtonClick("back_to_onboarding", {
            fromStep: 2,
            toStep: 1,
            feature: "cod-fees",
          });
          handleRedirect(e, "/quick-onboarding");
        },
      }}
      fullWidth={true}
    >
      <Form onSubmit={handleSubmit}>
        <Layout>
          <Layout.Section variant="twoThirds">
            <Box paddingBlockEnd="400">
              <FeatureCallout
                illustration="docs"
                title={I18n.t("documentation.cod_fees_help_title")}
                description={I18n.t("documentation.cod_fees_help_description")}
                docsUrl="https://codking.notion.site/Step-by-Step-Guide-for-setting-up-COD-fees-for-your-Shopify-store-12e6e71a63f980faa519e4dc35f617b7"
                videoUrl="https://youtu.be/I22U3fj6vKo?si=sJ5ZfDo4Am_jCX5y"
                showChat
              />
            </Box>
            {/* Success Banner */}
            {saveSuccess && (
              <Banner
                title={I18n.t("quick_onboarding_cod_fees.settings_saved")}
                tone="success"
                icon={CircleTickMinor}
                onDismiss={() => setSaveSuccess(false)}
              />
            )}
            {/* Header Section */}
            <QuickCurrentStep currentStep={2} />
            <br />
            {hasNoChargeId(shop) && plan?.name !== "Free" && (
              <QuickBilling disableBilling={!isConfigured} />
            )}
            <br />

            {/* Payment Method Selection */}
            <Card>
              <BlockStack gap="400">
                {/* Tutorial Video MediaCard */}

                <Text variant="bodyMd" tone="subdued">
                  {I18n.t(
                    "quick_onboarding_cod_fees.payment_method_description"
                  )}
                </Text>

                <FormLayout>
                  <Select
                    label=""
                    labelHidden
                    options={[
                      {
                        label: I18n.t(
                          "quick_onboarding_cod_fees.select_payment_placeholder"
                        ),
                        value: "",
                      },
                      ...(paymentMethods?.paymentMethods?.map((m) => ({
                        label: m.label,
                        value: m.value,
                      })) || []),
                    ]}
                    value={setting.paymentMethodName || ""}
                    onChange={handleSettingChange("paymentMethodName")}
                    helpText={I18n.t(
                      "quick_onboarding_cod_fees.payment_method_help"
                    )}
                    loading={paymentMethodsLoading}
                  />
                </FormLayout>
              </BlockStack>
            </Card>
            <br />
            {/* Shipping Setup Guide */}
            <Card>
              <BlockStack gap="400">
                <InlineStack gap="200" blockAlign="center">
                  <Text variant="headingMd">
                    {I18n.t("quick_onboarding_cod_fees.shipping_setup_title")}
                  </Text>
                  <Tooltip
                    content={I18n.t(
                      "quick_onboarding_cod_fees.shipping_setup_tooltip"
                    )}
                  >
                    <Icon source={CircleInformationMajor} tone="subdued" />
                  </Tooltip>
                </InlineStack>

                <Text variant="bodyMd" tone="subdued">
                  {I18n.t(
                    "quick_onboarding_cod_fees.shipping_setup_description"
                  )}
                </Text>

                <Box
                  padding="400"
                  background="bg-surface-neutral-subdued"
                  borderRadius="200"
                  borderWidth="025"
                  borderColor="border-neutral-subdued"
                >
                  <List type="number">
                    <List.Item>
                      <InlineStack gap="100" wrap={false} blockAlign="center">
                        <Text>
                          {I18n.t("quick_onboarding_cod_fees.step_1_prefix")}
                        </Text>
                        <Link
                          url={`https://${shop?.shopify_domain}/admin/settings/shipping`}
                          external
                          monochrome
                        >
                          <InlineStack gap="100" blockAlign="center">
                            <Text fontWeight="medium">
                              {I18n.t(
                                "quick_onboarding_cod_fees.shopify_shipping_settings"
                              )}
                            </Text>
                            <Icon source={ExternalSmallMinor} />
                          </InlineStack>
                        </Link>
                      </InlineStack>
                    </List.Item>
                    <List.Item>
                      {I18n.t("quick_onboarding_cod_fees.step_2")}
                    </List.Item>
                    <List.Item>
                      {I18n.t("quick_onboarding_cod_fees.step_3")}
                    </List.Item>
                    <List.Item>
                      {I18n.t("quick_onboarding_cod_fees.step_4")}
                    </List.Item>
                  </List>
                </Box>

                <FormLayout>
                  <TextField
                    label={I18n.t(
                      "quick_onboarding_cod_fees.shipping_keyword_label"
                    )}
                    value={setting.codFeeShippingKeyword || ""}
                    onChange={handleSettingChange("codFeeShippingKeyword")}
                    helpText={I18n.t(
                      "quick_onboarding_cod_fees.shipping_keyword_help"
                    )}
                    placeholder={I18n.t(
                      "quick_onboarding_cod_fees.shipping_keyword_placeholder"
                    )}
                    prefix="#"
                  />

                  {setting.codFeeShippingKeyword && (
                    <Text variant="headingSm" tone="info">
                      {I18n.t("quick_onboarding_cod_fees.keyword_example", {
                        keyword: setting.codFeeShippingKeyword,
                      })}
                    </Text>
                  )}

                  <TextField
                    label={I18n.t(
                      "quick_onboarding_cod_fees.cod_only_shipping_keyword_label"
                    )}
                    value={setting.codOnlyShippingKeyword || ""}
                    onChange={handleSettingChange("codOnlyShippingKeyword")}
                    helpText={I18n.t(
                      "quick_onboarding_cod_fees.cod_only_shipping_keyword_help"
                    )}
                    placeholder={I18n.t(
                      "quick_onboarding_cod_fees.cod_only_shipping_keyword_placeholder"
                    )}
                    prefix="#"
                  />
                </FormLayout>
              </BlockStack>
            </Card>
            <br />
            {/* Enable COD Fees */}
            <Card>
              <BlockStack gap="400">
                <Text variant="headingMd">
                  {I18n.t("quick_onboarding_cod_fees.enable_cod_fees_title")}
                </Text>

                <Box
                  padding="400"
                  background={
                    setting.enableShippingCodFees
                      ? "bg-surface-success-subdued"
                      : "bg-surface-neutral"
                  }
                  borderRadius="200"
                  borderWidth="025"
                  borderColor={
                    setting.enableShippingCodFees
                      ? "border-success"
                      : "border-neutral"
                  }
                >
                  <BlockStack gap="300">
                    <Checkbox
                      label={
                        <InlineStack gap="200" blockAlign="center">
                          <Text variant="bodyLg" fontWeight="semibold">
                            {I18n.t(
                              "quick_onboarding_cod_fees.enable_cod_fee_collection"
                            )}
                          </Text>
                          {setting.enableShippingCodFees && (
                            <Badge tone="success" size="small">
                              {I18n.t("quick_onboarding_cod_fees.active_badge")}
                            </Badge>
                          )}
                        </InlineStack>
                      }
                      checked={setting.enableShippingCodFees}
                      onChange={handleSettingChange("enableShippingCodFees")}
                    />
                    <Text variant="bodyMd" tone="subdued">
                      {I18n.t(
                        "quick_onboarding_cod_fees.enable_cod_fees_description"
                      )}
                    </Text>
                  </BlockStack>
                </Box>
              </BlockStack>
            </Card>
          </Layout.Section>

        </Layout>

        {/* Contextual Save Bar */}
        {isDirty && (
          <ContextualSaveBar
            message={I18n.t("quick_onboarding_cod_fees.unsaved_changes")}
            saveAction={{
              content: I18n.t("quick_onboarding_cod_fees.save"),
              onAction: () => {
                journeyTracker.trackButtonClick("save_settings", {
                  step: 2,
                  feature: "cod-fees",
                });
                handleSubmit();
              },
              loading,
              disabled: false,
            }}
            discardAction={{
              content: I18n.t("quick_onboarding_cod_fees.discard"),
              onAction: () => {
                journeyTracker.trackButtonClick("discard_changes", {
                  step: 2,
                  feature: "cod-fees",
                });
                setSetting(originalSetting);
                setIsDirty(false);
              },
            }}
          />
        )}

        {/* Video Tutorial Modal */}
        <Modal
          open={videoModalActive}
          onClose={() => setVideoModalActive(false)}
          title={I18n.t("quick_onboarding_cod_fees.modal_title")}
          large
          backdrop={true}
        >
          <Modal.Section>
            <BlockStack gap="400">
              <Text variant="bodyMd" tone="subdued">
                {I18n.t("quick_onboarding_cod_fees.modal_description")}
              </Text>
              <Box>
                <div
                  style={{
                    position: "relative",
                    paddingBottom: "56.25%",
                    height: 0,
                    overflow: "hidden",
                    borderRadius: "12px",
                    border: "1px solid var(--p-border-subdued)",
                  }}
                >
                  <iframe
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      height: "100%",
                    }}
                    src="https://www.youtube.com/embed/I22U3fj6vKo"
                    title={I18n.t("quick_onboarding_cod_fees.modal_title")}
                    frameBorder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowFullScreen
                  />
                </div>
              </Box>
            </BlockStack>
          </Modal.Section>
        </Modal>
      </Form>
    </Page>
  );
}

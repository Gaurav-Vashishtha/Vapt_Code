import React, { useState, useContext, useEffect } from "react";
import {
  Page,
  Layout,
  Card,
  Text,
  RadioButton,
  Button,
  ButtonGroup,
  Badge,
  BlockStack,
  InlineStack,
  Box,
  Divider,
  Banner,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import QuickCurrentStep from "./QuickCurrentStep";
import LanguageDropdown from "./Integrations/LanguageDropdown";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

// Wizard Steps Component
const WizardSteps = ({ currentStep = 1 }) => {
  const steps = [
    { step: 1, label: I18n.t("onboarding.quick_steps.select") },
    { step: 2, label: I18n.t("onboarding.quick_steps.activate") },
    { step: 3, label: I18n.t("onboarding.quick_steps.test_billing") },
  ];

  return (
    <Box paddingBlockEnd="600">
      <InlineStack gap="400" align="center">
        {steps.map((step, index) => (
          <React.Fragment key={step.step}>
            <InlineStack gap="200" align="center">
              <Box
                background={
                  currentStep >= step.step
                    ? "bg-fill-brand"
                    : "bg-fill-disabled"
                }
                padding="100"
                borderRadius="full"
                minWidth="24px"
                minHeight="24px"
              >
                <Text
                  as="span"
                  variant="bodyMd"
                  fontWeight="semibold"
                  tone={currentStep >= step.step ? "text-inverse" : "subdued"}
                  alignment="center"
                >
                  {step.step}
                </Text>
              </Box>
              <Text
                as="span"
                variant="bodyMd"
                fontWeight={currentStep === step.step ? "semibold" : "regular"}
                tone={currentStep >= step.step ? "base" : "subdued"}
              >
                {step.label}
              </Text>
            </InlineStack>
            {index < steps.length - 1 && (
              <Box
                background="bg-fill-disabled"
                minHeight="1px"
                minWidth="32px"
              />
            )}
          </React.Fragment>
        ))}
      </InlineStack>
    </Box>
  );
};

// Clean Feature Option Component
const FeatureOption = ({ feature, selected, onSelect, isLast }) => {
  const handleKeyDown = (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      onSelect();
    }
  };

  return (
    <>
      <Box
        padding="400"
        borderWidth="1"
        borderColor={selected ? "border-brand" : "border"}
        borderRadius="200"
        background={selected ? "bg-surface-brand-subdued" : "bg-surface"}
        borderStyle="solid"
        onClick={onSelect}
        role="button"
        tabIndex={0}
        onKeyDown={handleKeyDown}
        aria-pressed={selected}
        aria-labelledby={`feature-${feature.key}-title`}
        aria-describedby={`feature-${feature.key}-description`}
        style={{
          cursor: "pointer",
          transition: "all 0.15s ease",
        }}
      >
        <InlineStack gap="300" align="start" blockAlign="start">
          <Box minWidth="fit-content">
            <RadioButton
              id={`feature-${feature.key}`}
              name="feature-selection"
              checked={selected}
              onChange={onSelect}
              ariaLabel={I18n.t("onboarding.select_feature_option")}
            />
          </Box>
          <BlockStack gap="200" align="start" minWidth="0">
            <InlineStack gap="200" align="start" blockAlign="start" wrap={true}>
              <Text
                as="h4"
                variant="headingSm"
                fontWeight="semibold"
                tone="base"
                id={`feature-${feature.key}-title`}
              >
                {feature.title}
              </Text>
              {feature.badge && (
                <Badge tone="attention" size="small">
                  {feature.badge}
                </Badge>
              )}
              {feature.isPro && (
                <Badge tone="info" size="small">
                  {I18n.t("onboarding.pro_badge")}
                </Badge>
              )}
              {feature.setupTime && (
                <Badge tone="success" size="small">
                  ⚡ {feature.setupTime}
                </Badge>
              )}
            </InlineStack>
            <Text
              as="p"
              variant="bodyMd"
              tone="subdued"
              id={`feature-${feature.key}-description`}
            >
              {feature.description}
            </Text>
            {feature.benefit && (
              <Text
                as="p"
                variant="bodyMd"
                fontWeight="semibold"
                tone="success"
              >
                ✓ {feature.benefit}
              </Text>
            )}
          </BlockStack>
        </InlineStack>
      </Box>
    </>
  );
};

export default function QuickOnboarding() {
  const {
    isPrepaidEnabled,
    setting,
    setSetting,
    tab: [, setTab],
  } = useContext(StoreContext);
  const [selected, setSelected] = useState("otp");
  const [currentStep, setCurrentStep] = useState(1);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  /**
   * App Bridge v4 Navigation Interceptor
   * Prevents full page reload and syncs with Shopify Admin
   */
  const handleRedirect = (e, path) => {
    if (e) e.preventDefault();

    // 1. Update the address bar without hitting the server
    window.history.pushState({}, "", path);

    // 2. Dispatch event so StoreProvider/Router can update the view
    const navEvent = new PopStateEvent("popstate");
    window.dispatchEvent(navEvent);

    // 3. If your StoreContext uses a setTab function for routing, call it here
    if (typeof setTab === "function") {
      setTab(path);
    }
  };

  // Track feature selection
  const handleFeatureSelect = (featureKey) => {
    const selectedFeature = features.find((f) => f.key === featureKey);
    setSelected(featureKey);

    // Track feature selection
    journeyTracker.trackButtonClick("feature_selection", {
      selectedFeature: featureKey,
      featureTitle: selectedFeature?.title,
      featureDescription: selectedFeature?.description,
      isPro: selectedFeature?.isPro || false,
      step: currentStep,
    });
  };

  const features = [
    {
      key: "otp",
      title: I18n.t("onboarding.otp_heading"),
      description: I18n.t("quick_onboarding.otp_description"),
      path: "/quick-onboarding/otp",
      badge: I18n.t("quick_onboarding.most_popular"),
      setupTime: I18n.t("quick_onboarding.setup_5_min"),
      benefit: I18n.t("quick_onboarding.stop_fake_orders"),
    },
    {
      key: "partial-payment",
      title: I18n.t("onboarding.partial_heading"),
      description: I18n.t("quick_onboarding.partial_description"),
      path: "/quick-onboarding/partial-payment",
      setupTime: I18n.t("quick_onboarding.setup_3_min"),
      benefit: I18n.t("quick_onboarding.take_upfront_token"),
    },

    {
      key: "notifications",
      title: I18n.t("onboarding.notifications_heading"),
      description: I18n.t("quick_onboarding.notifications_description"),
      path: "/quick-onboarding/notifications",
      setupTime: I18n.t("quick_onboarding.setup_2_min"),
      benefit: I18n.t("quick_onboarding.convert_carts"),
    },
    {
      key: "rules",
      title: I18n.t("onboarding.rules_heading"),
      description: I18n.t("quick_onboarding.rules_description"),
      path: "/quick-onboarding/limit-cod",
      isPro: true,
      setupTime: I18n.t("quick_onboarding.setup_4_min"),
      benefit: I18n.t("quick_onboarding.block_risky_orders"),
    },
    {
      key: "cod-fees",
      title: I18n.t("onboarding.cod_heading"),
      description: I18n.t("quick_onboarding.cod_fees_description"),
      path: "/quick-onboarding/fees",
      isPro: true,
      setupTime: I18n.t("quick_onboarding.setup_3_min"),
      benefit: I18n.t("quick_onboarding.cover_cod_costs"),
    },
  ];

  const handleContinue = (e) => {
    const selectedFeature = features.find((f) => f.key === selected);
    if (selectedFeature?.path) {
      // Track the continue action with selected feature
      journeyTracker.trackButtonClick("continue", {
        selectedFeature: selectedFeature.key,
        featureTitle: selectedFeature.title,
        targetPath: selectedFeature.path,
        step: currentStep,
      });

      // Track navigation
      journeyTracker.trackNavigation("quick-onboarding", selectedFeature.path, {
        selectedFeature: selectedFeature.key,
      });

      // Move to next step before navigation
      setCurrentStep(2);

      // App Bridge v4 Navigation: Use handleRedirect pattern
      handleRedirect(e, selectedFeature.path);
    }
  };

  // Track skip action
  const handleSkip = (e) => {
    journeyTracker.trackButtonClick("skip", {
      currentStep: currentStep,
      selectedFeature: selected,
    });
    // App Bridge v4 Navigation: Use handleRedirect pattern
    handleRedirect(e, "/");
  };

  const filteredFeatures = features.filter(
    (f) => isPrepaidEnabled || f.key !== "cod-to-prepaid",
  );

  // Track initial page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      availableFeatures: filteredFeatures.map((f) => f.key),
      isPrepaidEnabled: isPrepaidEnabled,
      step: currentStep,
    });
  }, []);

  return (
    <Page
      title={I18n.t("onboarding.quick_setup")}
      subtitle={I18n.t("onboarding.get_started")}
      titleMetadata={<LanguageDropdown />}
    >
      <Layout>
        <Layout.Section>
          <Card>
            <QuickCurrentStep currentStep={currentStep} />
            <br />
            <BlockStack gap="500">
              <Text as="h2" variant="headingLg" fontWeight="semibold">
                {I18n.t("onboarding.choose_feature")}
              </Text>

              {/* Welcome Banner with Social Proof */}
              <Banner
                title={I18n.t("quick_onboarding.welcome_title")}
                tone="info"
              >
                <p>{I18n.t("quick_onboarding.welcome_message")}</p>
              </Banner>

              {/* Feature Selection */}
              <Card>
                <BlockStack gap="400">
                  <InlineStack
                    gap="300"
                    align="space-between"
                    blockAlign="start"
                    wrap={true}
                  >
                    <BlockStack gap="200">
                      <Text as="h3" variant="headingMd" fontWeight="semibold">
                        {I18n.t("quick_onboarding.choose_feature_title")}
                      </Text>
                      <Text as="p" variant="bodyMd" tone="subdued">
                        {I18n.t("quick_onboarding.choose_feature_subtitle")}
                      </Text>
                    </BlockStack>
                    <Button
                      variant="primary"
                      size="large"
                      onClick={handleContinue}
                      disabled={!selected}
                    >
                      {selected
                        ? I18n.t("quick_onboarding.continue_with_setup")
                        : I18n.t("onboarding.continue")}
                    </Button>
                  </InlineStack>

                  <BlockStack gap="400">
                    {filteredFeatures.map((feature, index) => (
                      <React.Fragment key={feature.key}>
                        <FeatureOption
                          feature={feature}
                          selected={selected === feature.key}
                          onSelect={() => handleFeatureSelect(feature.key)}
                          isLast={index === filteredFeatures.length - 1}
                        />
                        {index < filteredFeatures.length - 1 && (
                          <Box paddingBlockStart="100" paddingBlockEnd="100">
                            <Divider />
                          </Box>
                        )}
                      </React.Fragment>
                    ))}
                  </BlockStack>
                </BlockStack>
              </Card>

              {/* Trust Signals & Skip Option */}
              <Card>
                <BlockStack gap="400">
                  <InlineStack gap="400" align="space-between" wrap={true}>
                    <BlockStack gap="200">
                      {/* <Text as="p" variant="bodyMd" fontWeight="semibold">
                        {I18n.t("quick_onboarding.trust_signals")}
                      </Text> */}
                      <Text as="p" variant="bodyMd" tone="subdued">
                        {I18n.t("quick_onboarding.setup_time_note")}
                      </Text>
                    </BlockStack>
                  </InlineStack>

                  <Divider />

                  <InlineStack gap="200" align="center" blockAlign="center">
                    <Button variant="plain" onClick={handleSkip} tone="subdued">
                      {I18n.t("quick_onboarding.skip_for_now")}
                    </Button>
                    <Text as="span" variant="bodyMd" tone="subdued">
                      •
                    </Text>
                    <Text as="span" variant="bodyMd" tone="subdued">
                      {I18n.t("quick_onboarding.need_help")}
                    </Text>
                  </InlineStack>
                </BlockStack>
              </Card>
            </BlockStack>
          </Card>
        </Layout.Section>
      </Layout>
    </Page>
  );
}

import React, { useContext, useEffect } from "react";
import {
  BlockStack,
  InlineStack,
  Box,
  Button,
  Text,
  Card,
  Badge,
  Icon,
} from "@shopify/polaris";
import { CheckoutMajor, PlayMajor } from "@shopify/polaris-icons";
import I18n from "../i18n-lang";
import { StoreContext } from "../Context/Store";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

// Constants
const OTP_TYPE = {
  NONE: "",
  PRE_ORDER: "pre_order",
  POST_ORDER: "post_order",
};

function OtpTypeSelection({ selectedOtpType, onOtpTypeChange, onContinue }) {
  const { setting, setSetting } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // Track page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: 1,
      feature: "otp-placement",
    });
  }, []);
  const renderStepIndicator = (stepNumber, isHighlighted) => (
    <Box
      background={isHighlighted ? "bg-fill-warning" : "bg-fill-tertiary"}
      padding="100"
      borderRadius="100"
      minWidth="24px"
      minHeight="24px"
    >
      <Text
        as="span"
        variant="bodySm"
        fontWeight="medium"
        alignment="center"
        tone={isHighlighted ? "text-inverse" : "subdued"}
      >
        {stepNumber}
      </Text>
    </Box>
  );

  const renderCard = (
    type,
    title,
    steps,
    highlightStep,
    badges,
    description,
    additionalInfo
  ) => {
    const isSelected = selectedOtpType === type;

    return (
      <Box width="50%">
        <Card>
          <Box
            padding="500"
            borderWidth={isSelected ? "025" : "0"}
            borderColor={isSelected ? "border-brand" : "transparent"}
            borderRadius="300"
            background={isSelected ? "bg-surface-brand-selected" : "bg-surface"}
          >
            <BlockStack gap="500">
              {/* Card Header */}
              <BlockStack gap="200">
                <InlineStack align="space-between" blockAlign="start">
                  <Text as="h2" variant="headingMd" fontWeight="semibold">
                    {title}
                  </Text>
                  {isSelected && (
                    <Box
                      background="bg-fill-success"
                      padding="100"
                      borderRadius="100"
                    >
                      <Icon source={CheckoutMajor} tone="text-inverse" />
                    </Box>
                  )}
                </InlineStack>

                {/* Badges */}
                <InlineStack gap="200" wrap>
                  {badges.map((badge, index) => (
                    <Badge key={index} tone={badge.tone} size="small">
                      {badge.text}
                    </Badge>
                  ))}
                </InlineStack>
              </BlockStack>

              {/* How it works */}
              <BlockStack gap="300">
                <Text as="h3" variant="headingSm" fontWeight="medium">
                  {I18n.t("quick_onboarding_otp_placement.how_it_works")}
                </Text>
                <BlockStack gap="250">
                  {steps.map((text, index) => (
                    <InlineStack key={index} gap="300" blockAlign="center">
                      {renderStepIndicator(index + 1, index === highlightStep)}
                      <Text
                        as="span"
                        variant="bodyMd"
                        fontWeight={
                          index === highlightStep ? "medium" : "regular"
                        }
                        tone={index === highlightStep ? "base" : "subdued"}
                      >
                        {text}
                      </Text>
                    </InlineStack>
                  ))}
                </BlockStack>
              </BlockStack>

              {/* Description */}
              <Box
                padding="400"
                background="bg-surface-secondary"
                borderRadius="200"
              >
                <BlockStack gap="300">
                  <Text as="p" variant="bodyMd">
                    <Text as="span" fontWeight="semibold" tone="base">
                      {I18n.t("quick_onboarding_otp_placement.best_suited_for")}
                    </Text>{" "}
                    <Text as="span" tone="subdued">
                      {description}
                    </Text>
                  </Text>
                  {additionalInfo && (
                    <Text as="p" variant="bodyMd">
                      <Text as="span" fontWeight="semibold" tone="base">
                        {additionalInfo.label}:
                      </Text>{" "}
                      <Text as="span" tone="subdued">
                        {additionalInfo.text}
                      </Text>
                    </Text>
                  )}
                </BlockStack>
              </Box>

              {/* Action Buttons */}
              <BlockStack gap="300">
                <Button
                  variant={isSelected ? "primary" : "secondary"}
                  size="large"
                  fullWidth
                  onClick={() => {
                    journeyTracker.trackButtonClick("otp_type_selection", {
                      selectedType: type,
                      step: 1,
                      feature: "otp-placement",
                    });
                    onOtpTypeChange(type);
                  }}
                  icon={isSelected ? CheckoutMajor : undefined}
                >
                  {isSelected ? "Selected" : "Select This Option"}
                </Button>
                <Button
                  variant="plain"
                  size="medium"
                  fullWidth
                  icon={PlayMajor}
                  onClick={() => {
                    journeyTracker.trackButtonClick("watch_demo", {
                      otpType: type,
                      step: 1,
                      feature: "otp-placement",
                    });
                    /* Handle video modal */
                  }}
                >
                  {I18n.t("quick_onboarding_otp_placement.watch_quick_demo")}
                </Button>
              </BlockStack>
            </BlockStack>
          </Box>
        </Card>
      </Box>
    );
  };

  return (
    <BlockStack gap="600">
      {/* Header Section */}
      <BlockStack gap="200">
        <Text as="h1" variant="headingLg" fontWeight="bold">
          {I18n.t("quick_onboarding_otp_placement.select_option")}
        </Text>
        <Text as="p" variant="bodyLg" tone="subdued">
          {I18n.t("quick_onboarding_otp_placement.choose_the_otp_verification_method_that")}
        </Text>
      </BlockStack>

      {/* Comparison Cards */}
      <InlineStack gap="500" wrap={false} align="start">
        {renderCard(
          OTP_TYPE.PRE_ORDER,
          "Pre-Order OTP Verification",
          [
            "Customer adds product",
            "Clicks on Checkout",
            "OTP verification",
            "Shopify's Checkout Page",
            "Order Placed",
            "Adds a COD-Verified Tag in order",
          ],
          2, // Highlight step 3 (index 2)
          [
            { text: "High Fake Orders", tone: "attention" },
            { text: "India Shipping", tone: "info" },
          ],
          "Stores with a high number of fake orders.",
          {
            label: I18n.t("quick_onboarding_otp_placement.additional_feature"),
            text: "Supports prefilled shipping addresses for faster checkout process (Available only for India).",
          }
        )}

        {renderCard(
          OTP_TYPE.POST_ORDER,
          "Post-Order OTP Verification",
          [
            "Customer adds product",
            "Clicks on Checkout",
            "Shopify's Checkout Page",
            "Order Placed",
            "OTP verification",
            "Adds a COD-Verified Tag in order",
          ],
          4, // Highlight step 5 (index 4)
          [
            { text: "Low Fake Orders", tone: "success" },
            { text: "No Conversion Impact", tone: "info" },
          ],
          "Stores having less number of fake orders. No impact on order conversions.",
          {
            label: I18n.t("quick_onboarding_otp_placement.benefit"),
            text: "Customers complete their purchase first, then verify via OTP, ensuring higher conversion rates.",
          }
        )}
      </InlineStack>

      {/* Continue Button */}
      {selectedOtpType && (
        <Box paddingBlockStart="200">
          <InlineStack align="center">
            <Button
              variant="primary"
              size="large"
              onClick={() => {
                journeyTracker.trackButtonClick("continue", {
                  selectedOtpType: selectedOtpType,
                  step: 1,
                  feature: "otp-placement",
                });
                onContinue();
              }}
              icon={CheckoutMajor}
            >
              {I18n.t("onboarding_otp.selection.continue_button")}
            </Button>
          </InlineStack>
        </Box>
      )}
    </BlockStack>
  );
}

// Export the OTP_TYPE constants for use in parent component
export { OTP_TYPE };
export default OtpTypeSelection;

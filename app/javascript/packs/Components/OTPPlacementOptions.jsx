import React, { useState, useCallback, useEffect, useContext } from "react";
import {
  Page,
  Layout,
  Card,
  BlockStack,
  InlineGrid,
  Text,
  Button,
  Badge,
  Icon,
  Box,
  Modal,
  InlineStack,
  Collapsible,
  RadioButton,
} from "@shopify/polaris";
import {
  ClockMajor,
  PlayCircleMajor,
  CaretDownMinor,
  CaretUpMinor,
} from "@shopify/polaris-icons";
import I18n from "../i18n-lang";
import { navigateTo } from "../../utils/navigate";
import QuickCurrentStep from "./QuickCurrentStep";
import { StoreContext } from "../Context/Store";

export function isShopifyPlusStore(shop) {
  const raw = String(
    shop?.shopify_plan ?? shop?.shopifyPlan ?? "",
  ).trim();
  if (!raw) return false;
  const lower = raw.toLowerCase().replace(/\s+/g, "_");
  // Shopify REST: plan_name is usually "shopify_plus". Some payloads use "Shopify Plus" or variants.
  if (lower === "shopify_plus") return true;
  if (lower.includes("shopify") && lower.includes("plus")) return true;
  if (lower.endsWith("_plus") && lower.includes("shopify")) return true;
  if (lower.includes("unlimited")) return true;
  return false;
}

const OTPPlacementOptions = ({
  onOtpTypeSelection,
  onSetupClick,
  selectedOtpType,
  hideBackAction = false,
  isOnboardingFlow = false,
}) => {
  const { setting: settingState } = useContext(StoreContext);
  const [setting] = settingState || [{}];
  const [showVideoModal, setShowVideoModal] = useState(false);
  const [selectedVideo, setSelectedVideo] = useState("");
  const [isComparisonExpanded, setIsComparisonExpanded] = useState(false);

  const isTruthy = (value) =>
    value === true || value === "true" || value === 1 || value === "1";
  const isPreOrderActive = isTruthy(setting?.enablePreOrderOtp);
  const isPostOrderActive = isTruthy(setting?.sms);

  useEffect(() => {
    // Default selection once: match whichever flow is already enabled.
    // Do not re-sync when the merchant picks another card — that would lock them on "pre" whenever pre-order is active.
    if (selectedOtpType) return;

    let activeValue = "";
    if (isPostOrderActive) {
      activeValue = "post";
    } else if (isPreOrderActive) {
      activeValue = "pre";
    }

    if (activeValue) {
      onOtpTypeSelection([activeValue]);
    }
  }, [isPostOrderActive, isPreOrderActive, selectedOtpType, onOtpTypeSelection]);

  // Handle Esc key press to close video modal
  const handleKeyDown = useCallback(
    (event) => {
      if (event.key === "Escape" && showVideoModal) {
        setShowVideoModal(false);
      }
    },
    [showVideoModal]
  );

  // Add event listener for Esc key
  useEffect(() => {
    if (showVideoModal) {
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
  }, [showVideoModal, handleKeyDown]);

  const OTP_PLACEMENT_RADIO_NAME = "codkOtpPlacement";

  const otpOptions = [
    {
      value: "pre",
      label: I18n.t("admin.otp_pre_heading"),
      helpText: I18n.t("admin.otp_pre_subheading"),
      setupTime: I18n.t("admin.setup_2min"),
      videoUrl: "https://www.youtube.com/embed/yCPBjrO2tFA",
    },
    {
      value: "post",
      label: I18n.t("admin.otp_post_heading"),
      helpText: I18n.t("admin.otp_post_subheading"),
      setupTime: I18n.t("admin.setup_2min"),
      videoUrl: "https://www.youtube.com/embed/e3zYWQpMhlQ",
    },
  ];

  const handleOtpTypeSelection = (value) => {
    onOtpTypeSelection(value);
  };

  return (
    <Page
      title={
        !isOnboardingFlow ? I18n.t("admin.otp_placement_options") : undefined
      }
      subtitle={
        !isOnboardingFlow ? I18n.t("admin.otp_placement_subtitle") : undefined
      }
      {...(!hideBackAction && {
        backAction: {
          content: I18n.t("admin.back_to_features"),
          onAction: () => navigateTo("/features"),
        },
      })}
    >
      <Layout>
        <Layout.Section>
          {isOnboardingFlow && <QuickCurrentStep currentStep={1} />}

          {/* Collapsible Detailed Comparison at the top */}
          <Box paddingBlockStart="400">
            <Card>
              <Box
                as="button"
                type="button"
                aria-expanded={isComparisonExpanded}
                aria-controls="comparison-collapsible"
                onClick={() => setIsComparisonExpanded(!isComparisonExpanded)}
                padding="400"
                style={{
                  width: "100%",
                  textAlign: "left",
                  cursor: "pointer",
                  border: "none",
                  background: "transparent",
                }}
              >
                <InlineGrid columns="1fr auto" gap="200" alignItems="center">
                  <Text variant="headingMd" as="h3">
                    {I18n.t(
                      "onboarding_otp.placement_options.detailed_comparison"
                    )}
                  </Text>
                  <Icon
                    source={
                      isComparisonExpanded ? CaretUpMinor : CaretDownMinor
                    }
                    tone="subdued"
                  />
                </InlineGrid>
              </Box>

              <Collapsible
                open={isComparisonExpanded}
                id="comparison-collapsible"
                transition={{
                  duration: "200ms",
                  timingFunction: "ease-in-out",
                }}
              >
                <Box padding="400" paddingBlockStart="0">
                  <div style={{ overflowX: "auto" }}>
                    <table
                      style={{ width: "100%", borderCollapse: "collapse" }}
                    >
                      <thead>
                        <tr style={{ borderBottom: "1px solid #E1E3E5" }}>
                          <th
                            style={{
                              padding: "12px",
                              textAlign: "left",
                              fontWeight: "600",
                            }}
                          >
                            {I18n.t("onboarding_otp.placement_options.feature")}
                          </th>
                          <th
                            style={{
                              padding: "12px",
                              textAlign: "center",
                              fontWeight: "600",
                            }}
                          >
                            {I18n.t(
                              "onboarding_otp.placement_options.pre_order_otp"
                            )}
                          </th>
                          <th
                            style={{
                              padding: "12px",
                              textAlign: "center",
                              fontWeight: "600",
                            }}
                          >
                            {I18n.t(
                              "onboarding_otp.placement_options.post_order_otp"
                            )}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {[
                          {
                            feature: I18n.t(
                              "onboarding_otp.placement_options.verification_timing"
                            ),
                            pre: I18n.t(
                              "onboarding_otp.placement_options.before_checkout"
                            ),
                            post: I18n.t(
                              "onboarding_otp.placement_options.after_payment"
                            ),
                          },
                          {
                            feature: I18n.t(
                              "onboarding_otp.placement_options.fake_order_prevention"
                            ),
                            pre: I18n.t(
                              "onboarding_otp.placement_options.excellent"
                            ),
                            post: I18n.t(
                              "onboarding_otp.placement_options.good"
                            ),
                          },
                          {
                            feature: I18n.t(
                              "onboarding_otp.placement_options.implementation_time"
                            ),
                            pre: I18n.t(
                              "onboarding_otp.placement_options.two_minutes"
                            ),
                            post: I18n.t(
                              "onboarding_otp.placement_options.two_minute"
                            ),
                          },
                          {
                            feature: I18n.t(
                              "onboarding_otp.placement_options.sms_whatsapp_support"
                            ),
                            pre: I18n.t("onboarding_otp.placement_options.yes"),
                            post: I18n.t(
                              "onboarding_otp.placement_options.yes"
                            ),
                          },
                          {
                            feature: I18n.t(
                              "onboarding_otp.placement_options.when_verification_triggers"
                            ),
                            pre: I18n.t(
                              "onboarding_otp.placement_options.all_orders"
                            ),
                            post: I18n.t(
                              "onboarding_otp.placement_options.cod_orders_only"
                            ),
                          },
                        ].map((row, index) => (
                          <tr
                            key={index}
                            style={{ borderBottom: "1px solid #F6F6F7" }}
                          >
                            <td style={{ padding: "12px", fontWeight: "500" }}>
                              {row.feature}
                            </td>
                            <td
                              style={{ padding: "12px", textAlign: "center" }}
                            >
                              <InlineGrid
                                columns="auto 1fr"
                                gap="200"
                                alignItems="center"
                              >
                                {/* <Icon source={CheckoutMajor} tone="success" /> */}
                                <Text variant="bodySm">{row.pre}</Text>
                              </InlineGrid>
                            </td>
                            <td
                              style={{ padding: "12px", textAlign: "center" }}
                            >
                              <InlineGrid
                                columns="auto 1fr"
                                gap="200"
                                alignItems="center"
                              >
                                {/* <Icon source={CheckoutMajor} tone="success" /> */}
                                <Text variant="bodySm">{row.post}</Text>
                              </InlineGrid>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </Box>
              </Collapsible>
            </Card>
          </Box>

          <Box paddingBlockStart="400">
            <InlineGrid columns={{ xs: 1, md: 2 }} gap="500">
              {otpOptions.map((option) => {
                const isSelected = selectedOtpType === option.value;
                const isActiveOption =
                  (option.value === "pre" && isPreOrderActive) ||
                  (option.value === "post" && isPostOrderActive);

                const howItWorksSteps =
                  option.value === "post"
                    ? [
                        I18n.t(
                          "onboarding_otp.placement_options.customer_selects_products_checkout",
                        ),
                        I18n.t(
                          "onboarding_otp.placement_options.completes_order",
                        ),
                        I18n.t(
                          "onboarding_otp.placement_options.otp_verification",
                        ),
                        I18n.t(
                          "onboarding_otp.placement_options.attaches_verification_tag",
                        ),
                      ]
                    : [
                        I18n.t("admin.step_1"),
                        I18n.t("admin.step_2"),
                        I18n.t("admin.step_3"),
                        I18n.t("admin.step_4"),
                      ];

                const defaultLabel =
                  option.value === "pre"
                    ? I18n.t("admin.setup_pre_order_otp")
                    : I18n.t("admin.setup_post_order_otp");

                const buttonLabel = isActiveOption
                  ? "Manage Settings"
                  : defaultLabel;

                return (
                  <Card key={option.value}>
                    <Box
                      padding="500"
                      style={{
                        height: "100%",
                        display: "flex",
                        flexDirection: "column",
                        cursor: "pointer",
                      }}
                      onClick={() => handleOtpTypeSelection([option.value])}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          handleOtpTypeSelection([option.value]);
                        }
                      }}
                      role="presentation"
                    >
                      <BlockStack gap="400">
                        <Box
                          onClick={(e) => e.stopPropagation()}
                          style={{ width: "100%" }}
                        >
                          <RadioButton
                            id={`codk-otp-${option.value}`}
                            name={OTP_PLACEMENT_RADIO_NAME}
                            fill
                            label={
                              <BlockStack gap="150">
                                <InlineStack
                                  gap="200"
                                  blockAlign="center"
                                  wrap
                                >
                                  <Text variant="headingMd" as="span">
                                    {option.label}
                                  </Text>
                                  {isActiveOption ? (
                                    <Badge tone="success">
                                      {I18n.t("admin.active", { defaultValue: "Active" })}
                                    </Badge>
                                  ) : null}
                                </InlineStack>
                                <Text
                                  variant="bodySm"
                                  tone="subdued"
                                  as="span"
                                >
                                  {option.helpText}
                                </Text>
                              </BlockStack>
                            }
                            checked={isSelected}
                            onChange={() =>
                              handleOtpTypeSelection([option.value])
                            }
                          />
                        </Box>

                        {option.videoUrl ? (
                          <Box
                            as="button"
                            type="button"
                            style={{
                              border: "1px solid #E1E3E5",
                              borderRadius: "8px",
                              background: `linear-gradient(rgba(0,0,0,0.3), rgba(0,0,0,0.3)), url('https://img.youtube.com/vi/${option.videoUrl.split("/").pop()}/maxresdefault.jpg')`,
                              backgroundSize: "cover",
                              backgroundPosition: "center",
                              cursor: "pointer",
                              width: "100%",
                              height: "120px",
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "center",
                            }}
                            onClick={(e) => {
                              e.stopPropagation();
                              setSelectedVideo(
                                option.videoUrl + "?autoplay=1",
                              );
                              setShowVideoModal(true);
                            }}
                          >
                            <Icon source={PlayCircleMajor} tone="inverse" />
                          </Box>
                        ) : null}

                        <BlockStack gap="300">
                          <Text variant="headingSm" as="h4">
                            {I18n.t(
                              "onboarding_otp.placement_options.how_it_works",
                            )}
                          </Text>
                          <BlockStack gap="200">
                            {howItWorksSteps.map((step, index) => (
                              <InlineGrid
                                key={index}
                                columns="auto 1fr"
                                gap="200"
                                alignItems="center"
                              >
                                <Badge size="small">{index + 1}</Badge>
                                <Text variant="bodySm">{step}</Text>
                              </InlineGrid>
                            ))}
                          </BlockStack>
                        </BlockStack>

                        <Box
                          padding="300"
                          background="bg-surface-secondary"
                          borderRadius="200"
                        >
                          <InlineGrid
                            columns="auto 1fr"
                            gap="200"
                            alignItems="center"
                          >
                            <Icon source={ClockMajor} tone="subdued" />
                            <Text variant="bodySm" tone="subdued">
                              {I18n.t(
                                "onboarding_otp.placement_options.setup_time",
                              )}{" "}
                              {option.setupTime}
                            </Text>
                          </InlineGrid>
                        </Box>

                        <Box paddingBlockStart="400">
                          <BlockStack gap="200">
                            <Button
                              variant="primary"
                              size="large"
                              fullWidth
                              disabled={!isSelected}
                              onClick={(e) => {
                                e.stopPropagation();
                                handleOtpTypeSelection([option.value]);
                                onSetupClick();
                              }}
                            >
                              {buttonLabel}
                            </Button>
                          </BlockStack>
                        </Box>
                      </BlockStack>
                    </Box>
                  </Card>
                );
              })}
            </InlineGrid>
          </Box>
        </Layout.Section>

      </Layout>

      <Modal
        open={showVideoModal}
        onClose={() => setShowVideoModal(false)}
        title={I18n.t("admin.watch_video")}
        size="fullScreen"
        backdrop={true}
      >
        <Modal.Section>
          <div
            style={{
              position: "relative",
              paddingBottom: "56.25%", // 16:9
              height: 0,
              overflow: "hidden",
              width: "100%",
            }}
          >
            <iframe
              src={selectedVideo}
              title={I18n.t("admin.video_player")}
              frameBorder="0"
              allow="autoplay; encrypted-media"
              allowFullScreen
              style={{
                position: "absolute",
                top: 0,
                left: 0,
                width: "100%",
                height: "100%",
              }}
            />
          </div>
        </Modal.Section>
      </Modal>
    </Page>
  );
};

export default OTPPlacementOptions;

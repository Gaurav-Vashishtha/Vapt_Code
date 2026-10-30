import {
  Card,
  Box,
  Text,
  Badge,
  Spinner,
  BlockStack,
  InlineStack,
  Button,
  Collapsible,
} from "@shopify/polaris";
import useApi from "../Hooks/useApi";
import React, { useEffect, useState, useContext } from "react";
import Recommended from "./Recommended";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";

function PostOrderOTPWizard() {
  const {
    shop: [shop],
  } = useContext(StoreContext);
  const [isNewTypOspActive, setIsNewTypOspActive] = useState(false);
  const [shopProfileId, setShopProfileId] = useState(0);
  const [expandedCard, setExpandedCard] = useState(null);

  const [
    { data: profileData, loading: profileDataLoading },
    getCheckoutProfile,
  ] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/get_published_checkout_profile`,
      method: "GET",
    },
    { manual: true }
  );

  const loadCheckoutProfile = () => {
    getCheckoutProfile()
      .then((resp) => {
        setIsNewTypOspActive(
          resp?.data?.checkoutProfile?.typOspPagesActive || false
        );
        setShopProfileId(resp?.data?.checkoutProfile?.id || 0);
      })
      .catch(() => {});
  };

  useEffect(() => {
    loadCheckoutProfile();
  }, []);

  const StepCard = ({
    step,
    title,
    page,
    url,
    videoId,
    isExpanded,
    onToggle,
  }) => (
    <Card>
      <Box padding="300">
        <BlockStack gap="200">
          <InlineStack gap="200" align="space-between">
            <InlineStack gap="200" align="left">
              <Text as="h3" variant="headingSm" fontWeight="semibold">
                {step}. {title}
              </Text>
              <Badge status="attention" size="small">
                {I18n.t("post_order_otp_wizard.required")}
              </Badge>
            </InlineStack>
            <Button
              variant="plain"
              size="micro"
              onClick={onToggle}
              textAlign="left"
            >
              {isExpanded
                ? I18n.t("post_order_wizard.hide_instructions")
                : I18n.t("post_order_wizard.show_instructions")}
            </Button>
          </InlineStack>

          <Button variant="primary" size="medium" url={url} external fullWidth>
            {I18n.t("post_order_wizard.open_settings", { page })}
          </Button>

          <Collapsible open={isExpanded} id={`step-${step}`}>
            <Box paddingBlockStart="200">
              <BlockStack gap="100">
                <Text variant="bodySm" tone="subdued">
                  {I18n.t("post_order_wizard.quick_steps")}
                </Text>
                <Text variant="bodySm">
                  {I18n.t("post_order_wizard.find_app_blocks")}
                </Text>
                <Text variant="bodySm">
                  {I18n.t("post_order_wizard.click_otp_block")}
                </Text>
                <Text variant="bodySm">
                  {I18n.t("post_order_wizard.click_save")}
                </Text>
                {videoId && (
                  <Box marginBlockStart="200">
                    <Box width="100%" style={{ maxWidth: 400 }}>
                      <iframe
                        src={`https://drive.google.com/file/d/${videoId}/preview`}
                        width="100%"
                        height="240"
                        allow="autoplay"
                        style={{ border: "none", borderRadius: "8px" }}
                        title={`${page} Instructions`}
                      />
                    </Box>
                  </Box>
                )}
              </BlockStack>
            </Box>
          </Collapsible>
        </BlockStack>
      </Box>
    </Card>
  );

  if (profileDataLoading) {
    return (
      <Box
        padding="400"
        display="flex"
        alignItems="center"
        justifyContent="center"
      >
        <InlineStack gap="200" align="center">
          <Spinner size="small" />
          <Text variant="bodyMd" tone="subdued">
            {I18n.t("post_order_otp_wizard.loading")}
          </Text>
        </InlineStack>
      </Box>
    );
  }

  if (!isNewTypOspActive) {
    return <Recommended />;
  }

  return (
    <BlockStack gap="300">
      <Box paddingBlockEnd="200">
        <Badge status="attention" size="large">
          {I18n.t("post_order_otp_wizard.enable_otp_extensions_in_your_theme")}
        </Badge>
      </Box>

      <BlockStack gap="200">
        <StepCard
          step={1}
          title={I18n.t("post_order_otp.thank_you_page")}
          page="Thank You"
          url={`https://${shop.shopify_domain}/admin/settings/checkout/editor/profiles/${shopProfileId}?page=thank-you&context=extensibility&extensionPicker=true`}
          videoId="1poa0yULxvr8xXfsvwDAwwYymIeHpzs0z"
          isExpanded={expandedCard === 1}
          onToggle={() => setExpandedCard(expandedCard === 1 ? null : 1)}
        />

        <StepCard
          step={2}
          title={I18n.t("post_order_otp.order_status_page")}
          page={I18n.t("post_order_wizard.order_status")}
          url={`https://${shop.shopify_domain}/admin/settings/checkout/editor/profiles/${shopProfileId}?page=order-status&context=extensibility&extensionPicker=true`}
          videoId="178RX98azlQ582_Un_30pw4Phn4WF3aLF"
          isExpanded={expandedCard === 2}
          onToggle={() => setExpandedCard(expandedCard === 2 ? null : 2)}
        />
      </BlockStack>
    </BlockStack>
  );
}

export default PostOrderOTPWizard;

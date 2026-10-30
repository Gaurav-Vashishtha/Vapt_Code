import React, {
  useState,
  useCallback,
  useContext,
  Suspense,
  useEffect,
  useRef,
} from "react";
// 1. Correct Import for App Bridge v4
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import Api from "../Services/Api";
import { camelizeKeys } from "humps";
import axios from "axios";
import { StoreContext } from "../Context/Store";
import {
  Layout,
  Page,
  BlockStack,
  InlineGrid,
  InlineStack,
  Box,
  Card,
  Form,
  FormLayout,
  Checkbox,
  Banner,
  TextField,
  Button,
  Link,
  Select,
  Text,
  Badge,
  SkeletonBodyText,
  SkeletonPage,
  SkeletonDisplayText,
  ButtonGroup,
  Icon,
  Divider,
  useBreakpoints,
} from "@shopify/polaris";
import {
  CircleInformationMajor,
  MobileAcceptMajor,
  CircleTickMajor,
} from "@shopify/polaris-icons";
import TestOtp from "./TestOtp";
import I18n from "../i18n-lang";
import FeatureCallout from "./FeatureCallout";

const COD_FEES_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.13_PM_1.jpg?v=1791392886";
import useApi from "../Hooks/useApi";
import { debugLog } from "../Modal/utilities/otpUtils";

const RecommendedCODFeeCheckout = React.lazy(() =>
  import(
    /* webpackMode: "lazy", webpackChunkName: "cod-fee-loader" */
    "./RecommendedCODFeeCheckout"
  )
);
import EmailSetup from "./EmailSetup";
import { FreePlanFormNote } from "../Pages/CodForm/components/LimitCodNotes";

const CODFeesSettings = () => {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const { smUp } = useBreakpoints();
  const settingRef = useRef();
  
  const {
    loading: [loading, setLoading],
    plan: [plan, setPlan],
    shop: [shop, setShop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const [isDirty, setIsDirty] = useState(false);
  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;

  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  // Options for Fee Type
  const options = [
    { label: I18n.t("cod_fees_settings.fixed_amount"), value: "false" }, // Stringified to work with Select
    { label: I18n.t("cod_fees_settings.percentage_of_order_amount"), value: "true" },
  ];

  /**
   * App Bridge v4 Navigation Handler
   */
  const handleRedirect = (path) => {
    window.history.pushState({}, '', path);
    window.dispatchEvent(new PopStateEvent('popstate'));
  };

  const handleSettingChange = (key) => (value) => {
    const updatedValue = key === "isPercentage" ? (value === "true") : value;
    setSetting({
      ...setting,
      [key]: updatedValue,
    });
    setIsDirty(true);
  };

  const [wizardStep, setWizardStep] = useState(1);
  const handleNextButton = (step) => () => setWizardStep(step);

  /**
   * REFACTORED: Submit Logic for v4
   */
  const handleSubmit = useCallback(async () => {
    setLoading(true);
    try {
      const response = await Api.post("/settings", settingRef.current);
      setIsDirty(false);
      setSetting(response.data);
      setOriginalSetting(response.data);
      shopify.toast.show(I18n.t("admin.settings_saved"));
    } catch (error) {
      debugLog(error);
    } finally {
      setLoading(false);
    }
  }, [shopify, setSetting, setOriginalSetting, setLoading]);

  const handleDiscard = useCallback(() => {
    setSetting(originalSetting);
    setIsDirty(false);
  }, [originalSetting, setSetting]);

  // Loading skeleton – matches COD Fees: wizard steps (2 buttons) + 2fr 5fr form sections
  if (!setting || !plan) {
    return (
      <SkeletonPage primaryAction>
        <BlockStack gap={{ xs: "800", sm: "400" }}>
          <Box paddingInlineStart={{ xs: 400, sm: 0 }} paddingInlineEnd={{ xs: 400, sm: 0 }}>
            <InlineStack gap="200">
              <SkeletonBodyText lines={1} />
              <SkeletonBodyText lines={1} />
            </InlineStack>
          </Box>
          <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
            <Box as="section">
              <BlockStack gap="400">
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
            <Box as="section">
              <BlockStack gap="400">
                <SkeletonDisplayText size="small" />
                <SkeletonBodyText lines={1} />
              </BlockStack>
            </Box>
            <Card roundedAbove="sm">
              <Box padding="400">
                <BlockStack gap="200">
                  <SkeletonBodyText lines={2} />
                  <SkeletonBodyText lines={1} />
                </BlockStack>
              </Box>
            </Card>
          </InlineGrid>
        </BlockStack>
      </SkeletonPage>
    );
  }

  return (
    <Page
      divider
      title={I18n.t("cod_fees.cod_fees_page_name")}
      subtitle={I18n.t("cod_fees_missing.configure_cod_fees_subtitle")}
    >
      {/* 2. Declarative SaveBar for App Bridge v4 */}
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

      <BlockStack gap={{ xs: "800", sm: "400" }}>
        <Box paddingInlineStart={{ xs: 400, sm: 0 }} paddingInlineEnd={{ xs: 400, sm: 0 }}>
          <FeatureCallout
            illustration="payments"
            image={COD_FEES_CALLOUT_IMAGE}
            title={I18n.t("cod_fees.cod_fees_page_name")}
            description={I18n.t("cod_fees_missing.configure_cod_fees_subtitle")}
            docsUrl="https://codking.notion.site/Step-by-Step-Guide-for-setting-up-COD-fees-for-your-Shopify-store-12e6e71a63f980faa519e4dc35f617b7"
            videoUrl="https://youtu.be/I22U3fj6vKo?si=sJ5ZfDo4Am_jCX5y"
            showChat
            badge={
              setting?.codFeeEnabled ? (
                <Badge tone="success" progress="complete">
                  {I18n.t("pre_order.enabled")}
                </Badge>
              ) : (
                <Badge tone="attention" progress="incomplete">
                  {I18n.t("pre_order.inactive")}
                </Badge>
              )
            }
          />
        </Box>

        {/* Warning Banner for Free Plan */}
        {!setting.locked &&
          setting.codFeeEnabled === true &&
          (plan.name == "Free" || !shop.charge_id) && (
            <Banner
              title={I18n.t("cod_fees_missing.test_mode_title")}
              status="warning"
              action={{
                content: I18n.t("cod_fees_missing.upgrade_now"),
                onAction: () => handleRedirect("/subscription")
              }}
            >
              <div
                dangerouslySetInnerHTML={{
                  __html: I18n.t("cod_fees_missing.test_mode_message"),
                }}
              />
            </Banner>
          )}

        {/* COD Form: on the Free plan the fee applies to form orders */}
        <FreePlanFormNote
          feature="cod_fees"
          isFreePlan={plan.name == "Free" || !shop.charge_id}
        />

        {/* Wizard Navigation */}
        <Box paddingInlineStart={{ xs: 400, sm: 0 }} paddingInlineEnd={{ xs: 400, sm: 0 }}>
          <ButtonGroup>
            <Button
              size={wizardStep == 1 ? "medium" : "slim"}
              outline={wizardStep !== 1}
              onClick={handleNextButton(1)}
            >
              {I18n.t("cod_fees_settings.1_activate_cod_fees")}
            </Button>
            <Button
              size={wizardStep == 2 ? "medium" : "slim"}
              outline={wizardStep !== 2}
              onClick={handleNextButton(2)}
            >
              {I18n.t("cod_fees_settings.2_configure_cod_fees_email")}
            </Button>
          </ButtonGroup>
        </Box>

        {wizardStep == 1 && (
          <>
            <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
              <Box as="section">
                <BlockStack gap="400">
                  <Text as="h3" variant="headingMd">{I18n.t("cod_fees_settings.cod_fees_activation")}</Text>
                  <Text variant="bodyMd">{I18n.t("cod_fees_settings.enable_cash_on_delivery_fees_for")}</Text>
                </BlockStack>
              </Box>
              <Card roundedAbove="sm">
                <Checkbox
                  label={<span dangerouslySetInnerHTML={{ __html: I18n.t("admin.activate_cod_fees") }} />}
                  checked={setting.codFeeEnabled}
                  onChange={handleSettingChange("codFeeEnabled")}
                />
              </Card>
            </InlineGrid>

            {smUp ? <Divider /> : null}

            <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
              <Box as="section">
                <BlockStack gap="400">
                  <Text as="h3" variant="headingMd">{I18n.t("cod_fees_settings.fee_configuration")}</Text>
                </BlockStack>
              </Box>
              <Card roundedAbove="sm">
                <BlockStack gap="400">
                  <Select
                    label={I18n.t("cod_fees_settings.fee_type")}
                    options={options}
                    onChange={handleSettingChange("isPercentage")}
                    value={setting.isPercentage.toString()}
                  />
                  <TextField
                    label={"Fee amount in " + (setting.isPercentage ? "%" : shop.currency)}
                    value={setting.codFees}
                    onChange={handleSettingChange("codFees")}
                    type="number"
                    helpText={I18n.t("admin.cod_fees_help")}
                    autoComplete="off"
                  />
                </BlockStack>
              </Card>
            </InlineGrid>
            
            {smUp ? <Divider /> : null}

            <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
              <Box as="section">
                <BlockStack gap="400">
                  <Text as="h3" variant="headingMd">{I18n.t("cod_fees_settings.customer_display")}</Text>
                </BlockStack>
              </Box>
              <Card roundedAbove="sm">
                <BlockStack gap="400">
                  <TextField
                    label={I18n.t("cod_fees_settings.payment_name_in_checkout")}
                    value={setting.codLabel}
                    onChange={handleSettingChange("codLabel")}
                    placeholder={"Cash on delivery - Extra " + setting.codFees}
                    maxLength={100}
                    showCharacterCount
                    autoComplete="off"
                  />
                  <TextField
                    label={I18n.t("admin.cod_instruction")}
                    value={setting.codInstrutction}
                    onChange={handleSettingChange("codInstrutction")}
                    multiline={2}
                    maxLength={150}
                    showCharacterCount
                    autoComplete="off"
                  />
                </BlockStack>
              </Card>
            </InlineGrid>
          </>
        )}

        {wizardStep == 2 && (
          <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
            <Box as="section">
              <BlockStack gap="400">
                <Text as="h3" variant="headingMd">{I18n.t("cod_fees_settings.email_configuration")}</Text>
              </BlockStack>
            </Box>
            <Card roundedAbove="sm">
              <Suspense fallback={<SkeletonBodyText lines={4} />}>
                <EmailSetup setting={setting} />
              </Suspense>
            </Card>
          </InlineGrid>
        )}
      </BlockStack>
    </Page>
  );
};

export default CODFeesSettings;
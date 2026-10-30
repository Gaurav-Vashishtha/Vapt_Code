import React, {
  useState,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useMemo,
} from "react";
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  Layout,
  Card,
  Button,
  Checkbox,
  Select,
  TextField,
  Text,
  Box,
  BlockStack,
  InlineStack,
  Banner,
  Badge,
  Divider,
  FormLayout,
  Link,
  Popover,
  OptionList,
  Tag,
  Icon,
  Spinner,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import { ExternalMinor, RefreshMinor } from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
import I18n from "../i18n-lang";
import AppEmbedTutorial from "./AppEmbedTutorial";
import useApi from "../Hooks/useApi";
import countries from "./Country";
import FreeWalletBalance from "./FreeWalletBalance";
import UiCustomizationEditor, {
  UiCustomizationSectionList,
} from "./CheckoutPreview/UiCustomizationEditor";
import { SectionCard, SettingRow } from "./SettingsPrimitives";
import FeatureCallout from "./FeatureCallout";
import { debugLog } from "../Modal/utilities/otpUtils";
import { navigateTo } from "../../utils/navigate";
import QuickBilling from "./QuickBilling";
import QuickCurrentStep from "./QuickCurrentStep";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import { hasNoChargeId } from "../utils/shopUtils";

// The three screens the rail switches between: the catalog groups tagged with
// each one, and the preview step it maps onto.
// Shown in the callout panel at 290x210.
const PRE_ORDER_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-10_at_12.32.58_PM.jpg?v=1790777625";

const WIDGET_DOCS_URL = "https://codking.tech/documentation/";
const WIDGET_VIDEO_URL = "https://youtu.be/yCPBjrO2tFA";

// SettingWrapper passes 1 for /features/ui-customization.
const UI_ROUTE_TAB = 1;

const PreOrderSetting = ({ onBackToSettings, isOnboardingFlow, activeTab = 0 }) => {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    banner: [, setBanner],
    contextualBar: [contextualBar, setContextualBar],
    shop: [shop],
    plan: [plan],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
  } = useContext(StoreContext);

  const isEnterprisePlus = plan?.name === "Enterprise Plus";
  const isPaidPlan = useMemo(() => {
    const planName = String(plan?.name || "").toLowerCase();
    if (!planName) return false;
    return planName !== "free" && !hasNoChargeId(shop);
  }, [plan?.name, shop]);
  // Mirrors UiCustomizationPlanGuard on the backend — the server drops writes
  // and stops shipping overrides to the storefront for any other plan.

  // Gating is shown, never hidden: fields stay visible but disabled, with a
  // badge and a link to whatever unblocks them.

  const goToSubscription = useCallback((e) => {
    if (e) e.preventDefault();
    navigateTo("/subscription");
  }, []);

  // State management
  const [selectedCountries, setSelectedCountries] = useState(
    setting.countryCodeList || ""
  );
  const [popoverActive, setPopoverActive] = useState(false);
  const [geoPopoverActive, setGeoPopoverActive] = useState(false);
  const [selectedOtpScreen, setSelectedOtpScreen] = useState(0);
  const [isSaving, setIsSaving] = useState(false);
  const [isExtensionEnabled, setIsExtensionEnabled] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isCheckingTheme, setIsCheckingTheme] = useState(false);
  const [isRefreshingTheme, setIsRefreshingTheme] = useState(false);
  const [themeCheckInterval, setThemeCheckInterval] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchGeoQuery, setGeoSearchQuery] = useState("");
  const [preGeoCountriesStr, setPreGeoCountriesStr] = useState(
    setting?.preGeoCountries || ""
  );
  const [isPrefilledEnabled, setIsPrefilledEnabled] = useState(
    setting.isPrefilledAddressEnabled
  );
  const whatsappEnabledCountry = process.env.WHATSAPP_COUNTRIES.split(
    ","
  ).includes(shop.country_code);
  const checkCountRef = useRef(0);
  const hasInitialFetchRun = useRef(false);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);
  const [isDirty, setIsDirty] = useState(false);

  // API hooks
  const [{ data: paymentMethods }, getPaymentMethods] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/payment_methods`,
      method: "GET",
    },
    { manual: true }
  );
  const [{ data: productUrlData, loading: productUrlLoading, error: productUrlError }, getProductUrl] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/product_url`,
      method: "GET",
    },
    { manual: true }
  );

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  useEffect(() => {
    if (!setting.enablePreOrderOtp && isPrefilledEnabled) {
      setIsPrefilledEnabled(false);
      setSetting((prev) => ({
        ...prev,
        isPrefilledAddressEnabled: false,
      }));
    }
  }, [setting.enablePreOrderOtp, isPrefilledEnabled, setSetting]);

  // Function to check theme integration status
  const checkThemeIntegration = useCallback(async () => {
    try {
      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shop.shopify_domain}`
      );
      const data = await response.json();
      if (data.assetEnabled !== isExtensionEnabled) {
        const wasExtensionEnabled = isExtensionEnabled;
        setIsExtensionEnabled(data.assetEnabled);

        if (data.assetEnabled) {
          setIsCheckingTheme(false);
          if (themeCheckInterval) {
            clearInterval(themeCheckInterval);
            setThemeCheckInterval(null);
          }
        } else if (wasExtensionEnabled && !data.assetEnabled) {
          // Extension became disabled, disable pre-order OTP
          const updatedSetting = {
            ...setting,
            enablePreOrderOtp: false,
          };
          setSetting(updatedSetting);

          // Save settings automatically
          try {
            const response = await Api.post("/settings", { setting: updatedSetting });
            setSetting(response.data);
            setOriginalSetting(response.data);
            setBanner({
              active: true,
              status: "warning",
              text: I18n.t("pre_order.theme_integration_disabled_saved"),
            });
          } catch (error) {
            console.error("Error saving settings:", error);
          }
        }
      }
      return data.assetEnabled;
    } catch (error) {
      console.error("Error checking theme integration:", error);
      return false;
    }
  }, [
    shop.shopify_domain,
    isExtensionEnabled,
    setBanner,
    setSetting,
    themeCheckInterval,
  ]);

  // Manual refresh function for theme integration status
  const handleRefreshThemeStatus = useCallback(async () => {
    setIsRefreshingTheme(true);
    try {
      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shop.shopify_domain}`
      );
      const data = await response.json();

      setIsExtensionEnabled(data.assetEnabled);

      // If extension is disabled, ensure pre-order OTP is also disabled and saved
      if (!data.assetEnabled && setting.enablePreOrderOtp) {
        const updatedSetting = {
          ...setting,
          enablePreOrderOtp: false,
        };
        setSetting(updatedSetting);

        // Save settings automatically
        try {
          const saveResponse = await Api.post("/settings", { setting: updatedSetting });
          setSetting(saveResponse.data);
          setOriginalSetting(saveResponse.data);
        } catch (error) {
          console.error("Error saving settings on refresh:", error);
        }
      }

      if (data.assetEnabled) {
        setBanner({
          active: true,
          status: "success",
          text: I18n.t("pre_order.theme_integration_detected"),
        });
      } else {
        setBanner({
          active: true,
          status: "info",
          text: I18n.t("pre_order.theme_integration_not_detected"),
        });
      }
    } catch (error) {
      setBanner({
        active: true,
        status: "critical",
        text: I18n.t("pre_order.error_checking_theme"),
      });
    } finally {
      setIsRefreshingTheme(false);
    }
  }, [shop.shopify_domain, setting.enablePreOrderOtp, setSetting, setBanner]);

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
  const handleSettingChange = useCallback(
    (key) => (value) => {
      if (key === "countryCodeList") {
        const newSelectedCountries = Array.isArray(value)
          ? value.join(",")
          : value;
        setSelectedCountries(newSelectedCountries);
        setSetting((prev) => ({ ...prev, [key]: newSelectedCountries }));
      } else if (key === "preGeoCountries") {
        const newValue = Array.isArray(value) ? value.join(",") : value;
        setPreGeoCountriesStr(newValue);
        setSetting((prev) => ({ ...prev, [key]: newValue.toLowerCase() }));
      } else if (key === "isPrefilledAddressEnabled") {
        setIsPrefilledEnabled(value);
        setSetting((prev) => ({ ...prev, [key]: value }));
      } else if (key === "hide_for_unverified_orders") {
        setSetting((prev) => ({
          ...prev,
          hide_for_unverified_orders: value,
          hideForUnverifiedOrders: value,
        }));
      } else if (key === "optimized_buy_now") {
        setSetting((prev) => ({
          ...prev,
          optimized_buy_now: value,
          optimizedBuyNow: value,
        }));
      } else {
        setSetting((prev) => ({ ...prev, [key]: value }));
      }
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar]
  );

  // Nested update handler for the COD form config (placeholders / GST sub-objects).
  const [uiModalOpen, setUiModalOpen] = useState(false);
  const [uiSectionToOpen, setUiSectionToOpen] = useState(null);
  // /features/ui-customization and /features/otp/pre-order share this
  // component but are different screens.
  const isUiScreen = activeTab === UI_ROUTE_TAB;

  // Sidebar navigation between the two entry points must never leave the modal
  // hanging over the screen the merchant just asked for.
  useEffect(() => {
    setUiModalOpen(false);
  }, [activeTab]);

  // Submit handler
  const handleSubmit = useCallback(async () => {
    setIsSaving(true);
    try {
      const response = await Api.post("/settings", { setting });
      setSetting(response.data);
      setOriginalSetting(response.data);
      setContextualBar(false);
      setIsDirty(false);
      shopify.toast.show(I18n.t("pre_order.settings_saved"));
      setBanner({
        active: true,
        status: "success",
        text: I18n.t("pre_order.settings_saved"),
      });
    } catch (error) {
      console.error(error);
      shopify.toast.show(I18n.t("pre_order.save_error"), { isError: true });
      setBanner({
        active: true,
        status: "critical",
        text: I18n.t("pre_order.save_error"),
      });
    } finally {
      setIsSaving(false);
    }
  }, [setting, setSetting, setOriginalSetting, setContextualBar, setBanner, shopify]);

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setIsPrefilledEnabled(cloned.isPrefilledAddressEnabled);
    setContextualBar(false);
    setIsDirty(false);
  }, [originalSetting, setSetting, setContextualBar]);

  // Initial data fetch - only run once on mount
  useEffect(() => {
    if (hasInitialFetchRun.current) return;
    hasInitialFetchRun.current = true;

    Promise.allSettled([
      checkThemeIntegration(),
      getPaymentMethods(),
      getProductUrl(),
    ]).finally(() => {
      setIsLoading(false);

      // Track page load if in onboarding flow
      if (isOnboardingFlow) {
        journeyTracker.trackPageLoad({
          step: 2,
          feature: "pre-order-otp",
          isOnboardingFlow: true,
        });
      }
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Empty dependency array - only run once on mount

  // Handle product URL error state
  useEffect(() => {
    if (productUrlError) {
      console.error(
        I18n.t("onboarding_otp.error.product_url_fetch_error", { defaultValue: "Failed to fetch product URL" }),
        productUrlError
      );
    }
    if (productUrlData?.error) {
      console.warn(
        "Product URL fetch returned error:",
        productUrlData.message || "No active products found"
      );
    }
  }, [productUrlError, productUrlData]);

  // Cleanup interval on unmount
  useEffect(() => {
    return () => {
      if (themeCheckInterval) {
        clearInterval(themeCheckInterval);
      }
    };
  }, [themeCheckInterval]);

  // Helper functions
  const togglePopoverActive = useCallback(
    () => setPopoverActive((active) => !active),
    []
  );
  const toggleGeoPopoverActive = useCallback(
    () => setGeoPopoverActive((active) => !active),
    []
  );
  const filteredCountries = countries.filter((country) =>
    country.label.toLowerCase().includes(searchQuery.toLowerCase())
  );
  const filteredGeoCountries = countries.filter((country) =>
    country.label.toLowerCase().includes(searchGeoQuery.toLowerCase())
  );
  const parsedCountries = preGeoCountriesStr
    ? preGeoCountriesStr.split(",")
    : [];

  // Handle theme integration button click
  const handleThemeIntegrationClick = () => {
    // Track theme integration click
    journeyTracker.trackButtonClick("theme_integration", {
      step: 2,
      feature: "pre-order-otp",
      isOnboardingFlow: isOnboardingFlow,
      shopDomain: shop.shopify_domain,
    });

    startThemeMonitoring();
    window.open(
      `https://${shop.shopify_domain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`,
      "_blank"
    );
  };

  const isOnlyIndiaSelected = useMemo(() => {
    if (!selectedCountries) return false;
    const countries = selectedCountries
      .split(",")
      .map((c) => c.trim().toUpperCase());
    return countries.length === 1 && countries[0] === "IN";
  }, [selectedCountries]);

  // Loading skeleton – one screen of cards, same as the loaded page.
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
                  <Divider />
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={1} />
                </BlockStack>
              </Card>
              <Card padding="600">
                <BlockStack gap="300">
                  <SkeletonDisplayText size="small" />
                  <SkeletonBodyText lines={4} />
                </BlockStack>
              </Card>
            </BlockStack>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  // The callout introduces the feature; turning it on is a decision of its own,
  // so it gets its own row rather than riding on the illustration card.
  const renderOtpActivationCard = () => (
    <SectionCard>
      <SettingRow
        title={I18n.t("pre_order.activate_otp_verification")}
        description={I18n.t("pre_order.activate_otp_help")}
        control={
          <InlineStack gap="200" blockAlign="center">
            {(isCheckingTheme || isRefreshingTheme) && <Spinner size="small" />}
            <Checkbox
              label={I18n.t("pre_order.activate_otp_verification")}
              labelHidden
              checked={setting.enablePreOrderOtp || false}
              onChange={handleSettingChange("enablePreOrderOtp")}
              disabled={!isExtensionEnabled}
            />
          </InlineStack>
        }
      />
    </SectionCard>
  );

  const renderWidgetHubCard = () => (
    <FeatureCallout
      title={
        isUiScreen
          ? I18n.t("pre_order.checkout_widget_title")
          : I18n.t("pre_order.otp_feature_title")
      }
      description={
        isUiScreen
          ? I18n.t("pre_order.checkout_widget_help")
          : I18n.t("pre_order.otp_feature_help")
      }
      illustration={isUiScreen ? "uiCustomize" : "widget"}
      image={isUiScreen ? undefined : PRE_ORDER_CALLOUT_IMAGE}
      docsUrl={WIDGET_DOCS_URL}
      videoUrl={WIDGET_VIDEO_URL}
      badge={
        !isExtensionEnabled ? (
          <Badge tone="disabled">{I18n.t("pre_order.waiting")}</Badge>
        ) : setting.enablePreOrderOtp ? (
          <Badge tone="success" progress="complete">
            {I18n.t("pre_order.enabled")}
          </Badge>
        ) : (
          <Badge tone="attention" progress="incomplete">
            {I18n.t("pre_order.inactive")}
          </Badge>
        )
      }
      actions={
        isExtensionEnabled ? (
          <Button variant="primary" onClick={() => setUiModalOpen(true)}>
            {I18n.t("pre_order.customize")}
          </Button>
        ) : (
          <>
            <Button
              variant="primary"
              icon={ExternalMinor}
              onClick={handleThemeIntegrationClick}
              loading={isCheckingTheme}
            >
              {I18n.t("pre_order.enable")}
            </Button>
            <Button
              icon={RefreshMinor}
              loading={isRefreshingTheme}
              onClick={() => {
                journeyTracker.trackButtonClick("refresh_theme_status", {
                  step: 2,
                  feature: "pre-order-otp",
                  isOnboardingFlow: isOnboardingFlow,
                });
                handleRefreshThemeStatus();
              }}
            >
              {isRefreshingTheme
                ? I18n.t("pre_order.checking")
                : I18n.t("pre_order.refresh")}
            </Button>
          </>
        )
      }
    />
  );

  // Checkout behaviour: which payment method to match, how orders are tagged,
  // and where verification applies. Nothing here changes how the widget looks.
  const renderOtpAdvancedSection = () => (
    <>
      <SectionCard
        title={I18n.t("pre_order.advanced_payment_card_title", {
          defaultValue: "Payment method and order tagging",
        })}
        description={I18n.t("pre_order.advanced_payment_card_help", {
          defaultValue:
            "Which method at checkout counts as cash on delivery, and the tag put on an order once its number is verified.",
        })}
      >
        <FormLayout>
          <Select
            label={I18n.t("pre_order.select_payment_method")}
            options={
              paymentMethods?.paymentMethods?.map((method) => ({
                value: method.value,
                label: method.label,
              })) || []
            }
            helpText={I18n.t("pre_order.select_cod_payment_2")}
            onChange={handleSettingChange("paymentMethodName")}
            value={setting.paymentMethodName || ""}
          />
          <TextField
            label={I18n.t("admin.verification_tag_label")}
            helpText={I18n.t("admin.verification_tag_help")}
            value={setting.verificationTag || ""}
            onChange={handleSettingChange("verificationTag")}
          />
        </FormLayout>
      </SectionCard>

      <SectionCard
        title={I18n.t("pre_order.advanced_shipping_card_title", {
          defaultValue: "Shipping method",
        })}
        description={I18n.t("pre_order.advanced_shipping_card_help", {
          defaultValue:
            "Hide the cash on delivery rate until a shopper has verified, so an unverified order cannot pick it.",
        })}
      >
        <FormLayout>
          <Checkbox
            label={I18n.t("pre_order.hide_cod_shipping")}
            helpText={I18n.t("pre_order.hide_cod_shipping_help")}
            checked={setting.hideShippingMethod || false}
            onChange={handleSettingChange("hideShippingMethod")}
          />
          <TextField
            label={I18n.t("pre_order.shipping_rate_keyword")}
            value={setting.codFeeShippingKeyword || ""}
            disabled={!setting.hideShippingMethod}
            onChange={handleSettingChange("codFeeShippingKeyword")}
            helpText={I18n.t("pre_order.cod_fee_shipping_keyword_help")}
          />
          <Checkbox
            label={I18n.t("pre_order.hide_for_unverified_orders")}
            helpText={I18n.t("pre_order.hide_for_unverified_orders_help")}
            checked={
              setting.hideForUnverifiedOrders === true ||
              setting.hide_for_unverified_orders === true
            }
            onChange={handleSettingChange("hide_for_unverified_orders")}
          />
        </FormLayout>
      </SectionCard>

      <SectionCard
        title={I18n.t("pre_order.advanced_reach_card_title", {
          defaultValue: "Where verification applies",
        })}
        description={I18n.t("pre_order.advanced_reach_card_help", {
          defaultValue:
            "Limit verification to the countries you ship to, and skip numbers you never want to send a code to.",
        })}
      >
        <FormLayout>
          <Text variant="bodyMd" as="p">
            {I18n.t("pre_order.select_countries")}
          </Text>
          {parsedCountries.length === 0 ? (
            <Box>
              <Tag>{I18n.t("pre_order.all_countries")}</Tag>
            </Box>
          ) : (
            <Box>
              <Tag>{preGeoCountriesStr}</Tag>
            </Box>
          )}
          <Popover
            active={geoPopoverActive}
            activator={
              <Button
                onClick={() => {
                  journeyTracker.trackButtonClick("select_countries", {
                    step: 2,
                    feature: "pre-order-otp",
                    isOnboardingFlow: isOnboardingFlow,
                  });
                  toggleGeoPopoverActive();
                }}
                disclosure
              >
                {I18n.t("pre_order.select_countries_button")}
              </Button>
            }
            onClose={toggleGeoPopoverActive}
          >
            <Popover.Pane fixed>
              <Box padding="200">
                <TextField
                  placeholder={I18n.t("pre_order.search_country")}
                  value={searchGeoQuery}
                  onChange={setGeoSearchQuery}
                  clearButton
                  onClearButtonClick={() => setGeoSearchQuery("")}
                />
                <Box
                  style={{
                    maxHeight: "400px",
                    overflowY: "auto",
                    overflowX: "hidden",
                  }}
                >
                  <OptionList
                    title={I18n.t("pre_order.select_countries")}
                    onChange={(value) =>
                      handleSettingChange("preGeoCountries")(value)
                    }
                    options={filteredGeoCountries}
                    selected={parsedCountries}
                    allowMultiple
                  />
                </Box>
              </Box>
            </Popover.Pane>
          </Popover>
          <Text variant="bodyMd" tone="subdued" as="p">
            {I18n.t("pre_order.country_geo_selection_help")}
          </Text>
          <TextField
            label={I18n.t("pre_order.blacklisted_phone_numbers")}
            value={setting.preBlockPhone || ""}
            onChange={handleSettingChange("preBlockPhone")}
            multiline={5}
            maxLength={10000}
            helpText={I18n.t("pre_order.enter_blacklisted_phones")}
          />
        </FormLayout>
      </SectionCard>
    </>
  );

  const renderVerificationSettings = () => (
    <BlockStack gap="400">
      {/* Country selection: the widget cannot verify anyone until it is set. */}
      {isExtensionEnabled && setting.enablePreOrderOtp && (
        <Card padding="600">
            <BlockStack gap="400">
              <InlineStack align="space-between" blockAlign="center">
                <InlineStack gap="300" blockAlign="center">
                  <div>
                    <Text variant="headingMd" as="h3">
                      {I18n.t("pre_order.settings_required")}
                    </Text>
                    <Text variant="bodyMd" tone="subdued">
                      {selectedCountries
                        ? I18n.t("pre_order.country_selection_completed")
                        : I18n.t("pre_order.select_countries_required")}
                    </Text>
                  </div>
                </InlineStack>
                {selectedCountries ? (
                  <Badge tone="success">{I18n.t("pre_order.enabled")}</Badge>
                ) : (
                  <Badge tone="attention">{I18n.t("pre_order.inactive")}</Badge>
                )}
              </InlineStack>
              {!selectedCountries && (
                <Banner status="warning">
                  <Text variant="bodyMd">
                    {I18n.t("pre_order.must_select_country")}
                  </Text>
                </Banner>
              )}
              <BlockStack gap="300">
                {selectedCountries && (
                  <Box>
                    <Tag>{selectedCountries}</Tag>
                  </Box>
                )}
                <InlineStack gap="300" blockAlign="center">
                  <Popover
                    active={popoverActive}
                    activator={
                      <Button
                        onClick={togglePopoverActive}
                        disclosure
                        size="slim"
                      >
                        {I18n.t("pre_order.select_countries_button")}
                      </Button>
                    }
                    onClose={togglePopoverActive}
                  >
                    <Popover.Pane fixed>
                      <Box padding="200">
                        <TextField
                          placeholder={I18n.t("pre_order.search_country")}
                          value={searchQuery}
                          onChange={setSearchQuery}
                          clearButton
                          onClearButtonClick={() => setSearchQuery("")}
                        />
                        <Box 
                          style={{ 
                            maxHeight: "400px", 
                            overflowY: "auto",
                            overflowX: "hidden"
                          }}
                        >
                          <OptionList
                            title={I18n.t("pre_order.select_countries")}
                            onChange={(value) =>
                              handleSettingChange("countryCodeList")(value)
                            }
                            options={filteredCountries}
                            selected={
                              selectedCountries
                                ? selectedCountries.split(",")
                                : []
                            }
                            allowMultiple
                          />
                        </Box>
                      </Box>
                    </Popover.Pane>
                  </Popover>
                </InlineStack>
                <Text variant="bodyMd" tone="subdued" as="p">
                  {I18n.t("pre_order.select_countries_required")}
                </Text>
              </BlockStack>
              {isOnlyIndiaSelected && (
                <>
                  <Divider />
                  <FormLayout>
                <Checkbox
                  label={I18n.t("pre_order.enable_prefilled")}
                  checked={setting.isPrefilledAddressEnabled}
                  onChange={handleSettingChange("isPrefilledAddressEnabled")}
                  helpText={I18n.t("pre_order.prefilled_help")}
                  disabled={
                    !setting.enablePreOrderOtp ||
                    !isPaidPlan
                  }
                />
                {!isPaidPlan ? (
                  <Text variant="bodySm" tone="subdued" as="p">
                    {I18n.t("custom_setup.prefilled_paid_plan_notice")}{" "}
                    <Link url="/subscription" onClick={goToSubscription}>
                      {I18n.t("custom_setup.prefilled_upgrade_now")}
                    </Link>
                  </Text>
                ) : null}
                  </FormLayout>
                </>
              )}
            </BlockStack>
        </Card>
      )}

      <SectionCard
        title={I18n.t("pre_order.persistent_signin_label")}
        description={I18n.t("pre_order.persistent_signin_help")}
      >
        <BlockStack gap="300">
          <Checkbox
            label={I18n.t("pre_order.persistent_signin_enable")}
            checked={
              (setting.persistent_signin ?? setting.persistentSignin) === true ||
              (setting.persistent_signin ?? setting.persistentSignin) === "true"
            }
            onChange={handleSettingChange("persistent_signin")}
          />
        </BlockStack>
      </SectionCard>

      {renderOtpAdvancedSection()}

      {/* Test in Store - Only show when setup is complete */}
      {isExtensionEnabled && setting.enablePreOrderOtp && selectedCountries && (
        <Card>
          <Box padding="400">
            <BlockStack gap="400">
              <InlineStack gap="300" blockAlign="center">
                <Box
                  background={
                    selectedCountries
                      ? "bg-success"
                      : "bg-surface-warning-subdued"
                  }
                  padding="200"
                  borderRadius="100"
                >
                  <Text
                    variant="headingLg"
                    tone={selectedCountries ? "success" : "warning"}
                  >
                    4
                  </Text>
                </Box>
                <div>
                  <Text variant="headingMd" as="h3">
                    {I18n.t(
                      "onboarding_otp.activation.test_in_store_step4.title"
                    )}
                  </Text>
                  <Text variant="bodyMd" tone="subdued">
                    {I18n.t(
                      "onboarding_otp.activation.test_in_store_step4.subtitle"
                    )}
                  </Text>
                </div>
              </InlineStack>
              <Banner status="info">
                <Text variant="bodyMd">
                  {I18n.t(
                    "onboarding_otp.activation.test_in_store_step4.banner_message"
                  )}
                </Text>
              </Banner>
              <InlineStack gap="200" align="start">
                <Button
                  variant="primary"
                  icon={ExternalMinor}
                  onClick={() => {
                    // Try both camelCase and snake_case since axios-hooks may handle it differently
                    const productUrl = productUrlData?.productUrl || productUrlData?.product_url;
                    if (productUrl && !productUrlData?.error) {
                      window.open(productUrl, "_blank", "noopener,noreferrer");
                    } else if (shop?.shopify_domain) {
                      // Fallback to store domain if product URL is not available
                      const storeUrl = `https://${shop.shopify_domain}`;
                      window.open(storeUrl, "_blank", "noopener,noreferrer");
                    }
                  }}
                  disabled={!shop?.shopify_domain}
                >
                  {I18n.t(
                    "onboarding_otp.activation.test_in_store_step4.open_store_button"
                  )}
                </Button>
              </InlineStack>
            </BlockStack>
          </Box>
        </Card>
      )}
    </BlockStack>
  );


  return (
    <>
      {/* App Bridge v4 SaveBar */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={isSaving ? "" : undefined}
          disabled={isSaving}
        >
          {I18n.t("pre_order.save")}
        </button>
        <button onClick={handleDiscard}>
          {I18n.t("pre_order.discard")}
        </button>
      </SaveBar>
      <Layout>
        <Layout.Section>
          {/* Setup Steps */}
          <BlockStack gap="400">
            <FreeWalletBalance />
            {isOnboardingFlow && <QuickCurrentStep currentStep={2} />}
            {isOnboardingFlow && hasNoChargeId(shop) && (
              <QuickBilling navigationSource="onboarding-otp-pre" />
            )}

            {renderWidgetHubCard()}

            {!isExtensionEnabled && (
              <Card>
                <AppEmbedTutorial />
              </Card>
            )}

            {renderOtpActivationCard()}

            {isUiScreen
              ? (
                  <UiCustomizationSectionList
                    disabled={!isExtensionEnabled}
                    onOpen={(sectionId) => {
                      setUiSectionToOpen(sectionId);
                      setUiModalOpen(true);
                    }}
                  />
                )
              : renderVerificationSettings()}
          </BlockStack>
        </Layout.Section>

      </Layout>
      <UiCustomizationEditor
        open={uiModalOpen}
        onClose={() => setUiModalOpen(false)}
        isExtensionEnabled={isExtensionEnabled}
        initialSection={uiSectionToOpen}
      />
    </>
  );
};

export default PreOrderSetting;

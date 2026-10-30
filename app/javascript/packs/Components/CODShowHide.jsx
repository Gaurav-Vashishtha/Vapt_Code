import React, {
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  useRef,
} from "react";
// 1. App Bridge v4 Imports
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";

import { StoreContext } from "../Context/Store";
import useApi from "../Hooks/useApi";
import Api from "../Services/Api";

import {
  Page,
  Card,
  BlockStack,
  Text as PolarisText,
  Checkbox,
  Tooltip,
  Icon,
  TextField,
  Button,
  Banner,
  Divider,
  Layout,
  useBreakpoints,
  InlineGrid,
  Box,
  InlineStack,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import { QuestionMarkMajor } from "@shopify/polaris-icons";
import { debugLog } from "../Modal/utilities/otpUtils";
import I18n from "../i18n-lang";
// Removed navigateTo import - using handleRedirect pattern instead

// Import sub-components
import MultiSelect from "./CODShowHide/codkiMultiSelect";
import PaymentRules from "./CODShowHide/codkiPaymentRules";
import CartValueRules from "./CODShowHide/codkiCartValueRules";
import LocationRules from "./CODShowHide/codkiLocationRules";
import ProductCustomerRules from "./CODShowHide/codkiProductCustomerRules";
import DeliveryMethods from "./CODShowHide/codkiDeliveryMethods";
import { renderTooltip } from "./CODShowHide/codkiShowHideUtils";
import FeatureCallout from "./FeatureCallout";

const LIMIT_COD_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.15_PM_1.jpg?v=1791392734";
import QuickBilling from "./QuickBilling";
import { hasNoChargeId } from "../utils/shopUtils";
import QuickCurrentStep from "./QuickCurrentStep";
import {
  FreePlanFormNote,
  LimitCodPostalNotice,
} from "../Pages/CodForm/components/LimitCodNotes";

export default function CODShowHide({ isOnBoardingFlow, navigationSource }) {
  const shopify = useAppBridge(); // Initialize v4 App Bridge
  const {
    banner: [, setBanner],
    contextualBar: [contextualBar, setContextualBar],
    plan: [plan],
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [tab, setTab],
    loading: [loading, setLoading],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;
  const [isDirty, setIsDirty] = useState(false);
  const [onBoardingFlow, setOnBoardingFlow] = useState(!!isOnBoardingFlow);
  const [selectedTab, setSelectedTab] = useState(0);

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
  
  // Local UI States
  const [orderTotalChecked, setOrderTotalChecked] = useState(
    setting?.minCartTotal || setting?.maxCartTotal || false
  );
  const [provincesChecked, setProvincesChecked] = useState(
    setting.showProvinces || setting.hideProvinces || false
  );
  const [zipCodesChecked, setZipCodesChecked] = useState(
    setting.selectedZips || setting.excludedZips || false
  );
  const [productIdChecked, setProductIdChecked] = useState(
    setting.selectedProductIds || setting.showProductIds || false
  );
  const [variantChecked, setVariantChecked] = useState(
    setting.hideProductVariantIds || false
  );
  const [hideVendorsChecked, setHideVendorsChecked] = useState(
    setting.hideVendors && setting.hideVendors.length > 0
  );
  const [showVendorsChecked, setShowVendorsChecked] = useState(
    setting.showVendors && setting.showVendors.length > 0
  );
  const [resourcePickerError, setResourcePickerError] = useState();
  const [variantPickerError, setVariantPickerError] = useState();
  const [collectionsChecked, setCollectionsChecked] = useState(
    (setting.excludedCollectionIds && setting.excludedCollectionIds.length > 0) ||
    (setting.selectedCollectionIds && setting.selectedCollectionIds.length > 0)
  );

  const settingRef = useRef(setting);
  useEffect(() => { settingRef.current = setting; }, [setting]);

  // Track isDirty based on contextualBar
  useEffect(() => {
    setIsDirty(contextualBar);
  }, [contextualBar]);

  const isDisabled = () => {
    if (onBoardingFlow) return false; // Never disable during onboarding
    return plan.name === "Free" || !shop.charge_id || setting.lockPaidFeature;
  };

  const getDisabledMessage = () => {
    if (plan.name === "Free" || !shop.charge_id) {
      return {
        tone: "warning",
        title: I18n.t("cod_show_hide.test_mode_title"),
        message: "Requires Paid Plan. ",
        buttonText: I18n.t("cod_show_hide.upgrade_now"),
        buttonAction: (e) => handleRedirect(e, "/subscription"),
      };
    }
    // This feature will be disabled after 10 Orders
    if (setting.lockPaidFeature) {
      return {
        tone: "warning",
        title: I18n.t("cod_show_hide.locked_title"),
        message:
          "You need to upgrade your plan to pro or higher to enable COD Show Hide in your store. The feature is currently locked and will not work in desired way.",
        buttonText: I18n.t("cod_show_hide.upgrade_now"),
        buttonAction: () => setTab(7 + prepaidTabIncrement),
      };
    }
    return null;
  };

  /**
   * App Bridge v4 Resource Picker Logic with Duplicate Detection
   */
  const openPicker = async (resourceType, settingKey) => {
    if (isDisabled()) return;

    // Mapping for GID Capitalization
    const gidMapping = {
      'product': 'Product',
      'collection': 'Collection',
      'variant': 'ProductVariant'
    };

    const gidClassName = gidMapping[resourceType] || 'Product';
    const currentIds = setting[settingKey] ? setting[settingKey].split(",").filter(Boolean) : [];
    const selectionIds = currentIds.map(id => ({ id: `gid://shopify/${gidClassName}/${id}` }));

    try {
      const selected = await shopify.resourcePicker({
        type: resourceType, // v4 types: product, collection, variant
        multiple: true,
        selectionIds: selectionIds,
        action: 'select',
      });

      if (selected) {
        // Handle mutual exclusion for collections
        if (settingKey === "excludedCollectionIds") handleSettingChange("selectedCollectionIds")("");
        if (settingKey === "selectedCollectionIds") handleSettingChange("excludedCollectionIds")("");

        const selectedIds = selected.map(item => item.id.split("/").pop());
        const duplicateIds = [];
        const newIds = [];

        // Handle product picker - check both selectedProductIds and showProductIds
        if (resourceType === 'product') {
          const selectedProductIds = setting["selectedProductIds"]
            ? setting["selectedProductIds"].split(",").filter(Boolean)
            : [];
          const showProductIds = setting["showProductIds"]
            ? setting["showProductIds"].split(",").filter(Boolean)
            : [];

          selectedIds.forEach((id) => {
            if (selectedProductIds.includes(id) || showProductIds.includes(id)) {
              duplicateIds.push(id);
            } else {
              newIds.push(id);
            }
          });
        } else {
          // For collections and variants, check against current setting key
          selectedIds.forEach((id) => {
            if (currentIds.includes(id)) {
              duplicateIds.push(id);
            } else {
              newIds.push(id);
            }
          });
        }

        if (newIds.length > 0) {
          handleSettingChange(settingKey)([...currentIds, ...newIds].join(","));
        }

        // Show error for duplicates
        if (duplicateIds.length > 0) {
          const errorMessage = resourceType === 'variant'
            ? `The following variants already exists. ${duplicateIds.join(",")}`
            : resourceType === 'product'
            ? `The following products already exists. ${duplicateIds.join(",")}`
            : `The following collections already exist: ${duplicateIds.join(",")}`;

          if (resourceType === 'variant') {
            setVariantPickerError(errorMessage);
            setTimeout(() => {
              setVariantPickerError(null);
            }, 5000);
          } else {
            setResourcePickerError(errorMessage);
            setTimeout(() => {
              setResourcePickerError(null);
            }, 5000);
          }
        }
      }
    } catch (error) {
      console.error("Resource Picker Error:", error);
    }
  };

  const openCollectionPicker = (key) => openPicker('collection', key);
  const openResourcePicker = (key) => openPicker('product', key);
  const openVariantResourcePicker = () => openPicker('variant', 'hideProductVariantIds');

  const handleSettingChange = useCallback((key) => (value) => {
    if (!onBoardingFlow && isDisabled()) return;
    setSetting((prev) => ({ ...prev, [key]: Array.isArray(value) ? value.join(",") : value }));
    if (!contextualBar) setContextualBar(true);
  }, [onBoardingFlow, contextualBar, setSetting, setContextualBar]);

  const handleSubmit = useCallback(async () => {
    if (isDisabled()) return;
    setLoading(true);
    try {
      const response = await Api.post("/settings", settingRef.current);
      setIsDirty(false);
      setSetting(response.data);
      setOriginalSetting(response.data);
      shopify.toast.show(I18n.t("admin.settings_saved"));
      setContextualBar(false);
    } catch (error) {
      debugLog(error);
    } finally {
      setLoading(false);
    }
  }, [shopify, setSetting, setOriginalSetting, setContextualBar, setLoading, setIsDirty]);

  const resetLocalStates = useCallback((fromSetting) => {
    setSetting(fromSetting);
    setOrderTotalChecked(
      fromSetting.minCartTotal || fromSetting.maxCartTotal || false
    );
    setProvincesChecked(
      fromSetting.showProvinces || fromSetting.hideProvinces || false
    );
    setZipCodesChecked(
      fromSetting.selectedZips || fromSetting.excludedZips || false
    );
    setProductIdChecked(
      fromSetting.selectedProductIds || fromSetting.showProductIds || false
    );
    setVariantChecked(fromSetting.hideProductVariantIds || false);
    setHideVendorsChecked(fromSetting.hideVendors?.length > 0);
    setShowVendorsChecked(fromSetting.showVendors?.length > 0);
    setCollectionsChecked(
      fromSetting.excludedCollectionIds?.length > 0 ||
        fromSetting.selectedCollectionIds?.length > 0
    );
  }, [setSetting]);

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    resetLocalStates(cloned);
    setContextualBar(false);
  }, [originalSetting, resetLocalStates, setContextualBar]);

  const onItemRemoveHandler = useCallback((item, settingName) => {
    if (isDisabled()) return;
    const currentSetting = setting[settingName];
    let items = currentSetting ? currentSetting.split(",").filter(Boolean) : [];
    items = items.filter((e) => e != item);
    handleSettingChange(settingName)(items.join(","));
    setContextualBar(true);
  }, [setting, handleSettingChange, setContextualBar]);

  // Form Render Logic
  const renderMultiSelect = useCallback(
    (
      id,
      label,
      options,
      tooltip,
      showCheckbox = true,
      maxWidth = "500px",
      disabled = false
    ) => {
      const [checked, setChecked] = useState(
        setting[id] && setting[id].split(",").filter(Boolean).length > 0
      );

      // Sync checkbox when setting changes (e.g., from Discard)
      useEffect(() => {
        setChecked(setting[id] && setting[id].split(",").filter(Boolean).length > 0);
      }, [setting[id]]);

      const handleCheckedChange = (checked) => {
        if (isDisabled()) return;
        setChecked(checked);
        if (!checked) {
          handleSettingChange(id)("");
        }
        setContextualBar(true);
      };

      return (
        <Box style={{ opacity: disabled || isDisabled() ? 0.5 : 1 }}>
          <BlockStack gap="200">
            <InlineStack align="start" gap="100" blockAlign="center" wrap>
              {showCheckbox ? (
                <Checkbox
                  label={label}
                  checked={checked}
                  onChange={handleCheckedChange}
                  disabled={disabled || isDisabled()}
                />
              ) : (
                <PolarisText as="span" variant="bodyMd">
                  {label}
                </PolarisText>
              )}
              {tooltip && (
                <Tooltip content={tooltip}>
                  <Icon source={QuestionMarkMajor} tone="subdued" />
                </Tooltip>
              )}
            </InlineStack>
            {(checked || !showCheckbox) && (
              <MultiSelect
                label={label}
                options={options}
                selected={
                  setting[id] && setting[id].trim() !== ""
                    ? setting[id]
                        .split(",")
                        .map((s) => s.trim())
                        .filter(Boolean)
                    : []
                }
                onChange={handleSettingChange(id)}
                disabled={disabled || isDisabled()}
              />
            )}
          </BlockStack>
        </Box>
      );
    },
    [setting, handleSettingChange, setContextualBar]
  );

  const renderTextField = useCallback(
    (
      label,
      value,
      onChange,
      helpText,
      tooltip,
      placeholder = "",
      multiline = 3,
      showCheckbox = true,
      maxWidth = "400px",
      disabled = false,
      action
    ) => {
      const [checked, setChecked] = useState(
        value && value.split(",").filter(Boolean).length > 0
      );

      // Sync checkbox when prop value changes (e.g., from Discard)
      useEffect(() => {
        setChecked(value && value.split(",").filter(Boolean).length > 0);
      }, [value]);

      const handleCheckedChange = (checked) => {
        if (isDisabled()) return;
        setChecked(checked);
        if (!checked) {
          onChange("");
        }
        setContextualBar(true);
      };

      return (
        <Box style={{ opacity: disabled || isDisabled() ? 0.5 : 1 }}>
          <BlockStack gap="200">
            <InlineStack align="start" gap="100" blockAlign="center" wrap>
              {showCheckbox ? (
                <Checkbox
                  label={label}
                  checked={checked}
                  onChange={handleCheckedChange}
                  disabled={disabled || isDisabled()}
                />
              ) : (
                <PolarisText variant="bodyMd" as="span">
                  {label}
                </PolarisText>
              )}
            </InlineStack>
            {(checked || !showCheckbox) && (
              <BlockStack gap="100">
                {action && action()}
                <TextField
                  label=""
                  value={value || ""}
                  onChange={disabled || isDisabled() ? () => {} : (v) => { onChange(v); if(!contextualBar) setContextualBar(true); }}
                  helpText={helpText}
                  placeholder={placeholder}
                  multiline={multiline}
                  disabled={disabled || isDisabled()}
                  autoComplete="off"
                />
              </BlockStack>
            )}
          </BlockStack>
        </Box>
      );
    },
    [isDisabled, contextualBar, setContextualBar]
  );

  // Restored Hide/Show Mutual Exclusion Logic
  const checkedChangeHandler = useCallback((value, callback, checkbox) => {
    if (!onBoardingFlow && isDisabled()) return;
    callback(() => {
      if (value == false) {
        if (checkbox == "orderTotalChecked") {
          handleSettingChange("minCartTotal")("");
          handleSettingChange("maxCartTotal")("");
        }
        if (checkbox == "provincesChecked") {
          handleSettingChange("showProvinces")("");
          handleSettingChange("hideProvinces")("");
        }
        if (checkbox == "zipCodesChecked") {
          handleSettingChange("selectedZips")("");
          handleSettingChange("excludedZips")("");
        }
        if (checkbox == "productIdChecked") {
          handleSettingChange("selectedProductIds")("");
          handleSettingChange("showProductIds")("");
        }
        if (checkbox == "variantChecked") {
          handleSettingChange("hideProductVariantIds")("");
        }
      }
      return value;
    });
    setContextualBar(true);
  }, [onBoardingFlow, handleSettingChange, setContextualBar]);

  const toggleChangeHandler = useCallback((value, checkbox) => {
    if (!value || (!onBoardingFlow && isDisabled())) return;
    const conflictMap = {
      hideVendorsChecked: {
        clear: "showVendors",
        disable: setShowVendorsChecked,
      },
      showVendorsChecked: {
        clear: "hideVendors",
        disable: setHideVendorsChecked,
      },
    };
    const conflict = conflictMap[checkbox];
    if (conflict) {
      setSetting((prev) => ({ ...prev, [conflict.clear]: "" }));
      conflict.disable(false);
    }
  }, [onBoardingFlow, setSetting]);

  const [{ data: provinceData }, getProvinces] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/provinces`,
      method: "GET",
    },
    { manual: true }
  );
  const [{ data: paymentMethods }, getPaymentMethods] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/payment_methods`,
      method: "GET",
    },
    { manual: true }
  );

  useEffect(() => {
    if (paymentMethods === undefined) {
      getPaymentMethods();
    }
    if (provinceData === undefined) {
      getProvinces();
    }
  }, [paymentMethods, provinceData, getPaymentMethods, getProvinces]);

  // Sync local states with originalSetting on mount and when originalSetting changes
  useEffect(() => {
    setOrderTotalChecked(
      originalSetting?.minCartTotal || originalSetting?.maxCartTotal || false
    );
    setProvincesChecked(
      originalSetting.showProvinces || originalSetting.hideProvinces || false
    );
    setZipCodesChecked(
      originalSetting.selectedZips || originalSetting.excludedZips || false
    );
    setProductIdChecked(
      originalSetting.selectedProductIds ||
        originalSetting.showProductIds ||
        false
    );
    setVariantChecked(originalSetting.hideProductVariantIds || false);
    setHideVendorsChecked(originalSetting.hideVendors?.length > 0);
    setShowVendorsChecked(originalSetting.showVendors?.length > 0);
    setCollectionsChecked(
      (originalSetting.excludedCollectionIds &&
        originalSetting.excludedCollectionIds.length > 0) ||
        (originalSetting.selectedCollectionIds &&
          originalSetting.selectedCollectionIds.length > 0)
    );
  }, [originalSetting]);

  const renderBanner = useCallback(() => {
    const disabledMessage = getDisabledMessage();
    if (!disabledMessage) return null;
    return (
      <Banner
        tone={disabledMessage.tone}
        title={disabledMessage.title}
        action={{
          content: disabledMessage.buttonText,
          onAction: disabledMessage.buttonAction,
        }}
      >
        <p>{disabledMessage.message}</p>
      </Banner>
    );
  }, [
    plan.name,
    shop.charge_id,
    setting.lockPaidFeature,
    setTab,
    prepaidTabIncrement,
  ]);

  function CodKingFooter() {
    return (
      <Box paddingBlock="400" paddingInline="300">
        <BlockStack align="center" gap="200">
          <InlineStack align="center" gap="100">
            <PolarisText as="p" variant="bodySm" tone="subdued">
              {I18n.t("cod_show_hide.cod_king_2025")}
            </PolarisText>
          </InlineStack>
        </BlockStack>
      </Box>
    );
  }

  const { smUp } = useBreakpoints();

  // Loading skeleton – matches COD Show/Hide: repeated 2fr 5fr sections (heading left, form card right)
  if (!setting || !plan?.name) {
    return (
      <SkeletonPage primaryAction>
        <Layout>
          <Layout.Section>
            <BlockStack gap={{ xs: "800", sm: "400" }}>
              {[1, 2, 3].map((i) => (
                <React.Fragment key={i}>
                  <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                    <Box as="section" paddingInlineStart={{ xs: 400, sm: 0 }} paddingInlineEnd={{ xs: 400, sm: 0 }}>
                      <BlockStack gap="200">
                        <SkeletonDisplayText size="small" />
                        <SkeletonBodyText lines={2} />
                      </BlockStack>
                    </Box>
                    <Card>
                      <Box padding="400">
                        <BlockStack gap="200">
                          <SkeletonBodyText lines={1} />
                          <SkeletonBodyText lines={1} />
                          <SkeletonBodyText lines={1} />
                        </BlockStack>
                      </Box>
                    </Card>
                  </InlineGrid>
                  {i < 3 && <Divider />}
                </React.Fragment>
              ))}
            </BlockStack>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  const disabled = onBoardingFlow ? false : isDisabled();

  return (
    <>
      <Page
        divider
        title={I18n.t("cod_show_hide.page_title")}
        subtitle={I18n.t("cod_show_hide.page_subtitle")}
        backAction={
          onBoardingFlow
            ? {
                content: I18n.t("cod_show_hide.back_to_features"),
                onAction: (e) => {
                  if (isDirty || contextualBar) return;
                  handleRedirect(e, "/quick-onboarding");
                },
              }
            : undefined
        }
        fullWidth={true}
      >
        {/* Declarative Save Bar */}
        <SaveBar data-save-bar open={isDirty}>
          <button
            variant="primary"
            onClick={handleSubmit}
            loading={loading ? "" : undefined}
            disabled={loading}
          >
            {I18n.t("cod_show_hide.save_button")}
          </button>
          <button onClick={handleDiscard}>{I18n.t("cod_show_hide.discard_button")}</button>
        </SaveBar>

        {!onBoardingFlow && renderBanner()}
        {!onBoardingFlow && (
          <FreePlanFormNote
            feature="limit_cod"
            isFreePlan={plan.name == "Free" || !shop.charge_id}
          />
        )}
        <br />
        <Layout>
          <Layout.Section>
            <FeatureCallout
              illustration="docs"
              image={LIMIT_COD_CALLOUT_IMAGE}
              title={I18n.t("cod_show_hide.help_title")}
              description={I18n.t("cod_show_hide.help_description")}
              docsUrl="https://codking.notion.site/0feef35c0ec64875a1ecb9ec24de92e3?v=9ecb40d565f84b1a9e7e8c2d1656fc6f&p=10b8cb93518c423b83fe36352c35cb22&pm=s"
              videoUrl="https://youtu.be/m9-7seS1Yg8?si=kDFDirMRb4GFYBYQ"
              showChat
            />
            <br />
            {onBoardingFlow && <QuickCurrentStep currentStep={2} />}
            <br />
            {onBoardingFlow && hasNoChargeId(shop) && plan?.name !== "Free" && (
              <QuickBilling navigationSource={navigationSource} />
            )}
            <br />
            <BlockStack gap={{ xs: "800", sm: "400" }}>
              {/* Payment Rules Section */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box
                  as="section"
                  paddingInlineStart={{ xs: 400, sm: 0 }}
                  paddingInlineEnd={{ xs: 400, sm: 0 }}
                >
                  <BlockStack gap="400">
                    <PolarisText as="h3" variant="headingMd">
                      {I18n.t("cod_show_hide.payment_rules_heading")}
                    </PolarisText>
                    <PolarisText as="ul" variant="bodyMd">
                      <li>{I18n.t("cod_show_hide.payment_rules_desc_1")}</li>
                      <li>{I18n.t("cod_show_hide.payment_rules_desc_2")}</li>
                    </PolarisText>
                  </BlockStack>
                </Box>
                <PaymentRules
                  setting={setting}
                  handleSettingChange={handleSettingChange}
                  renderTextField={renderTextField}
                  renderTooltip={renderTooltip}
                  renderMultiSelect={renderMultiSelect}
                  disabled={disabled}
                  paymentMethods={paymentMethods}
                />
              </InlineGrid>

              {smUp ? <Divider /> : null}

              {/* Cart Value Rules Section */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box as="section">
                  <BlockStack gap="400">
                    <PolarisText as="h3" variant="headingMd">
                      {I18n.t("cod_show_hide.cart_value_rules_heading")}
                    </PolarisText>
                    <PolarisText as="ul" variant="bodyMd">
                      <li>{I18n.t("cod_show_hide.cart_value_rules_desc_1")}</li>
                      <li>{I18n.t("cod_show_hide.cart_value_rules_desc_2")}</li>
                      <li>{I18n.t("cod_show_hide.cart_value_rules_desc_3")}</li>
                    </PolarisText>
                  </BlockStack>
                </Box>
                <CartValueRules
                  setting={setting}
                  handleSettingChange={handleSettingChange}
                  renderTextField={renderTextField}
                  orderTotalChecked={orderTotalChecked}
                  setOrderTotalChecked={setOrderTotalChecked}
                  hideVendorsChecked={hideVendorsChecked}
                  showVendorsChecked={showVendorsChecked}
                  setHideVendorsChecked={setHideVendorsChecked}
                  setShowVendorsChecked={setShowVendorsChecked}
                  toggleChangeHandler={toggleChangeHandler}
                  checkedChangeHandler={checkedChangeHandler}
                  disabled={disabled}
                  shop={shop}
                />
              </InlineGrid>

              {smUp ? <Divider /> : null}

              {/* Location Rules Section */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box as="section">
                  <BlockStack gap="400">
                    <PolarisText as="h3" variant="headingMd">
                      {I18n.t("cod_show_hide.location_rules_heading")}
                    </PolarisText>
                    <PolarisText as="ul" variant="bodyMd">
                      <li>{I18n.t("cod_show_hide.location_rules_desc_1")}</li>
                      <li>{I18n.t("cod_show_hide.location_rules_desc_2")}</li>
                      <li>{I18n.t("cod_show_hide.location_rules_desc_3")}</li>
                    </PolarisText>
                  </BlockStack>
                </Box>
                <LocationRules
                  setting={setting}
                  handleSettingChange={handleSettingChange}
                  renderTextField={renderTextField}
                  renderMultiSelect={renderMultiSelect}
                  provincesChecked={provincesChecked}
                  zipCodesChecked={zipCodesChecked}
                  checkedChangeHandler={checkedChangeHandler}
                  setProvincesChecked={setProvincesChecked}
                  setZipCodesChecked={setZipCodesChecked}
                  disabled={disabled}
                  provinceData={provinceData}
                />
              </InlineGrid>
              {/* COD Form: postal prefix / range help and allow-list warnings (never blocks saving) */}
              <LimitCodPostalNotice
                visible={!!zipCodesChecked}
                selectedZips={setting.selectedZips}
                excludedZips={setting.excludedZips}
              />

              {smUp ? <Divider /> : null}

              {/* Product Customer Rules Section */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box as="section">
                  <BlockStack gap="400">
                    <PolarisText as="h3" variant="headingMd">
                      {I18n.t("cod_show_hide.product_customer_rules_heading")}
                    </PolarisText>
                    <PolarisText as="ul" variant="bodyMd">
                      <li>
                        {I18n.t("cod_show_hide.product_customer_rules_desc_1")}
                      </li>
                      <li>
                        {I18n.t("cod_show_hide.product_customer_rules_desc_2")}
                      </li>
                      <li>
                        {I18n.t("cod_show_hide.product_customer_rules_desc_3")}
                      </li>
                    </PolarisText>
                  </BlockStack>
                </Box>
                <ProductCustomerRules
                  setting={setting}
                  handleSettingChange={handleSettingChange}
                  renderTextField={renderTextField}
                  renderTooltip={renderTooltip}
                  collectionsChecked={collectionsChecked}
                  setCollectionsChecked={setCollectionsChecked}
                  productIdChecked={productIdChecked}
                  variantChecked={variantChecked}
                  checkedChangeHandler={checkedChangeHandler}
                  setProductIdChecked={setProductIdChecked}
                  setVariantChecked={setVariantChecked}
                  openCollectionPicker={openCollectionPicker}
                  openResourcePicker={openResourcePicker}
                  openVariantResourcePicker={openVariantResourcePicker}
                  onItemRemoveHandler={onItemRemoveHandler}
                  resourcePickerError={resourcePickerError}
                  variantPickerError={variantPickerError}
                  setResourcePickerError={setResourcePickerError}
                  setVariantPickerError={setVariantPickerError}
                  setContextualBar={setContextualBar}
                  disabled={disabled}
                />
              </InlineGrid>

              {smUp ? <Divider /> : null}

              {/* Delivery Methods Section */}
              <InlineGrid columns={{ xs: "1fr", md: "2fr 5fr" }} gap="400">
                <Box as="section">
                  <BlockStack gap="400">
                    <PolarisText as="h3" variant="headingMd">
                      {I18n.t("cod_show_hide.delivery_methods_heading")}
                    </PolarisText>
                    <PolarisText as="ul" variant="bodyMd">
                      <li>{I18n.t("cod_show_hide.delivery_methods_desc_1")}</li>
                      <li>{I18n.t("cod_show_hide.delivery_methods_desc_2")}</li>
                      <li>{I18n.t("cod_show_hide.delivery_methods_desc_3")}</li>
                    </PolarisText>
                  </BlockStack>
                </Box>
                <DeliveryMethods
                  renderMultiSelect={renderMultiSelect}
                  disabled={disabled}
                />
              </InlineGrid>
            </BlockStack>
          </Layout.Section>
        </Layout>
      </Page>
      {/* {CodKingFooter()} */}
    </>
  );
}
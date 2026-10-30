import React, {
  useState,
  useEffect,
  useCallback,
  useContext,
  useRef,
} from "react";
// 1. Remove legacy import: import { ContextualSaveBar as AppBridgeSaveBar } from "@shopify/app-bridge/actions";
// 2. Add v4 SaveBar and useAppBridge hook
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  Page,
  Layout,
  Card,
  Button,
  TextField,
  Checkbox,
  Tabs,
  DataTable,
  Icon,
  InlineStack,
  Text,
  Box,
  Badge,
  EmptyState,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
  Spinner,
  BlockStack,
  ChoiceList,
  InlineGrid,
  Divider,
  FormLayout,
  Link,
} from "@shopify/polaris";
import {
  EditMinor,
  DeleteMinor,
  SearchMinor,
  PlusMinor,
  AlertMinor,
  ExternalMinor,
  RefreshMinor,
  ChevronUpMinor,
  ChevronDownMinor,
} from "@shopify/polaris-icons";
import Api from "../../Services/Api";
import useApi from "../../Hooks/useApi";
import { StoreContext } from "../../Context/Store";
import I18n from "../../i18n-lang";
import AddPaymentOptions from "./addPartialPaymentOptions";
// 3. Updated navigate utility if necessary, though App Bridge intercepts history.pushState
import { navigateTo } from "../../../utils/navigate";
import FreeWalletBalance from "../FreeWalletBalance";
import FeatureCallout from "../FeatureCallout";
import AppEmbedTutorial from "../AppEmbedTutorial";
import { SectionCard, SettingRow } from "../SettingsPrimitives";
import UiCustomizationEditor from "../CheckoutPreview/UiCustomizationEditor";
import QuickBilling from "../QuickBilling";
import QuickCurrentStep from "../QuickCurrentStep";
import { hasNoChargeId } from "../../utils/shopUtils";
import { useUserJourneyTracker } from "../../utils/userJourneyTracker";
import HexColorPicker from "../HexColorPicker";
import { currentAppPath } from "../../Pages/SettingsHub/hubUrl";
import {
  PARTIAL_RULE_EDIT_PAYLOAD_KEY,
  consumePartialPaymentReturnPath,
} from "../../utils/partialRuleEditPayload";

// Shown in the callout panel at 290x210.
const PARTIAL_PAYMENT_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-10_at_1.30.54_PM.jpg?v=1789127006";

function readPartialRuleEditPayloadFromStorage() {
  if (typeof window === "undefined") return null;
  try {
    const path = currentAppPath() || "";
    if (path !== "/features/partial-payment/edit") return null;
    const raw = sessionStorage.getItem(PARTIAL_RULE_EDIT_PAYLOAD_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    sessionStorage.removeItem(PARTIAL_RULE_EDIT_PAYLOAD_KEY);
    return parsed && parsed.id != null ? parsed : null;
  } catch (_) {
    return null;
  }
}

function PartialPayments({ isOnboardingFlow = false }) {
  const shopify = useAppBridge(); // Initialize App Bridge v4
  const {
    banner: [, setBanner],
    contextualBar: [contextualBar, setContextualBar],
    shop: [shop],
    plan: [plan],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
  } = useContext(StoreContext);

  const isPaidPlan =
    plan?.name?.toLowerCase() !== "free" && !hasNoChargeId(shop);

  const [location, setLocation] = useState(currentAppPath);
  useEffect(() => {
    const sync = () => setLocation(currentAppPath());
    window.addEventListener("popstate", sync);
    window.addEventListener("locationchange", sync);
    return () => {
      window.removeEventListener("popstate", sync);
      window.removeEventListener("locationchange", sync);
    };
  }, []);

  const normalizedPath = location.replace(/\/+$/, "");
  const showAddForm =
    normalizedPath === "/features/partial-payment/add" ||
    normalizedPath === "/features/partial-payment/edit";

  // State management
  const [rules, setRules] = useState([]);
  const [searchValue, setSearchValue] = useState("");
  const [uiModalOpen, setUiModalOpen] = useState(false);
  const [editingData, setEditingData] = useState(
    readPartialRuleEditPayloadFromStorage,
  );
  const [isExtensionEnabled, setIsExtensionEnabled] = useState(false);
  const [selectedTab, setSelectedTab] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [isCheckingTheme, setIsCheckingTheme] = useState(false);
  const [themeCheckInterval, setThemeCheckInterval] = useState(null);
  const [isRefreshingTheme, setIsRefreshingTheme] = useState(false);

  const [{ loading: saveLoading }] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings`,
      method: "POST",
    },
    { manual: true },
  );

  const checkCountRef = useRef(0);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  // 4. Removed legacy SaveBar useEffect and Refs.
  // Callbacks are now passed directly to the <SaveBar> component.

  // Function to check theme integration status
  const checkThemeIntegration = useCallback(async () => {
    try {
      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shop.shopify_domain}`,
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

  const handleRefreshThemeStatus = useCallback(async () => {
    setIsRefreshingTheme(true);
    try {
      const isEnabled = await checkThemeIntegration();
      if (isEnabled) {
        setBanner({
          active: true,
          status: "success",
          text: I18n.t("partial.theme_integration_active"),
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
  }, [checkThemeIntegration, setBanner]);

  const startThemeMonitoring = useCallback(() => {
    setIsCheckingTheme(true);
    checkCountRef.current = 0;
    const interval = setInterval(async () => {
      checkCountRef.current += 1;
      const isEnabled = await checkThemeIntegration();
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
    }, 5000);
    setThemeCheckInterval(interval);
  }, [checkThemeIntegration, setBanner]);

  const handleSettingChange = useCallback(
    (key) => (value) => {
      setSetting((prev) => ({ ...prev, [key]: value }));
      !contextualBar && setContextualBar(true);
    },
    [contextualBar, setSetting, setContextualBar],
  );

  // 5. Submit handler - optimized for v4 (backend expects params.require(:setting))
  const handleSubmit = useCallback(async () => {
    try {
      const response = await Api.post("/settings", { setting });
      setSetting(response.data);
      setOriginalSetting(response.data);
      setContextualBar(false);

      // Using v4 Toast via shopify object
      shopify.toast.show(I18n.t("admin.settings_saved"));
    } catch (error) {
      console.error("Settings save failed:", error);
      shopify.toast.show(I18n.t("admin.settings_error"), { isError: true });
    }
  }, [setting, setSetting, setOriginalSetting, setContextualBar, shopify]);

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  // API hooks for rules
  const [{}, getPartialRuleSets] = useApi(
    { url: `https://${process.env.APP_HOST}/partial_rule_sets`, method: "GET" },
    { manual: true },
  );
  const [{}, createRuleSet] = useApi(
    {
      url: `https://${process.env.APP_HOST}/partial_rule_sets`,
      method: "POST",
    },
    { manual: true },
  );
  const [{}, updateRuleSet] = useApi({}, { manual: true });
  const [{}, deleteRuleSet] = useApi({}, { manual: true });
  const [{ loading: reorderLoading }, reorderRuleSets] = useApi(
    {
      url: `https://${process.env.APP_HOST}/partial_rule_sets/reorder`,
      method: "POST",
    },
    { manual: true },
  );

  const handleMoveUp = useCallback(
    (rule) => {
      const idx = rules.findIndex((r) => r.id === rule.id);
      if (idx <= 0) return;
      const newOrder = [...rules];
      [newOrder[idx - 1], newOrder[idx]] = [newOrder[idx], newOrder[idx - 1]];
      reorderRuleSets({ data: { rule_ids: newOrder.map((r) => r.id) } })
        .then((resp) => {
          setRules(resp?.data || []);
          shopify.toast.show(I18n.t("partial.reorder_success"));
        })
        .catch((err) => {
          console.error("Error reordering:", err);
          shopify.toast.show(I18n.t("partial.reorder_error"), {
            isError: true,
          });
        });
    },
    [rules, reorderRuleSets, shopify],
  );

  const handleMoveDown = useCallback(
    (rule) => {
      const idx = rules.findIndex((r) => r.id === rule.id);
      if (idx < 0 || idx >= rules.length - 1) return;
      const newOrder = [...rules];
      [newOrder[idx], newOrder[idx + 1]] = [newOrder[idx + 1], newOrder[idx]];
      reorderRuleSets({ data: { rule_ids: newOrder.map((r) => r.id) } })
        .then((resp) => {
          setRules(resp?.data || []);
          shopify.toast.show(I18n.t("partial.reorder_success"));
        })
        .catch((err) => {
          console.error("Error reordering:", err);
          shopify.toast.show(I18n.t("partial.reorder_error"), {
            isError: true,
          });
        });
    },
    [rules, reorderRuleSets, shopify],
  );

  const fetchRuleSets = useCallback(() => {
    getPartialRuleSets()
      .then((resp) => {
        setRules(resp?.data || []);
        setIsLoading(false);
      })
      .catch((err) => {
        console.error("Error fetching rule sets:", err);
        setIsLoading(false);
      });
  }, [getPartialRuleSets]);

  const handleCreate = useCallback(
    (newRuleData) => {
      return createRuleSet({ data: newRuleData })
        .then(() => {
          fetchRuleSets();
          navigateTo(
            consumePartialPaymentReturnPath() || "/features/partial-payment",
          );
          return true;
        })
        .catch((err) => {
          console.error("Error creating rule set:", err);
          return false;
        });
    },
    [createRuleSet, fetchRuleSets],
  );

  const handleUpdate = useCallback(
    (id, updatedRuleData) => {
      return updateRuleSet({
        url: `https://${process.env.APP_HOST}/partial_rule_sets/${id}`,
        method: "PUT",
        data: updatedRuleData,
      })
        .then(() => {
          fetchRuleSets();
          navigateTo(
            consumePartialPaymentReturnPath() || "/features/partial-payment",
          );
          // Return true so the form clears its dirty/SaveBar state on edit
          // (matching handleCreate); otherwise App Bridge's unsaved-changes
          // discard fires and reverts the form to its initial values.
          return true;
        })
        .catch((err) => {
          console.error("Error updating rule set:", err);
          return false;
        });
    },
    [updateRuleSet, fetchRuleSets],
  );

  const handleDelete = useCallback(
    (id) => {
      deleteRuleSet({
        url: `https://${process.env.APP_HOST}/partial_rule_sets/${id}`,
        method: "DELETE",
      })
        .then(() => fetchRuleSets())
        .catch((err) => console.error("Error deleting rule set:", err));
    },
    [deleteRuleSet, fetchRuleSets],
  );

  useEffect(() => {
    checkThemeIntegration().then(() => {
      if (isExtensionEnabled || setting.partialPaymentEnabled) {
        fetchRuleSets();
      } else {
        setIsLoading(false);
      }
      if (isOnboardingFlow) {
        journeyTracker.trackPageLoad({
          step: 2,
          feature: "partial-payment",
          isOnboardingFlow: true,
        });
      }
    });
  }, [
    shop.shopify_domain,
    checkThemeIntegration,
    isExtensionEnabled,
    setting.partialPaymentEnabled,
    fetchRuleSets,
  ]);

  useEffect(() => {
    return () => {
      if (themeCheckInterval) clearInterval(themeCheckInterval);
    };
  }, [themeCheckInterval]);

  const filteredRules = rules.filter((rule) =>
    rule.ruleName.toLowerCase().includes(searchValue.toLowerCase()),
  );

  const rows = filteredRules.map((rule) => {
    const amount =
      rule.amount === null || rule.amount === undefined ? 0 : rule.amount;
    const isNullAmount = rule.amount === null || rule.amount === undefined;

    let amountTypeDisplay;
    if (isNullAmount) {
      amountTypeDisplay = "";
    } else if (rule.amountType === "cod" || rule.amountType === "fixed") {
      amountTypeDisplay = I18n.t("partial.amount_type_fixed");
    } else {
      amountTypeDisplay = I18n.t("partial.amount_type_percentage");
    }

    const money = (value) => {
      const num = Number(value);
      if (!Number.isFinite(num)) return String(value);
      return num % 1 === 0 ? String(num) : String(Number(num.toFixed(2)));
    };
    const isPercentage = !isNullAmount && rule.amountType === "percentage";
    const isCodFeeRule = rule.amountType === "cod";
    const paymentText = isPercentage
      ? `${money(amount)}%`
      : money(amount);
    const codFeeAmount =
      rule.includeCodFee && Number(rule.codFeeAmount) > 0
        ? Number(rule.codFeeAmount)
        : 0;
    const discountValue = Number(rule.discountValue) || 0;
    const discountLabel =
      discountValue > 0
        ? rule.discountType === "percentage"
          ? `${money(discountValue)}% off`
          : `${money(discountValue)} off`
        : "";
    const ruleIndex = rules.findIndex((r) => r.id === rule.id);
    const canMoveUp = ruleIndex > 0;
    const canMoveDown = ruleIndex >= 0 && ruleIndex < rules.length - 1;

    return [
      <InlineStack key={`order-${rule.id}`} gap="100" blockAlign="center">
        <Button
          size="micro"
          icon={ChevronUpMinor}
          onClick={() => handleMoveUp(rule)}
          disabled={!canMoveUp || reorderLoading}
          accessibilityLabel={I18n.t("partial.move_up")}
        />
        <Button
          size="micro"
          icon={ChevronDownMinor}
          onClick={() => handleMoveDown(rule)}
          disabled={!canMoveDown || reorderLoading}
          accessibilityLabel={I18n.t("partial.move_down")}
        />
      </InlineStack>,
      <Button
        key={`name-${rule.id}`}
        variant="plain"
        onClick={() => {
          setEditingData(rule);
          navigateTo("/features/partial-payment/edit");
        }}
      >
        {rule.ruleName}
      </Button>,
      <BlockStack key={`amount-${rule.id}`} gap="050">
        <InlineStack gap="150" blockAlign="center">
          {isCodFeeRule ? (
            <Badge tone="warning">{`COD fee · ${paymentText}`}</Badge>
          ) : (
            <>
              <Text variant="bodyMd" fontWeight="medium" as="span">
                {paymentText}
              </Text>
              {!isNullAmount && (
                <Text variant="bodySm" tone="subdued" as="span">
                  {amountTypeDisplay}
                </Text>
              )}
            </>
          )}
        </InlineStack>
        {(codFeeAmount > 0 || discountLabel) && (
          <InlineStack gap="150" blockAlign="center">
            {codFeeAmount > 0 && (
              <Badge tone="attention">{`+ ${money(codFeeAmount)} COD fee`}</Badge>
            )}
            {discountLabel && (
              <Badge tone="success">
                {rule.discountCode
                  ? `${discountLabel} · ${rule.discountCode}`
                  : discountLabel}
              </Badge>
            )}
          </InlineStack>
        )}
      </BlockStack>,
      <InlineStack key={`actions-${rule.id}`} gap="200">
        <Button
          size="micro"
          icon={EditMinor}
          onClick={() => {
            setEditingData(rule);
            navigateTo("/features/partial-payment/edit");
          }}
        />
        <Button
          size="micro"
          icon={DeleteMinor}
          onClick={() => handleDelete(rule.id)}
          tone="critical"
        />
      </InlineStack>,
    ];
  });

  const tabs = [
    { id: "rules", content: I18n.t("partial.payment_rules") },
    { id: "settings", content: I18n.t("partial.advanced_settings") },
  ];

  const handleThemeIntegrationClick = () => {
    startThemeMonitoring();
    window.open(
      `https://${shop.shopify_domain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`,
      "_blank",
    );
  };

  // Loading skeleton – matches Partial Payment: step card (badge + heading + actions) + list/table card
  if (isLoading) {
    return (
      <SkeletonPage primaryAction>
        <Layout>
          <Layout.Section variant="twoThirds">
            <BlockStack gap="400">
              <Card>
                <Box padding="400">
                  <BlockStack gap="300">
                    <InlineStack gap="300" blockAlign="center">
                      <Box
                        padding="200"
                        background="bg-surface-secondary"
                        borderRadius="100"
                      >
                        <SkeletonDisplayText size="small" />
                      </Box>
                      <BlockStack gap="100">
                        <SkeletonDisplayText size="small" />
                        <SkeletonBodyText lines={1} />
                      </BlockStack>
                    </InlineStack>
                    <InlineStack gap="200">
                      <SkeletonBodyText lines={1} />
                      <SkeletonBodyText lines={1} />
                    </InlineStack>
                  </BlockStack>
                </Box>
              </Card>
              <Card>
                <Box padding="400">
                  <BlockStack gap="200">
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                  </BlockStack>
                </Box>
              </Card>
            </BlockStack>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  if (showAddForm) {
    return (
      <AddPaymentOptions
        handleCreate={handleCreate}
        handleUpdate={handleUpdate}
        onBack={() => {
          setEditingData(null);
          navigateTo(
            consumePartialPaymentReturnPath() || "/features/partial-payment",
          );
        }}
        initialData={editingData}
      />
    );
  }

  return (
    <Page
      title={!isOnboardingFlow ? I18n.t("partial.page_title") : undefined}
      subtitle={!isOnboardingFlow ? I18n.t("partial.page_subtitle") : undefined}
      fullWidth={true}
    >
      {/* 6. Declarative SaveBar for App Bridge v4 */}
      <SaveBar
        id="partial-payments-save-bar"
        data-save-bar
        open={contextualBar}
      >
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={saveLoading ? "" : undefined}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>{I18n.t("admin.discard")}</button>
      </SaveBar>

      <Layout>
        <Layout.Section>
          <BlockStack gap="400">
            <FeatureCallout
              illustration="payments"
              image={PARTIAL_PAYMENT_CALLOUT_IMAGE}
              title={I18n.t("partial.activate_partial_payments")}
              description={I18n.t(
                "documentation.partial_payment_help_description",
              )}
              docsUrl="https://codking.notion.site/Step-By-Step-Guide-for-Setting-Up-Upfront-Partial-Payment-Token-Amount-1c96e71a63f98005aaddd04f5ea6000a#1c96e71a63f98005aaddd04f5ea6000a"
              videos={[
                {
                  url: "https://youtu.be/gq2C3A0pbXY?si=sJ5ZfDo4Am_jCX5y",
                  label: I18n.t("documentation_buttons.watch_setup_video"),
                },
                {
                  url: "https://youtu.be/BtB4CVRqwZM?si=X7wiKrfM3vbiiOgR",
                  label: I18n.t("documentation_buttons.partial_payment_demo"),
                },
              ]}
              showChat
              badge={
                !isExtensionEnabled ? (
                  <Badge tone="disabled">{I18n.t("partial.waiting")}</Badge>
                ) : setting.partialPaymentEnabled ? (
                  <Badge tone="success" progress="complete">
                    {I18n.t("partial.active")}
                  </Badge>
                ) : (
                  <Badge tone="attention" progress="incomplete">
                    {I18n.t("partial.inactive")}
                  </Badge>
                )
              }
              actions={
                isExtensionEnabled ? (
                  <Button
                    variant="primary"
                    onClick={() => setUiModalOpen(true)}
                  >
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
                      onClick={handleRefreshThemeStatus}
                      loading={isRefreshingTheme}
                    >
                      {isRefreshingTheme
                        ? I18n.t("partial.checking")
                        : I18n.t("partial.refresh")}
                    </Button>
                  </>
                )
              }
            />

            {!isExtensionEnabled && (
              <Card>
                <AppEmbedTutorial />
              </Card>
            )}

            <SectionCard>
              <SettingRow
                title={I18n.t("partial.activate_partial_payments")}
                description={I18n.t("partial.activate_partial_help")}
                control={
                  <InlineStack gap="200" blockAlign="center">
                    {(isCheckingTheme || isRefreshingTheme) && (
                      <Spinner size="small" />
                    )}
                    <Checkbox
                      label={I18n.t("partial.activate_partial_payments")}
                      labelHidden
                      checked={setting.partialPaymentEnabled}
                      onChange={handleSettingChange("partialPaymentEnabled")}
                      disabled={!isExtensionEnabled}
                    />
                  </InlineStack>
                }
              />
            </SectionCard>

            <FreeWalletBalance />
            {isOnboardingFlow && <QuickCurrentStep currentStep={2} />}
            {isOnboardingFlow && hasNoChargeId(shop) && (
              <QuickBilling navigationSource="onboarding-partial-payment" />
            )}

            {isExtensionEnabled && setting.partialPaymentEnabled && (
              <Card>
                <Box padding="200" paddingBlockEnd="0">
                  <InlineStack align="space-between" blockAlign="center">
                    <Text variant="headingMd" as="h3">
                      {I18n.t("partial.payment_rules_settings")}
                    </Text>
                    <Button
                      variant="primary"
                      icon={PlusMinor}
                      onClick={() =>
                        navigateTo("/features/partial-payment/add")
                      }
                    >
                      {I18n.t("partial.add_payment_rule")}
                    </Button>
                  </InlineStack>
                </Box>
                <Tabs
                  tabs={tabs}
                  selected={selectedTab}
                  onSelect={setSelectedTab}
                >
                  <Box padding="400">
                    {selectedTab === 0 && (
                      <BlockStack gap="400">
                        <div style={{ width: "100%", maxWidth: "300px" }}>
                          <TextField
                            placeholder={I18n.t("partial.search_payment_rules")}
                            value={searchValue}
                            onChange={setSearchValue}
                            prefix={<Icon source={SearchMinor} />}
                            clearButton
                            onClearButtonClick={() => setSearchValue("")}
                          />
                        </div>
                        <DataTable
                          columnContentTypes={["text", "text", "text", "text"]}
                          headings={[
                            I18n.t("partial.order"),
                            I18n.t("partial.rule_name"),
                            I18n.t("partial.payment_amount"),
                            I18n.t("admin.actions"),
                          ]}
                          rows={rows}
                        />
                      </BlockStack>
                    )}
                    {selectedTab === 1 && (
                      <BlockStack gap={{ xs: "800", sm: "400" }}>
                        {/* Tax & Calculation Settings */}
                        <InlineGrid
                          columns={{ xs: "1fr", md: "2fr 5fr" }}
                          gap="400"
                        >
                          <Box
                            paddingInlineStart={{ xs: 400, sm: 0 }}
                            paddingInlineEnd={{ xs: 400, sm: 0 }}
                          >
                            <BlockStack gap="400">
                              <Text as="h3" variant="headingMd">
                                {I18n.t("partial.tax_calculations")}
                              </Text>
                              <Text as="p" variant="bodyMd">
                                {I18n.t("partial.tax_calculations_desc")}
                              </Text>
                            </BlockStack>
                          </Box>
                          <Card>
                            <BlockStack gap="400">
                              <Checkbox
                                label={I18n.t("partial.include_tax_in_product")}
                                checked={
                                  setting.isTaxIncludedWithProduct || false
                                }
                                onChange={handleSettingChange(
                                  "isTaxIncludedWithProduct",
                                )}
                              />
                              <TextField
                                label={I18n.t("partial.partial_tax_text")}
                                value={setting.preV2PartialTaxText || ""}
                                onChange={handleSettingChange(
                                  "preV2PartialTaxText",
                                )}
                              />
                            </BlockStack>
                          </Card>
                        </InlineGrid>

                        <Divider />

                        {/* Shipping Settings */}
                        <InlineGrid
                          columns={{ xs: "1fr", md: "2fr 5fr" }}
                          gap="400"
                        >
                          <Box
                            paddingInlineStart={{ xs: 400, sm: 0 }}
                            paddingInlineEnd={{ xs: 400, sm: 0 }}
                          >
                            <BlockStack gap="400">
                              <Text as="h3" variant="headingMd">
                                {I18n.t("partial.shipping_configuration")}
                              </Text>
                              <Text as="p" variant="bodyMd">
                                {I18n.t("partial.shipping_configuration_desc")}
                              </Text>
                            </BlockStack>
                          </Box>
                          <Card>
                            <BlockStack gap="400">
                              <TextField
                                label={I18n.t("partial.shipping_rate_keyword")}
                                value={setting.partialShippingKeyword || ""}
                                onChange={handleSettingChange(
                                  "partialShippingKeyword",
                                )}
                                helpText={
                                  isPaidPlan
                                    ? I18n.t("partial.shipping_rate_keyword_help")
                                    : I18n.t("partial.cod_form_enabled_paid_only")
                                }
                                placeholder={I18n.t(
                                  "partial.shipping_rate_keyword_placeholder",
                                )}
                                disabled={!isPaidPlan}
                              />
                              {!isPaidPlan && (
                                <Text as="p" variant="bodyMd" tone="subdued">
                                  <Link
                                    url="#"
                                    onClick={(e) => {
                                      e.preventDefault();
                                      window.history.pushState(
                                        {},
                                        "",
                                        "/subscription",
                                      );
                                      window.dispatchEvent(
                                        new PopStateEvent("popstate"),
                                      );
                                    }}
                                  >
                                    {I18n.t("prepaid_discount.upgrade_cta")}
                                  </Link>
                                </Text>
                              )}
                            </BlockStack>
                          </Card>
                        </InlineGrid>

                        <Divider />

                        {/* Payment Flow Section */}
                        <InlineGrid
                          columns={{ xs: "1fr", md: "2fr 5fr" }}
                          gap="400"
                        >
                          <Box
                            paddingInlineStart={{ xs: 400, sm: 0 }}
                            paddingInlineEnd={{ xs: 400, sm: 0 }}
                          >
                            <BlockStack gap="400">
                              <Text as="h3" variant="headingMd">
                                {I18n.t("partial.payment_flow")}
                              </Text>
                              <Text as="p" variant="bodyMd">
                                {I18n.t("partial.payment_flow_desc")}
                              </Text>
                            </BlockStack>
                          </Box>
                          <Card>
                            <BlockStack gap="400">
                              <ChoiceList
                                title=""
                                choices={[
                                  {
                                    label: I18n.t("partial.same_order"),
                                    value: "SAME_ORDER",
                                    helpText: I18n.t("partial.same_order_help"),
                                  },
                                  {
                                    label: I18n.t("partial.new_order"),
                                    value: "NEW_ORDER",
                                    helpText: I18n.t("partial.new_order_help"),
                                  },
                                ]}
                                selected={[
                                  setting.partialPaymentFlow || "SAME_ORDER",
                                ]}
                                onChange={(selected) =>
                                  handleSettingChange("partialPaymentFlow")(
                                    selected[0],
                                  )
                                }
                              />
                            </BlockStack>
                          </Card>
                        </InlineGrid>
                      </BlockStack>
                    )}
                  </Box>
                </Tabs>
              </Card>
            )}
          </BlockStack>
        </Layout.Section>

      </Layout>

      <UiCustomizationEditor
        open={uiModalOpen}
        onClose={() => setUiModalOpen(false)}
        isExtensionEnabled={isExtensionEnabled}
        initialSection="payments"
      />
    </Page>
  );
}

export default PartialPayments;

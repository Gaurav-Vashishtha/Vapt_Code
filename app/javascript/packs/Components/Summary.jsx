import React, {
  useContext,
  useEffect,
  useState,
  useCallback,
  useRef,
} from "react";
import {
  Page,
  Layout,
  Card,
  Text,
  Button,
  Icon,
  Select,
  Badge,
  BlockStack,
  InlineStack,
  InlineGrid,
  Divider,
  Box,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
  Banner,
  Link,
  List,
} from "@shopify/polaris";
import ImpactStats from "./Analytics/ImpactStats";
import MessageSummaryCard from "./Analytics/MessageSummaryCard";
import { DEFAULT_DAYS, dayOptions } from "./Analytics/dateRange";
import {
  CircleTickMajor,
  CircleCancelMajor,
  AnalyticsMajor,
  OrdersMajor,
  NotificationMajor,
  EmailMajor,
  CashDollarMajor,
  ShipmentMajor,
  SettingsMajor,
  ViewMajor,
  CartMajor,
  RefreshMinor,
  ChevronRightMinor,
} from "@shopify/polaris-icons";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from "recharts";
import { StoreContext } from "../Context/Store";
import CallbackRequest from "./CallbackRequest";
import OneClickCheckoutCard from "./OneClickCheckoutCard";
import CodFormSummaryCard from "../Pages/CodForm/Summary/CodFormSummaryCard";
import InstagramFollowCard from "./InstagramFollowCard";
import ProUpgradeSavingsCard from "./ProUpgradeSavingsCard";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";
import Api from "../Services/Api";
import LanguageDropdown from "./Integrations/LanguageDropdown";
import I18n from "../i18n-lang";
import FreeWalletBalance from "./FreeWalletBalance";
import { navigateTo } from "../../utils/navigate";
import { isShopifyPlusStore } from "./OTPPlacementOptions";

const SUMMARY_FEATURE_RR_KEY = "cod_king_summary_feature_rr_v1";

function getDisabledFeatureSuggestions(
  setting,
  isCodShowHideEnabled,
  isExtensionEnabled,
  shop,
) {
  const s = setting || {};
  const items = [];
  if (!(s.sms || s.enablePreOrderOtp)) {
    items.push({
      id: "otp",
      messageKey: "summary.suggestion_enable_otp",
      path: "/features/otp/pre-order",
    });
  }
  if (!(s.codFeeEnabled || s.enableShippingCodFees)) {
    items.push({
      id: "cod_fees",
      messageKey: "summary.suggestion_enable_cod_fees",
      path: "/features/cod-fees",
    });
  }
  if (!(s.abandonedCartEnabled || s.acWhatsapp)) {
    items.push({
      id: "abandoned_cart",
      messageKey: "summary.suggestion_enable_abandoned_cart",
      path: "/features/notifications",
    });
  }
  if (!(s.confirmationSmsEnabled || s.confirmationWhatsapp)) {
    items.push({
      id: "confirmation",
      messageKey: "summary.suggestion_enable_confirmation",
      path: "/features/notifications",
    });
  }
  if (!(s.enableFulfilmentMessage || s.fulfilmentWhatsapp)) {
    items.push({
      id: "fulfillment",
      messageKey: "summary.suggestion_enable_fulfillment",
      path: "/features/notifications",
    });
  }
  if (!s.partialPaymentEnabled) {
    items.push({
      id: "partial_payment",
      messageKey: "summary.suggestion_enable_partial_payment",
      path: "/features/partial-payment",
    });
  }
  if (!isCodShowHideEnabled) {
    items.push({
      id: "cod_show_hide",
      messageKey: "summary.suggestion_enable_cod_show_hide",
      path: "/features/limit-cod",
    });
  }
  const plusExt =
    s.plusCheckoutOtpExtensionEnabled ?? s.plus_checkout_otp_extension_enabled;
  const plusExtOn =
    plusExt === true ||
    plusExt === "true" ||
    plusExt === 1 ||
    plusExt === "1";
  if (isShopifyPlusStore(shop) && !plusExtOn) {
    items.push({
      id: "plus_checkout_extension",
      messageKey: "summary.suggestion_plus_checkout_extension",
      path: "/features/shopify-plus-widget",
    });
  }
  return items;
}

function humanizeShippingStatus(key) {
  if (!key) return "";
  const normalized = key.toString().trim().toLowerCase();
  const slug = normalized.replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  const tKey = `summary.shipping_status_${slug}`;
  const translated = I18n.t(tKey);
  // i18n-js returns "translation missing: <locale>.<key>" when missing.
  if (translated && !String(translated).startsWith("translation missing:")) {
    return translated;
  }
  return normalized
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

const Summary = () => {
  const {
    shop: [shop],
    setting: [setting],
    plan: [plan],
  } = useContext(StoreContext);

  const [loading, setLoading] = useState(true);
  const [days, setDays] = useState(DEFAULT_DAYS);
  const [shippingDays, setShippingDays] = useState(DEFAULT_DAYS);
  const [prepaidMixDays, setPrepaidMixDays] = useState(DEFAULT_DAYS);
  const [shippingMetrics, setShippingMetrics] = useState(null);
  const [prepaidMixMetrics, setPrepaidMixMetrics] = useState(null);
  const [rawData, setRawData] = useState({
    orderCount: [],
    pieData: { cod_sales: 0, prepaid_sales: 0 },
    metrics: {},
    messages: {},
  });
  const [isCodShowHideEnabled, setIsCodShowHideEnabled] = useState(false);
  const [localProviders, setLocalProviders] = useState([]);
  const [loadingProviders, setLoadingProviders] = useState(false);
  const [updatingPermissions, setUpdatingPermissions] = useState(false);
  const [needsReauth, setNeedsReauth] = useState(false);
  const [permissionsFeedback, setPermissionsFeedback] = useState({
    message: "",
    status: "info",
  });
  const [isExtensionEnabled, setIsExtensionEnabled] = useState(false);
  const [isCheckingTheme, setIsCheckingTheme] = useState(false);
  const [featureSuggestion, setFeatureSuggestion] = useState(null);
  // Whether the merchant has a verified BSP WhatsApp number connected. Used
  // to decide whether to surface the WhatsApp-setup highlight card (when no
  // number) or the existing abandoned-cart-intelligence card (when a number
  // is connected — at that point AC reminders are the next step to enable).
  const [whatsappAccountState, setWhatsappAccountState] = useState({
    loaded: false,
    connected: false,
    status: null,
  });

  const mountedRef = useRef(true);
  const prevDaysRef = useRef(days);
  const themeCheckIntervalRef = useRef(null);
  const checkCountRef = useRef(0);
  const prevLoadingRef = useRef(false);

  /**
   * App Bridge v4 Navigation Handler
   * Replaces legacy navigateTo to stay within embedded context
   */
  const handleAppNavigation = (path) => {
    navigateTo(path);
  };

  const daysOptions = dayOptions();

  const fetchSummaryMetricsForDays = useCallback(
    async (daysValue) => {
      if (!shop?.id) return {};
      const resp = await fetch(
        `https://${process.env.APP_HOST}/analytics/summary?shop_id=${shop.id}&days=${daysValue}`,
      )
        .then((res) => res.json())
        .catch(() => ({ metrics: {} }));
      return resp?.metrics || {};
    },
    [shop?.id],
  );

  const loadData = useCallback(async () => {
    if (!shop?.id) return;
    setLoading(true);

    try {
      const metricsResponse = await fetch(
        `https://${process.env.APP_HOST}/analytics/summary?shop_id=${shop.id}&days=${days}`,
      )
        .then((res) => res.json())
        .catch(() => ({ metrics: {} }));

      if (mountedRef.current) {
        setRawData((prev) => ({
          ...prev,
          metrics: metricsResponse?.metrics || {},
        }));
        setLoading(false);
      }
    } catch (error) {
      if (mountedRef.current) setLoading(false);
    }
  }, [shop?.id, days]);

  const checkThemeIntegration = useCallback(async () => {
    if (!shop?.shopify_domain && !shop?.shopifyDomain) return false;

    try {
      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/is_cod_king_block_enabled?shopifyDomain=${shop?.shopify_domain || shop?.shopifyDomain}`,
      );
      const data = await response.json();
      const assetEnabled = !!data?.assetEnabled;
      if (mountedRef.current) {
        setIsExtensionEnabled(assetEnabled);
      }
      return assetEnabled;
    } catch (error) {
      console.error("Error checking theme integration:", error);
      return false;
    }
  }, [shop?.shopify_domain, shop?.shopifyDomain]);

  const startThemeMonitoring = useCallback(() => {
    if (themeCheckIntervalRef.current) {
      clearInterval(themeCheckIntervalRef.current);
      themeCheckIntervalRef.current = null;
    }

    setIsCheckingTheme(true);
    checkCountRef.current = 0;

    themeCheckIntervalRef.current = setInterval(async () => {
      checkCountRef.current += 1;
      const enabled = await checkThemeIntegration();

      if (enabled || checkCountRef.current >= 24) {
        clearInterval(themeCheckIntervalRef.current);
        themeCheckIntervalRef.current = null;
        if (mountedRef.current) {
          setIsCheckingTheme(false);
        }
      }
    }, 5000);
  }, [checkThemeIntegration]);

  const handleThemeIntegrationClick = useCallback(() => {
    if (!shop?.shopify_domain && !shop?.shopifyDomain) return;
    startThemeMonitoring();
    window.open(
      `https://${shop?.shopify_domain || shop?.shopifyDomain}/admin/themes/current/editor?context=apps&template=cart&activateAppId=99553eb5-bf07-4ce0-9263-7e5f10cab22c/app-embed`,
      "_blank",
    );
  }, [shop?.shopify_domain, shop?.shopifyDomain, startThemeMonitoring]);

  useEffect(() => {
    if (shop?.id) loadData();
  }, [shop?.id, days]);

  // Keep section ranges in sync with global *unless* user changed them.
  useEffect(() => {
    const prevDays = prevDaysRef.current;
    if (shippingDays === prevDays) setShippingDays(days);
    if (prepaidMixDays === prevDays) setPrepaidMixDays(days);
    prevDaysRef.current = days;
  }, [days, shippingDays, prepaidMixDays]);

  // Per-section metrics: refetch only when a section range differs from global.
  useEffect(() => {
    if (!shop?.id) return;
    let cancelled = false;
    if (shippingDays === days) {
      setShippingMetrics(null);
      return;
    }
    fetchSummaryMetricsForDays(shippingDays).then((m) => {
      if (!cancelled) setShippingMetrics(m);
    });
    return () => {
      cancelled = true;
    };
  }, [shop?.id, shippingDays, days, fetchSummaryMetricsForDays]);

  useEffect(() => {
    if (!shop?.id) return;
    let cancelled = false;
    if (prepaidMixDays === days) {
      setPrepaidMixMetrics(null);
      return;
    }
    fetchSummaryMetricsForDays(prepaidMixDays).then((m) => {
      if (!cancelled) setPrepaidMixMetrics(m);
    });
    return () => {
      cancelled = true;
    };
  }, [shop?.id, prepaidMixDays, days, fetchSummaryMetricsForDays]);

  const sectionShippingMetrics =
    shippingDays === days ? rawData.metrics : shippingMetrics || {};
  const sectionPrepaidMixMetrics =
    prepaidMixDays === days ? rawData.metrics : prepaidMixMetrics || {};

  useEffect(() => {
    if (!shop?.id) return;
    Api.get("/settings/is_cod_show_hide_enabled").then((response) => {
      if (mountedRef.current) {
        const enabled =
          response?.data?.isCodShowHideEnabled ??
          response?.data?.data?.isCodShowHideEnabled ??
          response?.isCodShowHideEnabled ??
          false;
        setIsCodShowHideEnabled(!!enabled);
      }
    });
  }, [shop?.id]);

  // Fetch the merchant's BSP WhatsApp account state — drives whether the
  // sidebar highlights "Add your WhatsApp number" (when no number is
  // connected) or falls back to the abandoned-cart-intelligence card.
  useEffect(() => {
    if (!shop?.id) return;
    Api.get("/api/whatsapp/account")
      .then((response) => {
        if (!mountedRef.current) return;
        const data = response?.data || {};
        setWhatsappAccountState({
          loaded: true,
          connected: !!data.connected,
          status: data.status || null,
        });
      })
      .catch(() => {
        if (mountedRef.current) {
          setWhatsappAccountState({
            loaded: true,
            connected: false,
            status: null,
          });
        }
      });
  }, [shop?.id]);

  useEffect(() => {
    checkThemeIntegration();
  }, [checkThemeIntegration]);

  useEffect(() => {
    if (prevLoadingRef.current && !loading && shop?.id) {
      const items = getDisabledFeatureSuggestions(
        setting,
        isCodShowHideEnabled,
        isExtensionEnabled,
        shop,
      );
      if (!items.length) {
        setFeatureSuggestion(null);
      } else {
        let idx = parseInt(localStorage.getItem(SUMMARY_FEATURE_RR_KEY) || "0", 10);
        if (Number.isNaN(idx)) idx = 0;
        const picked = items[idx % items.length];
        localStorage.setItem(SUMMARY_FEATURE_RR_KEY, String(idx + 1));
        setFeatureSuggestion(picked);
      }
    }
    prevLoadingRef.current = loading;
  }, [
    loading,
    shop?.id,
    shop?.shopify_plan,
    shop?.shopifyPlan,
    setting,
    isCodShowHideEnabled,
    isExtensionEnabled,
  ]);

  useEffect(() => {
    if (!shop?.country_code) return;
    Api.get("/settings/local_providers", {
      params: { country_code: shop.country_code },
    }).then((response) => {
      if (mountedRef.current) {
        setLocalProviders(
          response?.data?.providers || response?.providers || [],
        );
      }
    });
  }, [shop?.country_code]);

  useEffect(() => {
    if (!shop?.shopify_domain && !shop?.shopifyDomain) return;
    Api.get("/check_permissions", {
      params: { shop: shop?.shopify_domain || shop?.shopifyDomain },
    })
      .then((response) => {
        if (mountedRef.current) {
          setNeedsReauth(
            !!(response?.data?.needsReauth ?? response?.data?.needs_reauth),
          );
        }
      })
      .catch(() => {
        if (mountedRef.current) setNeedsReauth(true);
      });
  }, [shop?.shopify_domain, shop?.shopifyDomain]);

  useEffect(() => {
    return () => {
      mountedRef.current = false;
      if (themeCheckIntervalRef.current) {
        clearInterval(themeCheckIntervalRef.current);
      }
    };
  }, []);

  const handleUpdatePermissions = useCallback(async () => {
    setUpdatingPermissions(true);
    try {
      const response = await Api.post("/update_permissions", {
        shop: shop?.shopify_domain || shop?.shopifyDomain,
      });
      // Response keys are camelized by Api interceptor, so scope_refresh_url becomes scopeRefreshUrl
      const scopeRefreshUrl =
        response?.data?.scopeRefreshUrl || response?.data?.scope_refresh_url;
      if (scopeRefreshUrl) {
        // Redirect to Shopify OAuth to review/update app permissions (when they return, page reloads and check_permissions runs again)
        window.open(scopeRefreshUrl, "_top");
      } else {
        setNeedsReauth(false);
        setPermissionsFeedback({
          message: response?.data?.message || I18n.t("summary.permissions_up_to_date"),
          status: "success",
        });
      }
    } catch (error) {
      console.error("Error updating permissions:", error);
      setPermissionsFeedback({
        message: I18n.t("summary.permissions_check_failed"),
        status: "critical",
      });
    } finally {
      setUpdatingPermissions(false);
    }
  }, []);

  const featureList = [
    {
      key: I18n.t("summary.OTP_Verification"),
      value: setting?.sms || setting?.enablePreOrderOtp,
      path: "/features/otp/pre-order",
    },
    {
      key: I18n.t("summary.partial_payment"),
      value: setting?.partialPaymentEnabled,
      path: "/features/partial-payment",
      isNew: false,
    },
    {
      key: I18n.t("summary.cod_show_hide"),
      value: isCodShowHideEnabled,
      path: "/features/limit-cod",
    },
    {
      key: I18n.t("summary.prepaid_discount"),
      value: setting?.partialPaymentEnabled,
      path: "/features/prepaid-discount",
      isNew: true,
    },
    {
      key: I18n.t("summary.abandoned_cart"),
      value: setting?.abandonedCartEnabled || setting?.acWhatsapp,
      path: "/features/notifications",
    },
    {
      key: I18n.t("summary.cod_fees"),
      value: setting?.codFeeEnabled || setting?.enableShippingCodFees,
      path: "/features/cod-fees",
    },
    {
      key: I18n.t("summary.confirmation_message"),
      value: setting?.confirmationSmsEnabled || setting?.confirmationWhatsapp,
      path: "/features/notifications",
    },
    {
      key: I18n.t("summary.fulfillment_message"),
      value: setting?.enableFulfilmentMessage || setting?.fulfilmentWhatsapp,
      path: "/features/notifications",
    },
    {
      key: I18n.t("admin.plus_checkout_extension_page_title"),
      value: !!(
        setting?.plusCheckoutOtpExtensionEnabled ||
        setting?.plus_checkout_otp_extension_enabled
      ),
      path: "/features/shopify-plus-widget",
      requiresShopifyPlus: true,
    },
  ];

  const codFormBootstrap = useCodFormBootstrap();
  const isPreOrderOtpEnabled =
    setting?.enablePreOrderOtp === true || setting?.enable_pre_order_otp === true;
  // Indian shop on the Free plan that verifies orders with OTP — pre-order OTP, post-order
  // OTP (setting.sms) or the COD Form's own OTP (cod_form general.otp.enabled, via bootstrap):
  // show the Pro upgrade card at the top instead of the Abandoned cart intelligence row.
  // "Free" = the Free plan or any plan priced 0, as PricingV3India.free_plan? decides
  // (RabbitPay plans excluded).
  const isOtpEnabled =
    isPreOrderOtpEnabled ||
    setting?.sms === true ||
    setting?.sms === "true" ||
    codFormBootstrap?.otpEnabled === true;
  const planName = String(plan?.name || "").toLowerCase();
  const planPrice = String(plan?.price ?? "").trim();
  const isFreePlan =
    !!plan &&
    !planName.includes("rabbit") &&
    (planName === "free" || planPrice === "" || Number(planPrice) === 0);
  const showProUpgradeCard =
    String(shop?.country_code || shop?.countryCode || "").toUpperCase() === "IN" &&
    isFreePlan &&
    isOtpEnabled;

  // Check if shop has charge_id and setting is locked
  const showCappedAmountWarning = shop?.charge_id && setting?.locked;

  if (loading) {
    return (
      <SkeletonPage title={I18n.t("summary.cod_king_title")} primaryAction>
        <Layout>
          <Layout.Section>
            <Card>
              <Box padding="50">
                <SkeletonBodyText lines={1} />
              </Box>
            </Card>
            <br />
            <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="500">
              {[...Array(4)].map((_, i) => (
                <Card key={i} padding="500">
                  <BlockStack gap="200">
                    <SkeletonBodyText lines={1} />
                    <SkeletonDisplayText size="medium" />
                  </BlockStack>
                </Card>
              ))}
            </InlineGrid>
          </Layout.Section>
          <Layout.Section>
            <InlineGrid columns={{ xs: 1, lg: "2fr 1fr" }} gap="500">
              <Card>
                <Box padding="400">
                  <BlockStack gap="400">
                    <SkeletonDisplayText size="small" />
                    <InlineGrid columns={{ xs: 1, sm: 3 }} gap="400">
                      {[...Array(3)].map((_, i) => (
                        <Box
                          key={i}
                          padding="400"
                          background="bg-surface-secondary"
                          borderRadius="200"
                        >
                          <BlockStack gap="100">
                            <SkeletonBodyText lines={1} />
                            <SkeletonDisplayText size="small" />
                          </BlockStack>
                        </Box>
                      ))}
                    </InlineGrid>
                    <Divider />
                    <SkeletonBodyText lines={3} />
                  </BlockStack>
                </Box>
              </Card>
              <BlockStack gap="500">
                <Card>
                  <Box padding="500">
                    <BlockStack gap="400">
                      <SkeletonDisplayText size="small" />
                      <SkeletonBodyText lines={7} />
                    </BlockStack>
                  </Box>
                </Card>
                <Card>
                  <Box padding="500">
                    <BlockStack gap="400">
                      <SkeletonDisplayText size="small" />
                      <SkeletonBodyText lines={4} />
                    </BlockStack>
                  </Box>
                </Card>
              </BlockStack>
            </InlineGrid>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  return (
    <Page
      fullWidth
      title={I18n.t("summary.cod_king_title")}
      subtitle={I18n.t("summary.key_metrics_subtitle")}
      secondaryActions={<LanguageDropdown />}
      primaryAction={
        <InlineStack gap="200">
          {needsReauth && (
            <Button
              onClick={handleUpdatePermissions}
              loading={updatingPermissions}
              variant="primary"
            >
              {I18n.t("summary.app_update_needed")}
            </Button>
          )}
          <Button icon={RefreshMinor} variant="tertiary" onClick={loadData} />
          <Select options={daysOptions} value={days} onChange={setDays} />
        </InlineStack>
      }
    >
      <Layout>
        <Layout.Section>
          {permissionsFeedback.message && (
            <Box paddingBlockEnd="500">
              <Banner
                status={permissionsFeedback.status}
                onDismiss={() =>
                  setPermissionsFeedback({ message: "", status: "info" })
                }
              >
                <Text variant="bodyMd" as="p">
                  {permissionsFeedback.message}
                </Text>
              </Banner>
            </Box>
          )}
          {showCappedAmountWarning && (
            <Box paddingBlockEnd="500">
              <Banner status="warning" onDismiss={() => {}}>
                <Text variant="bodyMd" as="p">
                  {I18n.t("summary.capped_amount_exhausted")}{" "}
                  <Link
                    url="https://www.notion.so/codking/Increase-Capped-amount-for-COD-King-2bd6e71a63f980e7986dd11e290595b2"
                    external
                  >
                    {I18n.t("summary.learn_increase_capped_amount")}
                  </Link>{" "}
                  {I18n.t("summary.continue_sending_notifications")}
                </Text>
              </Banner>
            </Box>
          )}
          {showProUpgradeCard && (
            <ProUpgradeSavingsCard onFallback={() => handleAppNavigation("/subscription")} />
          )}
          <InstagramFollowCard />
          <Card padding="0">
            <Box paddingBlock="300" paddingInline="400">
              <InlineStack
                align="space-between"
                blockAlign="center"
                gap="300"
                wrap={false}
              >
                <BlockStack gap="050">
                  <InlineStack gap="150" blockAlign="center">
                    <Text variant="headingSm" as="h3">
                      {I18n.t("summary.theme_app_embed")}
                    </Text>
                    <Badge tone={isExtensionEnabled ? "success" : "new"} size="small">
                      {isExtensionEnabled
                        ? I18n.t("summary.on")
                        : I18n.t("summary.off")}
                    </Badge>
                  </InlineStack>
                  <Text variant="bodySm" as="p" tone="subdued">
                    {isExtensionEnabled
                      ? I18n.t("summary.theme_active")
                      : I18n.t("summary.theme_inactive")}
                  </Text>
                </BlockStack>
                <Button
                  onClick={handleThemeIntegrationClick}
                  loading={isCheckingTheme}
                  size="slim"
                >
                  {I18n.t("summary.open_theme")}
                </Button>
              </InlineStack>
            </Box>

            <OneClickCheckoutCard />
            <CodFormSummaryCard />

            {whatsappAccountState.loaded && (() => {
              const isLinked =
                whatsappAccountState.connected &&
                whatsappAccountState.status === "verified";
              return (
                <React.Fragment>
                  <Divider />
                  <Box paddingBlock="300" paddingInline="400">
                    <InlineStack
                      align="space-between"
                      blockAlign="center"
                      gap="300"
                      wrap={false}
                    >
                      <BlockStack gap="050">
                        <InlineStack gap="150" blockAlign="center">
                          <Text variant="headingSm" as="h3">
                            {I18n.t("summary.send_whatsapp_from_your_own_brand")}
                          </Text>
                          <Badge tone="success" size="small">
                            {I18n.t("summary.free_service_messages")}
                          </Badge>
                        </InlineStack>
                        <Text variant="bodySm" as="p" tone="subdued">
                          {isLinked
                            ? "Order confirmations, shipping updates and cart reminders go out automatically from your own number."
                            : "Send order updates customers actually open — from your own WhatsApp number, live in minutes."}
                        </Text>
                      </BlockStack>
                      <Button
                        size="slim"
                        onClick={() =>
                          handleAppNavigation(
                            isLinked
                              ? "/features/whatsapp"
                              : "/features/whatsapp/account"
                          )
                        }
                      >
                        {isLinked ? "Manage WhatsApp" : "Connect number"}
                      </Button>
                    </InlineStack>
                  </Box>
                </React.Fragment>
              );
            })()}

            {whatsappAccountState.loaded && isPreOrderOtpEnabled && !showProUpgradeCard && (
              <React.Fragment>
                <Divider />
                <Box paddingBlock="300" paddingInline="400">
                  <InlineStack
                    align="space-between"
                    blockAlign="center"
                    gap="300"
                    wrap={false}
                  >
                    <BlockStack gap="050">
                      <InlineStack gap="150" blockAlign="center">
                        <Text variant="headingSm" as="h3">
                          {I18n.t("summary.abandoned_cart_intelligence_title")}
                        </Text>
                        <Badge tone="info" size="small">
                          {I18n.t("summary.new_badge")}
                        </Badge>
                      </InlineStack>
                      <Text variant="bodySm" as="p" tone="subdued">
                        {I18n.t("summary.abandoned_cart_intelligence_body")}
                      </Text>
                    </BlockStack>
                    <Button
                      size="slim"
                      onClick={() =>
                        handleAppNavigation(
                          "/usage-analytics/cod-king-abandoned-carts",
                        )
                      }
                    >
                      {I18n.t("summary.abandoned_cart_intelligence_cta")}
                    </Button>
                  </InlineStack>
                </Box>
              </React.Fragment>
            )}

            <Divider />
            <Box paddingBlock="300" paddingInline="400">
              <InlineStack
                align="space-between"
                blockAlign="center"
                gap="300"
                wrap={false}
              >
                <BlockStack gap="050">
                  <InlineStack gap="150" blockAlign="center">
                    <Text variant="headingSm" as="h3">
                      {I18n.t("summary.referral_program_title")}
                    </Text>
                    <Badge tone="success" size="small">
                      {I18n.t("summary.referral_program_badge")}
                    </Badge>
                  </InlineStack>
                  <Text variant="bodySm" as="p" tone="subdued">
                    {I18n.t("summary.referral_program_body")}
                  </Text>
                </BlockStack>
                <Button
                  url="https://app.codking.tech/referral/signup"
                  external
                  size="slim"
                >
                  {I18n.t("summary.referral_program_cta")}
                </Button>
              </InlineStack>
            </Box>
          </Card>
          <Box paddingBlockStart="500" />
          <BlockStack gap="500">
            <ImpactStats days={days} />
            <MessageSummaryCard days={days} />
          </BlockStack>
        </Layout.Section>

        <Layout.Section>
          <InlineGrid columns={{ xs: 1, lg: "2fr 1fr" }} gap="500">
            <BlockStack gap="500">
              {/* DISABLED: Sales & Order Analytics section */}
              {/* <Card>
                <Box padding="500">
                  <BlockStack gap="500">
                    <Text variant="headingMd" as="h2">{I18n.t("summary.sales_order_analytics")}</Text>
                    <InlineGrid columns={{ xs: 1, md: 2 }} gap="500">
                      <Box>
                        <Text variant="headingSm">{I18n.t("summary.order_trends")}</Text>
                        <div style={{ height: "200px" }}>
                          <ResponsiveContainer width="100%" height="100%">
                            <LineChart data={rawData.orderCount}><XAxis dataKey="date" /><YAxis /><RechartsTooltip /><Line type="monotone" dataKey="order_count" stroke="#007ace" /></LineChart>
                          </ResponsiveContainer>
                        </div>
                      </Box>
                      <Box>
                        <Text variant="headingSm">{I18n.t("summary.cod_vs_prepaid")}</Text>
                        <div style={{ height: "200px" }}>
                          <ResponsiveContainer width="100%" height="100%">
                            <PieChart><Pie data={pieChartData} cx="50%" cy="50%" outerRadius={80} dataKey="value">{pieChartData.map((e, i) => <Cell key={i} fill={i === 0 ? "#6A5ACD" : "#20B2AA"} />)}</Pie><RechartsTooltip /></PieChart>
                          </ResponsiveContainer>
                        </div>
                      </Box>
                    </InlineGrid>
                  </BlockStack>
                </Box>
              </Card> */}


              <Card>
                <Box padding="400">
                  <BlockStack gap="400">
                    <InlineStack align="space-between" blockAlign="center">
                      <Text variant="headingMd" as="h2">
                        {I18n.t("summary.shipping_delivery_title")}
                      </Text>
                      <Select
                        options={daysOptions}
                        value={shippingDays}
                        onChange={setShippingDays}
                      />
                    </InlineStack>
                    <Text variant="bodySm" as="p" tone="subdued">
                      {I18n.t("summary.shipping_delivery_help")}
                    </Text>
                    {(() => {
                      const ship = sectionShippingMetrics?.shipping_stats;
                      const terminal = ship?.terminal_total ?? 0;
                      const delivered = ship?.delivered_count ?? 0;
                      const undelivered = ship?.undelivered_count ?? 0;
                      const other = ship?.other_statuses || {};
                      const byPay = ship?.by_payment_type || {};
                      if (!ship || (ship.with_status_total ?? 0) === 0) {
                        return (
                          <Text variant="bodyMd" tone="subdued" as="p">
                            {I18n.t("summary.shipping_no_status_data")}
                          </Text>
                        );
                      }
                      return (
                        <BlockStack gap="400">
                          {terminal > 0 && (
                            <Text variant="bodySm" tone="subdued" as="p">
                              {I18n.t("summary.shipping_terminal_basis", {
                                count: terminal,
                              })}
                            </Text>
                          )}
                          <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                            <Box
                              padding="400"
                              background="bg-surface-secondary"
                              borderRadius="200"
                            >
                              <BlockStack gap="100">
                                <Text variant="bodySm" tone="subdued">
                                  {I18n.t("summary.shipping_delivered")}
                                </Text>
                                <Text variant="headingLg" as="p">
                                  {terminal > 0
                                    ? `${delivered.toLocaleString()} (${ship.delivered_pct ?? 0}%)`
                                    : delivered.toLocaleString()}
                                </Text>
                              </BlockStack>
                            </Box>
                            <Box
                              padding="400"
                              background="bg-surface-secondary"
                              borderRadius="200"
                            >
                              <BlockStack gap="100">
                                <Text variant="bodySm" tone="subdued">
                                  {I18n.t("summary.shipping_undelivered_rto")}
                                </Text>
                                <Text variant="headingLg" as="p">
                                  {terminal > 0
                                    ? `${undelivered.toLocaleString()} (${ship.undelivered_pct ?? 0}%)`
                                    : undelivered.toLocaleString()}
                                </Text>
                              </BlockStack>
                            </Box>
                          </InlineGrid>

                          {Object.keys(other).length > 0 && (
                            <BlockStack gap="200">
                              <Text variant="bodyMd" fontWeight="semibold" as="p">
                                {I18n.t("summary.shipping_other_statuses")}
                              </Text>
                              <BlockStack gap="150">
                                {Object.entries(other).map(([statusKey, count]) => (
                                  <InlineStack
                                    key={statusKey}
                                    align="space-between"
                                    blockAlign="center"
                                  >
                                    <Text variant="bodyMd" as="span">
                                      {humanizeShippingStatus(statusKey)}
                                    </Text>
                                    <Text variant="bodyMd" fontWeight="semibold" as="span">
                                      {Number(count).toLocaleString()}
                                    </Text>
                                  </InlineStack>
                                ))}
                              </BlockStack>
                            </BlockStack>
                          )}

                          <Divider />

                          <BlockStack gap="200">
                            <Text variant="bodyMd" fontWeight="semibold" as="p">
                              {I18n.t("summary.shipping_by_payment_type")}
                            </Text>
                            <Text variant="bodySm" tone="subdued" as="p">
                              {I18n.t("summary.shipping_by_payment_type_help")}
                            </Text>
                            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                              {["cod", "prepaid"].map((pt) => {
                                const seg = byPay[pt] || {};
                                const t = seg.terminal_total ?? 0;
                                return (
                                  <Box
                                    key={pt}
                                    padding="400"
                                    background="bg-surface-secondary"
                                    borderRadius="200"
                                  >
                                    <BlockStack gap="150">
                                      <Text variant="bodySm" fontWeight="semibold">
                                        {pt === "cod"
                                          ? I18n.t("summary.cod")
                                          : I18n.t("summary.prepaid")}
                                      </Text>
                                      <Text variant="bodySm" tone="subdued">
                                        {I18n.t("summary.shipping_delivered_short")}:{" "}
                                        {(seg.delivered_count ?? 0).toLocaleString()}
                                        {t > 0
                                          ? ` (${seg.delivered_pct ?? 0}%)`
                                          : ""}
                                      </Text>
                                      <Text variant="bodySm" tone="subdued">
                                        {I18n.t("summary.shipping_undelivered_short")}:{" "}
                                        {(seg.undelivered_count ?? 0).toLocaleString()}
                                        {t > 0
                                          ? ` (${seg.undelivered_pct ?? 0}%)`
                                          : ""}
                                      </Text>
                                    </BlockStack>
                                  </Box>
                                );
                              })}
                            </InlineGrid>
                          </BlockStack>

                          {(ship.missing_status_count ?? 0) > 0 && (
                            <Text variant="bodySm" tone="subdued" as="p">
                              {I18n.t("summary.shipping_missing_status", {
                                count: ship.missing_status_count,
                              })}
                            </Text>
                          )}
                        </BlockStack>
                      );
                    })()}
                  </BlockStack>
                </Box>
              </Card>

              {sectionPrepaidMixMetrics?.prepaid_discount_ratios?.eligible && (
                <Card>
                  <Box padding="400">
                    <BlockStack gap="300">
                      <InlineStack align="space-between" blockAlign="center">
                        <Text variant="headingMd" as="h2">
                          {I18n.t("summary.prepaid_discount_ratio_title")}
                        </Text>
                        <Select
                          options={daysOptions}
                          value={prepaidMixDays}
                          onChange={setPrepaidMixDays}
                        />
                      </InlineStack>
                      <Text variant="bodySm" as="p" tone="subdued">
                        {I18n.t("summary.prepaid_discount_ratio_help")}
                      </Text>
                      <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
                        <Box
                          padding="400"
                          background="bg-surface-secondary"
                          borderRadius="200"
                        >
                          <BlockStack gap="100">
                            <Text variant="bodySm" tone="subdued">
                              {I18n.t("summary.prepaid_orders")}
                            </Text>
                            <Text variant="headingLg" as="p">
                              {(
                                sectionPrepaidMixMetrics.prepaid_discount_ratios
                                  .prepaid_orders ?? 0
                              ).toLocaleString()}
                              {sectionPrepaidMixMetrics.prepaid_discount_ratios
                                .total_classification_orders > 0
                                ? ` (${sectionPrepaidMixMetrics.prepaid_discount_ratios.prepaid_pct ?? 0}%)`
                                : ""}
                            </Text>
                          </BlockStack>
                        </Box>
                        <Box
                          padding="400"
                          background="bg-surface-secondary"
                          borderRadius="200"
                        >
                          <BlockStack gap="100">
                            <Text variant="bodySm" tone="subdued">
                              {I18n.t("summary.cod_orders")}
                            </Text>
                            <Text variant="headingLg" as="p">
                              {(
                                sectionPrepaidMixMetrics.prepaid_discount_ratios
                                  .cod_orders ?? 0
                              ).toLocaleString()}
                              {sectionPrepaidMixMetrics.prepaid_discount_ratios
                                .total_classification_orders > 0
                                ? ` (${sectionPrepaidMixMetrics.prepaid_discount_ratios.cod_pct ?? 0}%)`
                                : ""}
                            </Text>
                          </BlockStack>
                        </Box>
                      </InlineGrid>
                    </BlockStack>
                  </Box>
                </Card>
              )}
            </BlockStack>

            <BlockStack gap="500">
              <FreeWalletBalance />
              {/* Referral program card moved to top row */}
              <CallbackRequest />
              <Card>
                <Box padding="500">
                  <BlockStack gap="400">
                    <Text variant="headingMd">
                      {I18n.t("summary.features")}
                    </Text>
                    <BlockStack gap="0">
                      {featureList.map((feature, index) => {
                        const plusLocked =
                          feature.requiresShopifyPlus &&
                          !isShopifyPlusStore(shop);
                        return (
                          <div key={index}>
                            {plusLocked ? (
                              <Box paddingBlock="150">
                                <InlineGrid columns="minmax(0,1fr) auto" gap="200">
                                  <InlineStack gap="100" blockAlign="center">
                                    <Text variant="bodyMd" tone="subdued">
                                      {feature.key}
                                    </Text>
                                    {feature.isNew && (
                                      <Badge tone="info" size="small">
                                        {I18n.t("summary.new_badge")}
                                      </Badge>
                                    )}
                                  </InlineStack>
                                  <Badge
                                    tone={feature.value ? "success" : "attention"}
                                    progress={
                                      feature.value ? "complete" : "incomplete"
                                    }
                                  >
                                    {feature.value
                                      ? I18n.t("summary.enabled")
                                      : I18n.t("summary.disabled")}
                                  </Badge>
                                </InlineGrid>
                                <Box paddingBlockStart="100">
                                  <Text variant="bodySm" tone="subdued">
                                    {I18n.t(
                                      "admin.plus_checkout_otp_shopify_plus_only",
                                    )}
                                  </Text>
                                </Box>
                              </Box>
                            ) : (
                              <Button
                                variant="plain"
                                fullWidth
                                textAlign="left"
                                onClick={() =>
                                  handleAppNavigation(feature.path)
                                }
                              >
                                <Box width="100%" paddingBlock="150">
                                  <InlineGrid columns="minmax(0,1fr) auto" gap="200">
                                    <InlineStack gap="100" blockAlign="center">
                                      <Text variant="bodyMd">
                                        {feature.key}
                                      </Text>
                                      {feature.isNew && (
                                        <Badge tone="info" size="small">
                                          {I18n.t("summary.new_badge")}
                                        </Badge>
                                      )}
                                    </InlineStack>
                                    <InlineStack gap="200" blockAlign="center" wrap={false}>
                                      <Box minWidth="110px" style={{ textAlign: "right" }}>
                                        <Badge
                                          tone={feature.value ? "success" : "attention"}
                                          progress={
                                            feature.value ? "complete" : "incomplete"
                                          }
                                        >
                                          {feature.value
                                            ? I18n.t("summary.enabled")
                                            : I18n.t("summary.disabled")}
                                        </Badge>
                                      </Box>
                                      <Icon source={ChevronRightMinor} tone="subdued" />
                                    </InlineStack>
                                  </InlineGrid>
                                </Box>
                              </Button>
                            )}
                            {index < featureList.length - 1 && <Divider />}
                          </div>
                        );
                      })}
                    </BlockStack>
                  </BlockStack>
                </Box>
              </Card>

            </BlockStack>
          </InlineGrid>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default Summary;

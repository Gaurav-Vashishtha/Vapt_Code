import React, { useContext, useState, useEffect, useRef } from "react";
import {
  Page,
  Layout,
  Card,
  Text,
  Badge,
  Icon,
  Link,
  Button,
  BlockStack,
  InlineGrid,
  Box,
  Divider,
  InlineStack,
  TextField,
} from "@shopify/polaris";
import { CircleTickMajor, CircleMinusMajor } from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import I18n from "../i18n-lang";
import Api from "../Services/Api";
import FeatureCallout from "./FeatureCallout";
import { isShopifyPlusStore } from "./OTPPlacementOptions";
import { hasNoChargeId } from "../utils/shopUtils";
import { shopHasFullPaymentPrepaidDiscount } from "../utils/paidPlanDowngradeBlockers";

function renderManageAction(item, shop, handleRedirect, setTab) {
  if (item.href) {
    if (item.requiresShopifyPlus && !isShopifyPlusStore(shop)) {
      return (
        <Text variant="bodySm" tone="subdued">
          {I18n.t("admin.plus_checkout_otp_shopify_plus_only")}
        </Text>
      );
    }
    return (
      <Link
        url={item.href}
        onClick={(e) =>
          handleRedirect(
            e,
            item.href,
            item.href === "/features/notifications"
              ? { returnTo: "/features" }
              : {},
          )
        }
      >
        {I18n.t("admin.manage")}
      </Link>
    );
  }
  if (item.tab !== undefined) {
    return (
      <Button variant="plain" onClick={() => setTab(item.tab)}>
        {I18n.t("admin.manage")}
      </Button>
    );
  }
  return null;
}

function FeatureTile({ item, shop, handleRedirect, setTab }) {
  const manageAction = renderManageAction(
    item,
    shop,
    handleRedirect,
    setTab,
  );

  return (
    <Box
      padding="400"
      background="bg-surface-secondary"
      borderRadius="300"
      minHeight="100%"
    >
      <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
        <BlockStack gap="300">
          <InlineStack gap="200" align="start" blockAlign="start" wrap={false}>
            {!item.noStatus && (
              <Box>
                <Icon
                  source={item.enabled ? CircleTickMajor : CircleMinusMajor}
                  tone={item.enabled ? "success" : "attention"}
                />
              </Box>
            )}
            <BlockStack gap="100">
              <InlineStack gap="150" wrap blockAlign="center">
                <Text variant="bodyMd" fontWeight="semibold" as="span">
                  {item.title}
                </Text>
                {item.isNew && (
                  <Badge tone="info" size="small">
                    {I18n.t("features.new")}
                  </Badge>
                )}
              </InlineStack>
              <Text variant="bodySm" tone="subdued" as="p">
                {item.description}
              </Text>
            </BlockStack>
          </InlineStack>
        </BlockStack>

        <div style={{ marginTop: "auto", paddingTop: 12 }}>
          <InlineStack
            align={item.noStatus ? "end" : "space-between"}
            blockAlign="center"
            wrap={false}
            gap="200"
          >
            {!item.noStatus && (
              <Badge
                tone={item.enabled ? "success" : "attention"}
                progress={item.enabled ? "complete" : "incomplete"}
              >
                {item.enabled
                  ? I18n.t("admin.enabled")
                  : I18n.t("admin.disabled")}
              </Badge>
            )}
            {manageAction}
          </InlineStack>
        </div>
      </div>
    </Box>
  );
}

const Features = () => {
  const {
    shop: [shop],
    plan: [plan],
    setting: [setting],
    tab: [, setTab],
  } = useContext(StoreContext);

  const isPaidPlan =
    plan?.name?.toLowerCase() !== "free" && !hasNoChargeId(shop);

  const [isCodShowHideEnabled, setIsCodShowHideEnabled] = useState(false);
  const [prepaidDiscountFeatureEnabled, setPrepaidDiscountFeatureEnabled] =
    useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [whatsappConnected, setWhatsappConnected] = useState(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    if (!shop?.id) return;

    Api.get("/partial_rule_sets")
      .then((response) => {
        const rules = Array.isArray(response?.data) ? response.data : [];
        setPrepaidDiscountFeatureEnabled(
          shopHasFullPaymentPrepaidDiscount(setting, rules),
        );
      })
      .catch(() => setPrepaidDiscountFeatureEnabled(false));
  }, [shop?.id, setting?.partialPaymentEnabled]);

  useEffect(() => {
    if (!shop?.id) return;

    Api.get("/settings/is_cod_show_hide_enabled")
      .then((response) => {
        if (mountedRef.current) {
          const enabled =
            response?.data?.isCodShowHideEnabled ??
            response?.data?.data?.isCodShowHideEnabled ??
            response?.isCodShowHideEnabled ??
            false;
          setIsCodShowHideEnabled(!!enabled);
        }
      })
      .catch((error) => {
        console.error("[COD_SHOW_HIDE] Load failed:", error);
        if (mountedRef.current) {
          setIsCodShowHideEnabled(false);
        }
      });

    return () => {
      mountedRef.current = false;
    };
  }, [shop?.id]);

  // Is a WhatsApp Business account connected? Drives the "Integrate Your WhatsApp
  // Number" card's status. (Account state lives outside `setting`, so fetch it.)
  useEffect(() => {
    if (!shop?.id) return undefined;

    let cancelled = false;
    Api.get("/api/whatsapp/account")
      .then((response) => {
        const connected =
          response?.data?.connected ?? response?.data?.data?.connected ?? false;
        if (!cancelled) setWhatsappConnected(!!connected);
      })
      .catch(() => {
        if (!cancelled) setWhatsappConnected(false);
      });

    return () => {
      cancelled = true;
    };
  }, [shop?.id]);

  const handleRedirect = (e, path, extraQuery = {}) => {
    if (e) e.preventDefault();

    const params = new URLSearchParams(window.location.search || "");
    Object.entries(extraQuery).forEach(([k, v]) => {
      if (v != null && v !== "") params.set(k, String(v));
    });
    const qs = params.toString();
    const href = qs ? `${path}?${qs}` : path;

    window.history.pushState({}, "", href);

    const navEvent = new PopStateEvent("popstate");
    window.dispatchEvent(navEvent);

    if (typeof setTab === "function") {
      setTab(path);
    }
  };

  const features = [
    {
      section: I18n.t("admin.sections.order_verification"),
      description: I18n.t("features.secure_orders"),
      items: [
        {
          title: I18n.t("admin.otp_verification"),
          description: I18n.t("admin.otp_description"),
          enabled: setting.sms || setting.enablePreOrderOtp,
          href: "/features/otp/pre-order",
        },
        {
          title: I18n.t("admin.partial_heading"),
          description: I18n.t("admin.partial_description"),
          enabled: setting.partialPaymentEnabled,
          href: "/features/partial-payment",
        },
        {
          title: I18n.t("admin.cod_show_hide"),
          description: I18n.t("admin.cod_show_hide_description"),
          enabled: isCodShowHideEnabled,
          href: "/features/limit-cod",
        },
        {
          title: I18n.t("admin.cod_verification_whatsapp"),
          description: I18n.t("admin.cod_verification_whatsapp_description"),
          enabled: setting.sendVerificationLinkOnly,
          href: "/features/notifications",
        },
      ],
    },
    {
      section: I18n.t("admin.sections.conversion_boosters"),
      description: I18n.t("admin.sections.conversion_boosters_description"),
      items: [
        {
          title: I18n.t("admin.prepaid_discount"),
          description: I18n.t("admin.prepaid_discount_description"),
          enabled:
            isPaidPlan &&
            !!setting.partialPaymentEnabled &&
            prepaidDiscountFeatureEnabled,
          href: "/features/prepaid-discount",
          isNew: true,
        },
        {
          title: I18n.t("admin.cod_fees"),
          description: I18n.t("admin.cod_fees_description"),
          enabled: setting.codFeeEnabled || setting.enableShippingCodFees,
          href: "/features/cod-fees",
        },
        {
          title: I18n.t("onboarding.convert_heading"),
          description: I18n.t("admin.cod_to_prepaid_description"),
          enabled: setting.prepaidEnabled,
          href: "/features/cod-to-prepaid",
        },
      ],
    },
    {
      section: I18n.t("admin.sections.customer_engagement"),
      description: I18n.t("admin.sections.customer_engagement_description"),
      items: [
        {
          title: I18n.t("admin.confirmation_msg"),
          description: I18n.t("admin.confirmation_msg_description"),
          enabled:
            setting.confirmationSmsEnabled || setting.confirmationWhatsapp,
          href: "/features/notifications",
        },
        {
          title: I18n.t("admin.fulfilment_msg"),
          description: I18n.t("admin.fulfilment_msg_description"),
          enabled:
            setting.enableFulfilmentMessage || setting.fulfilmentWhatsapp,
          href: "/features/notifications",
        },
        {
          title: I18n.t("admin.abandoned_cart"),
          description: I18n.t("admin.abandoned_cart_description"),
          enabled: setting.abandonedCartEnabled || setting.acWhatsapp,
          href: "/features/notifications",
        },
        {
          title: I18n.t("whatsapp_integration.integrate_whatsapp_number"),
          description: I18n.t("admin.whatsapp_integration_description"),
          enabled: whatsappConnected,
          href: "/features/whatsapp",
        },
      ],
    },
    {
      section: I18n.t("admin.sections.shopify_plus_checkout"),
      description: I18n.t("admin.sections.shopify_plus_checkout_description"),
      items: [
        {
          title: I18n.t("admin.plus_checkout_extension_page_title"),
          description: I18n.t("admin.plus_checkout_extension_page_subtitle"),
          enabled: !!(
            setting.plusCheckoutOtpExtensionEnabled ||
            setting.plus_checkout_otp_extension_enabled
          ),
          href: "/features/shopify-plus-widget",
          requiresShopifyPlus: true,
        },
      ],
    },
  ];

  const normalizedQuery = searchQuery.trim().toLowerCase();
  const filteredFeatures = normalizedQuery
    ? features
        .map((section) => ({
          ...section,
          items: section.items.filter((item) => {
            const haystack = `${item.title ?? ""} ${item.description ?? ""}`
              .toLowerCase()
              .trim();
            return haystack.includes(normalizedQuery);
          }),
        }))
        .filter((section) => section.items.length > 0)
    : features;

  return (
    <Page
      title={I18n.t("admin.features_heading")}
      subtitle={I18n.t("admin.features_subtitle")}
      compactTitle
      backAction={{
        content: I18n.t("admin.back_to_summary"),
        onAction: (e) => handleRedirect(e, "/"),
      }}
    >
      <Layout>
        <Layout.Section variant="twoThirds">
          <Box paddingBlockEnd="400">
            <FeatureCallout
              illustration="docs"
              title={I18n.t("features.feature_setup_guide")}
              description={I18n.t("admin.need_help_subtitle") + " results."}
              docsUrl="https://codking.notion.site/Feature-Configuration-Guide"
              showChat
            />
          </Box>
          <Card padding="0">
            <Box padding={{ xs: "400", sm: "500" }}>
              <BlockStack gap="500">
                <TextField
                  label={I18n.t("admin.search", { defaultValue: "Search" })}
                  labelHidden
                  value={searchQuery}
                  onChange={setSearchQuery}
                  placeholder={I18n.t("features.search_features")}
                  autoComplete="off"
                  clearButton
                  onClearButtonClick={() => setSearchQuery("")}
                />

                {filteredFeatures.map((section, sectionIdx) => (
                  <React.Fragment key={sectionIdx}>
                    {sectionIdx > 0 && <Divider />}
                    <BlockStack gap="300">
                      <BlockStack gap="100">
                        <Text variant="headingMd" as="h2">
                          {section.section}
                        </Text>
                        {section.description && (
                          <Text variant="bodySm" tone="subdued">
                            {section.description}
                          </Text>
                        )}
                      </BlockStack>
                      <InlineGrid
                        columns={
                          section.items.length === 1
                            ? { xs: 1, sm: 1, lg: 1 }
                            : { xs: 1, sm: 2, lg: 2 }
                        }
                        gap="300"
                      >
                        {section.items.map((item, itemIdx) => (
                          <FeatureTile
                            key={itemIdx}
                            item={item}
                            shop={shop}
                            handleRedirect={handleRedirect}
                            setTab={setTab}
                          />
                        ))}
                      </InlineGrid>
                    </BlockStack>
                  </React.Fragment>
                ))}
              </BlockStack>
            </Box>
          </Card>
        </Layout.Section>

      </Layout>
    </Page>
  );
};

export default Features;

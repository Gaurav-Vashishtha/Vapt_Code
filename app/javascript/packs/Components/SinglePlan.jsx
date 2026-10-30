import React, { useContext, useState } from "react";
import { useAppBridge } from "@shopify/app-bridge-react";
import {
  Card,
  BlockStack,
  InlineStack,
  Text,
  Button,
  Badge,
  List,
  Modal,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
// Removed: import { Redirect } from "@shopify/app-bridge/actions"; // App Bridge v4 - use window.open instead
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import I18n from "../i18n-lang";
import { usePlanFeatureOrder } from "../utils/planFeatureOrder";
import { isUnlimitedFormOrders } from "../Pages/CodForm/utils";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";
import {
  planFeatureFontWeight,
  planFeatureLabel,
} from "../utils/planFeatureHelpers";
import {
  consumePendingAndGoCustomSetup,
  shouldRedirectToCustomSetupAfterUpgrade,
} from "../utils/customSetupFlow";
import {
  filterBlockerKeysForTarget,
  isUpgradeToTarget,
} from "../utils/paidPlanDowngradeBlockers";

const SinglePlan = ({
  planKey,
  planName,
  price,
  priceDisplay,
  billing,
  originalPrice,
  limitedTimeOffer = false,
  offerOriginalPrice,
  countryOffer = null,
  features,
  recommended,
  savings,
  country = "United States",
  countryCode = "US",
  rates = {},
  downgradeBlocked = false,
  blockerKeys = [],
  currentPlanKey,
  currentPlanPrice,
}) => {
  // COD Form orders per month of this plan (plans.cod_form_orders), for stores with the COD Form.
  const codFormBootstrap = useCodFormBootstrap();
  const planFormOrders =
    codFormBootstrap && codFormBootstrap.moduleEnabled
      ? (codFormBootstrap.planFormOrders || {})[planKey]
      : null;
  const hasFormOrders =
    planFormOrders !== null && planFormOrders !== undefined && planFormOrders !== "";
  const shopify = useAppBridge();
  const {
    shop: [shop, setShop],
    plan: [plan, setPlan],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [, setTab],
  } = useContext(StoreContext);
  const [loading, setLoading] = useState(false);
  // Features the merchant has switched on are listed first, then the rest.
  const { sort: sortFeatures } = usePlanFeatureOrder(setting);
  const formOrdersLine = !hasFormOrders
    ? null
    : isUnlimitedFormOrders(planFormOrders)
    ? I18n.t("plans.cod_form_orders_unlimited", { defaultValue: "Unlimited COD Form orders" })
    : I18n.t("plans.cod_form_orders", {
        count: Number(planFormOrders).toLocaleString(),
        defaultValue: "Up to %{count} COD Form orders per month",
      })
;
  const orderedFeatures = sortFeatures(
    formOrdersLine &&
      !(features || []).some((feature) => planFeatureLabel(feature) === formOrdersLine)
      ? [{ text: formOrdersLine, bold: true, topic: "cod_form", pin: true }].concat(features || [])
      : features || [],
  );
  const [showDowngradeBlockedModal, setShowDowngradeBlockedModal] =
    useState(false);
  const [showCancelConfirmModal, setShowCancelConfirmModal] = useState(false);
  // Server-side error (e.g. a 422 downgrade block) to surface to the merchant.
  const [upgradeError, setUpgradeError] = useState(null);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);
  const isCurrentPlan = plan.name === planKey && shop.charge_id;

  const relevantBlockerKeys = filterBlockerKeysForTarget(blockerKeys, planKey);
  const isUpgrade = isUpgradeToTarget({
    currentPlanKey: currentPlanKey || plan?.name,
    currentPlanPrice,
    targetPlanKey: planKey,
    targetPrice: price,
  });
  const isDowngradeBlockedForTarget =
    downgradeBlocked && !isUpgrade && relevantBlockerKeys.length > 0;

  const getButtonText = () => {
    if (isCurrentPlan) {
      return I18n.t("plans.cancel_plan");
    }
    if (price === 0) return I18n.t("plans.get_started_free");
    return recommended
      ? I18n.t("plans.choose_pro_plan")
      : I18n.t("plans.choose_plan", { planName });
  };

  const handlePlanSelection = () => {
    if (isDowngradeBlockedForTarget && !isCurrentPlan) {
      setShowDowngradeBlockedModal(true);
      return;
    }
    // Track plan selection
    journeyTracker.trackButtonClick("plan_selected", {
      step: 3,
      feature: "billing",
      planKey: planKey,
      planName: planName,
      price: price,
      priceDisplay: priceDisplay,
      recommended: recommended,
      country: country,
      countryCode: countryCode,
      isCurrentPlan: isCurrentPlan,
      action: isCurrentPlan ? "cancel" : "upgrade",
    });

    // Handle plan selection logic here
    console.log(`Selected ${planName} plan for ${country}`, {
      planKey,
      price,
      country,
      countryCode,
      rates,
    });

    if (isCurrentPlan) {
      setShowCancelConfirmModal(true);
    } else {
      handleUpgrade();
    }
  };

  const handleUpgrade = () => {
    setLoading(true);
    Api.post("/plans/upgrade", {
      name: planKey,
      orders: 1000,
    })
      .then((response) => {
        // Track successful upgrade
        journeyTracker.trackButtonClick("plan_upgrade_success", {
          step: 3,
          feature: "billing",
          planKey: planKey,
          planName: planName,
          confirmationUrl: response.data.confirmationUrl,
        });

        // App Bridge v4: Use window.open with "_top" for external redirects
        if (response.data.confirmationUrl) {
          window.open(response.data.confirmationUrl, "_top");
        } else if (
          shouldRedirectToCustomSetupAfterUpgrade(response.data.confirmationUrl)
        ) {
          consumePendingAndGoCustomSetup();
        }
      })
      .catch((error) => {
        // Track upgrade error
        journeyTracker.trackError("plan_upgrade_error", error.message, {
          step: 3,
          feature: "billing",
          planKey: planKey,
          planName: planName,
        });
        console.error("Plan upgrade failed:", error);
        setUpgradeError(
          error?.response?.data?.error ||
            error?.response?.data?.message ||
            "Couldn't change your plan. Please try again.",
        );
      })
      .finally(() => {
        setLoading(false);
      });
  };

  const handleCancel = () => {
    setLoading(true);
    Api.post("/plans/cancel", { name: planKey })
      .then((response) => {
        // Track successful cancellation
        journeyTracker.trackButtonClick("plan_cancel_success", {
          step: 3,
          feature: "billing",
          planKey: planKey,
          planName: planName,
        });

        setPlan(response.data);
        setShop({ ...shop, charge_id: '' });
        setSetting({ ...setting });
        setOriginalSetting({ ...setting });
        setTab(0);
      })
      .catch((error) => {
        // Track cancellation error
        journeyTracker.trackError("plan_cancel_error", error.message, {
          step: 3,
          feature: "billing",
          planKey: planKey,
          planName: planName,
        });
        console.error("Plan cancellation failed:", error);
        setUpgradeError(
          error?.response?.data?.error ||
            error?.response?.data?.message ||
            "Couldn't cancel your plan. Please try again.",
        );
      })
      .finally(() => {
        setLoading(false);
      });
  };

  return (
    <Card>
      <BlockStack gap="400">
        <Modal
          open={!!upgradeError}
          onClose={() => setUpgradeError(null)}
          title={I18n.t("plans.change_failed_title", { defaultValue: "Couldn't change plan" })}
          primaryAction={{
            content: I18n.t("admin.ok", { defaultValue: "OK" }),
            onAction: () => setUpgradeError(null),
          }}
        >
          <Modal.Section>
            <Text as="p" variant="bodyMd">
              {upgradeError}
            </Text>
          </Modal.Section>
        </Modal>

        <Modal
          open={showDowngradeBlockedModal}
          onClose={() => setShowDowngradeBlockedModal(false)}
          title={I18n.t("plans.downgrade_blockers.banner_title")}
          primaryAction={{
            content: I18n.t("admin.ok", { defaultValue: "OK" }),
            onAction: () => setShowDowngradeBlockedModal(false),
          }}
        >
          <Modal.Section>
            <BlockStack gap="200">
              <Text as="p" variant="bodyMd">
                {I18n.t("plans.downgrade_blockers.banner_body")}
              </Text>
              <List type="bullet">
                {relevantBlockerKeys.map((key) => (
                  <List.Item key={key}>
                    {I18n.t(`plans.downgrade_blockers.features.${key}`)}
                  </List.Item>
                ))}
              </List>
            </BlockStack>
          </Modal.Section>
        </Modal>

        <Modal
          open={showCancelConfirmModal}
          onClose={() => setShowCancelConfirmModal(false)}
          title={I18n.t("single_plan.cancel_plan")}
          primaryAction={{
            content: I18n.t("single_plan.cancel_plan"),
            destructive: true,
            loading,
            onAction: () => {
              setShowCancelConfirmModal(false);
              handleCancel();
            },
          }}
          secondaryActions={[
            {
              content: I18n.t("admin.back", { defaultValue: "Back" }),
              onAction: () => setShowCancelConfirmModal(false),
            },
          ]}
        >
          <Modal.Section>
            <BlockStack gap="200">
              <Text as="p" variant="bodyMd">
                {I18n.t("single_plan.your_features_may_stop_functioning_after")}
              </Text>
              {downgradeBlocked && (blockerKeys || []).length > 0 && (
                <>
                  <Text as="p" variant="bodyMd" tone="subdued">
                    {I18n.t("single_plan.you_are_currently_using")}
                  </Text>
                  <List type="bullet">
                    {(blockerKeys || []).map((key) => (
                      <List.Item key={key}>
                        {I18n.t(`plans.downgrade_blockers.features.${key}`)}
                      </List.Item>
                    ))}
                  </List>
                </>
              )}
            </BlockStack>
          </Modal.Section>
        </Modal>

        {/* Plan Header */}
        <BlockStack gap="200">
          <InlineStack align="space-between" blockAlign="start">
            <Text variant="headingMd" as="h3">
              {planName}
            </Text>
            <InlineStack gap="200">
              {isCurrentPlan && (
                <Badge status="info" size="small">
                  {I18n.t("plans.current_plan")}
                </Badge>
              )}
              {recommended && !isCurrentPlan && (
                <Badge status="success" size="small">
                  {I18n.t("plans.most_popular")}
                </Badge>
              )}
            </InlineStack>
          </InlineStack>

          {/* Pricing */}
          <BlockStack gap="100">
            {countryOffer && (
              <InlineStack gap="200" blockAlign="center">
                <Badge tone="success">
                  {countryOffer.badge ||
                    (countryOffer.trial_days
                      ? I18n.t("single_plan.offer_free_days", { days: countryOffer.trial_days })
                      : I18n.t("single_plan.limited_time_offer"))}
                </Badge>
                {countryOffer.slots_left != null && (
                  <Text variant="bodySm" tone="subdued">
                    {I18n.t("single_plan.offer_slots_left", { count: countryOffer.slots_left })}
                  </Text>
                )}
              </InlineStack>
            )}
            {limitedTimeOffer && (
              <InlineStack gap="200" blockAlign="center">
                <Badge tone="success">{I18n.t("single_plan.limited_time_offer")}</Badge>
                {offerOriginalPrice && (
                  <Text
                    variant="bodyMd"
                    tone="subdued"
                    textDecorationLine="line-through"
                  >
                    {offerOriginalPrice}
                  </Text>
                )}
              </InlineStack>
            )}
            <InlineStack gap="200" blockAlign="baseline">
              <Text variant="headingLg" as="h4">
                {priceDisplay}
              </Text>
              {originalPrice && (
                <Text
                  variant="bodyMd"
                  tone="subdued"
                  textDecorationLine="line-through"
                >
                  {originalPrice}
                </Text>
              )}
            </InlineStack>
            <Text variant="bodySm" tone="subdued">
              {countryOffer && countryOffer.trial_days
                ? `${I18n.t("single_plan.offer_free_days", { days: countryOffer.trial_days })} · ${I18n.t("single_plan.offer_then_price", { price: priceDisplay })}`
                : billing}
            </Text>
            {savings && (
              <Text variant="bodySm" tone="success">
                {savings}
              </Text>
            )}
          </BlockStack>
        </BlockStack>

        {/* CTA Button */}
        <Button
          variant={isCurrentPlan ? "primary" : recommended ? "primary" : "secondary"}
          tone={isCurrentPlan ? "critical" : undefined}
          size="large"
          fullWidth
          loading={loading}
          disabled={loading}
          onClick={handlePlanSelection}
        >
          {getButtonText()}
        </Button>

        {/* Features List */}
        <BlockStack gap="200">
          <Text variant="bodyMd" fontWeight="medium">
            {I18n.t("plans.whats_included")}
          </Text>
          <List>
            {orderedFeatures.slice(0, 8).map((feature, index) => (
              <List.Item key={index}>
                <Text
                  variant="bodySm"
                  fontWeight={planFeatureFontWeight(feature)}
                >
                  {planFeatureLabel(feature)}
                </Text>
              </List.Item>
            ))}
          </List>
          {orderedFeatures.length > 8 && (
            <details>
              <summary style={{ cursor: "pointer", marginTop: "8px" }}>
                <Text variant="bodySm" tone="subdued">
                  {I18n.t("plans.more_features", {
                    count: orderedFeatures.length - 8,
                  })}
                </Text>
              </summary>
              <List>
                {orderedFeatures.slice(8).map((feature, index) => (
                  <List.Item key={index + 8}>
                    <Text
                      variant="bodySm"
                      fontWeight={
                        planFeatureFontWeight(feature) ?? "medium"
                      }
                    >
                      {planFeatureLabel(feature)}
                    </Text>
                  </List.Item>
                ))}
              </List>
            </details>
          )}
        </BlockStack>

        {/* Rate Summary Card (if rates available) */}
        {rates && Object.keys(rates).length > 0 && (
          <Card background="bg-surface-secondary">
            <BlockStack gap="200">
              <Text variant="bodyMd" fontWeight="medium">
                {I18n.t("plans.rate_summary")}
              </Text>
              <BlockStack gap="100">
                {rates.sms && (
                  <InlineStack align="space-between">
                    <Text variant="bodySm">{I18n.t("plans.sms_rate")}</Text>
                    <Text variant="bodySm" fontWeight="medium">
                      {I18n.t("single_plan.price_per_message", {
                        price: rates.sms.toFixed(3),
                      })}
                    </Text>
                  </InlineStack>
                )}
                {[
                  ["whatsappUtility", "plans.whatsapp_utility_rate", "WhatsApp Utility"],
                  ["whatsappMarketing", "plans.whatsapp_marketing_rate", "WhatsApp Marketing"],
                  ["bspWhatsapp", "plans.bsp_whatsapp_rate", "WhatsApp (own number)"],
                ].map(([key, i18nKey, fallback]) =>
                  rates[key] ? (
                    <InlineStack key={key} align="space-between">
                      <Text variant="bodySm">{I18n.t(i18nKey, { defaultValue: fallback })}</Text>
                      <Text variant="bodySm" fontWeight="medium">
                        {I18n.t("single_plan.price_per_message", {
                          price: rates[key].toFixed(3),
                        })}
                      </Text>
                    </InlineStack>
                  ) : null
                )}
                {rates.whatsapp && (
                  <InlineStack align="space-between">
                    <Text variant="bodySm">
                      {I18n.t("plans.whatsapp_rate")}
                    </Text>
                    <Text variant="bodySm" fontWeight="medium">
                      {I18n.t("single_plan.price_per_message", {
                        price: rates.whatsapp.toFixed(3),
                      })}
                    </Text>
                  </InlineStack>
                )}
                {/* {rates.transactionFee && (
                  <InlineStack align="space-between">
                    <Text variant="bodySm">Transaction Fee:</Text>
                    <Text variant="bodySm" fontWeight="medium">
                      {rates.transactionFee}%
                    </Text>
                  </InlineStack>
                )} */}
              </BlockStack>
            </BlockStack>
          </Card>
        )}

        {/* Additional Info */}
        {price === 0 && (
          <Text variant="bodySm" tone="subdued" alignment="center">
            {I18n.t("plans.no_credit_card_required")}
          </Text>
        )}

        {/* Country-specific note */}
        <Text variant="caption" tone="subdued" alignment="center">
          {I18n.t("plans.pricing_optimized_for", { country })}
        </Text>
      </BlockStack>
    </Card>
  );
};

export default SinglePlan;

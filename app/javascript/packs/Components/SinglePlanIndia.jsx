// SinglePlanIndia.js
import React, { useState, useContext } from "react";
import { useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../Context/Store";
import {
  Button,
  Badge,
  Text,
  InlineStack,
  BlockStack,
  Card,
  List,
  Divider,
  Modal,
} from "@shopify/polaris";
import Api from "../Services/Api";
// 1. Remove legacy Redirect import: import { Redirect } from "@shopify/app-bridge/actions";
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

const SinglePlanIndia = ({
  features,
  planName,
  planKey,
  price,
  priceDisplay,
  usdDisplay,
  billing,
  originalPrice,
  limitedTimeOffer = false,
  offerOriginalPrice,
  recommended,
  savings,
  downgradeBlocked = false,
  blockerKeys = [],
  currentPlanKey,
  currentPlanPrice,
  messageRates,
  messageRatesNote,
  partialPaymentRate,
  partialPaymentCompareLabel,
  formOrders: formOrdersProp = null,
  messageRatesCompareLabel,
  messageRatesFirst = false,
  highlightFeature,
  badgeLabel,
  badgeTone = "success",
  upsellNote,
  countryOffer = null,
}) => {
  // COD Form orders per month of this plan (plans.cod_form_orders), for stores with the COD Form.
  const codFormBootstrap = useCodFormBootstrap();
  const planFormOrders =
    codFormBootstrap && codFormBootstrap.moduleEnabled
      ? (codFormBootstrap.planFormOrders || {})[planKey]
      : null;
  const formOrders =
    formOrdersProp !== null && formOrdersProp !== undefined
      ? formOrdersProp
      : planFormOrders === undefined || planFormOrders === "" ? null : planFormOrders;
  const shopify = useAppBridge();
  const [loading, setLoading] = useState(false);
  const [showDowngradeBlockedModal, setShowDowngradeBlockedModal] =
    useState(false);
  const [showCancelConfirmModal, setShowCancelConfirmModal] = useState(false);
  const [featuresExpanded, setFeaturesExpanded] = useState(false);
  // Server-side error (e.g. a 422 downgrade block) to surface to the merchant.
  const [upgradeError, setUpgradeError] = useState(null);
  const {
    shop: [shop, setShop],
    plan: [plan, setPlan],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [, setTab],
  } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  const relevantBlockerKeys = filterBlockerKeysForTarget(blockerKeys, planKey);
  const isUpgrade = isUpgradeToTarget({
    currentPlanKey: currentPlanKey || plan?.name,
    currentPlanPrice,
    targetPlanKey: planKey,
    targetPrice: price,
  });
  const isDowngradeBlockedForTarget =
    downgradeBlocked && !isUpgrade && relevantBlockerKeys.length > 0;

  const isCurrentPlan = plan.name === planKey && shop.charge_id;
  // Trial from a country offer; not shown on the plan the store is already on.
  const showTrial = !!(countryOffer && countryOffer.trial_days) && !isCurrentPlan;
  const isFreePlan = planKey === "Free" || Number(price) === 0;

  const handlePlanAction = () => {
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
      priceDisplay: priceDisplay,
      recommended: recommended,
      country: "India",
      countryCode: "IN",
      isCurrentPlan: isCurrentPlan,
      action: isCurrentPlan ? "cancel" : "upgrade",
    });

    if (isCurrentPlan) {
      setShowCancelConfirmModal(true);
    } else {
      handleUpgrade();
    }
  };

  /**
   * REFACTORED: REMOTE REDIRECT (App Bridge v4)
   * In v4, use window.open(url, "_top") for external redirects 
   * like subscription confirmation URLs.
   */
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
          country: "India",
          confirmationUrl: response.data.confirmationUrl,
        });

        // App Bridge v4 standard for top-level navigation
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
          country: "India",
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

  /**
   * REFACTORED: INTERNAL NAVIGATION (App Bridge v4)
   * Use History API + popstate to update internal state.
   */
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
          country: "India",
        });

        setPlan(response.data);
        setShop({ ...shop, charge_id: "" });
        setSetting({ ...setting });
        setOriginalSetting({ ...setting });

        // Update URL and trigger internal view swap
        window.history.pushState({}, '', '/');
        window.dispatchEvent(new PopStateEvent('popstate'));
        
        if (typeof setTab === 'function') {
          setTab(0);
        }
      })
      .catch((error) => {
        journeyTracker.trackError("plan_cancel_error", error.message, {
          step: 3,
          feature: "billing",
          planKey: planKey,
          planName: planName,
          country: "India",
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

  const getButtonText = () => {
    if (isCurrentPlan) {
      return I18n.t("plans_india.cancel_plan");
    }

    switch (planKey) {
      case "Free":
        return I18n.t("plans_india.get_started");
      case "Pro":
        return I18n.t("plans_india.choose_pro");
      case "Enterprise":
      case "india_budget":
        return I18n.t("plans_india.choose_enterprise");
      case "Enterprise Plus":
        return I18n.t("plans_india.choose_enterprise_plus");
      default:
        return I18n.t("plans_india.select_plan");
    }
  };

  const getButtonVariant = () => {
    if (isCurrentPlan) {
      return "secondary";
    }
    return recommended ? "primary" : "secondary";
  };

  const isZeroPartialFee = partialPaymentRate === "0%";

  const FEATURES_COLLAPSE_THRESHOLD = 4;
  // Features the merchant has switched on are listed first, then the rest.
  const { topics: onTopics, sort: sortFeatures } = usePlanFeatureOrder(setting);
  const orderedFeatures = sortFeatures(features);
  const hasMoreFeatures = orderedFeatures.length > FEATURES_COLLAPSE_THRESHOLD;
  const visibleFeatures =
    featuresExpanded || !hasMoreFeatures
      ? orderedFeatures
      : orderedFeatures.slice(0, FEATURES_COLLAPSE_THRESHOLD);
  const hiddenFeatureCount = orderedFeatures.length - FEATURES_COLLAPSE_THRESHOLD;

  const formOrdersSection = formOrders !== null && formOrders !== undefined && (
    <>
      <Divider />
      <BlockStack gap="150">
        <Text variant="headingSm" as="h4">
          {I18n.t("plans_india.cod_form_orders_title", { defaultValue: "COD Form" })}
        </Text>
        <InlineStack align="space-between" blockAlign="center" wrap={false}>
          <Text variant="bodyMd">
            {I18n.t("plans_india.cod_form_orders_label", { defaultValue: "Form orders per month" })}
          </Text>
          <Text variant="headingSm" as="span">
            {isUnlimitedFormOrders(formOrders)
              ? I18n.t("plans.unlimited", { defaultValue: "Unlimited" })
              : Number(formOrders).toLocaleString()}
          </Text>
        </InlineStack>
      </BlockStack>
    </>
  );

  const partialPaymentSection = partialPaymentRate && (
    <>
      <Divider />
      <BlockStack gap="150">
        <Text variant="headingSm" as="h4">
          {I18n.t("plans_india.partial_payment_fee_title")}
        </Text>
        <InlineStack align="space-between" blockAlign="center" wrap={false}>
          <Text variant="bodyMd">
            {I18n.t("plans_india.partial_payment_fee_label")}
          </Text>
          <Text
            variant="headingSm"
            as="span"
            tone={isZeroPartialFee ? "success" : undefined}
          >
            {partialPaymentRate}
          </Text>
        </InlineStack>
        {partialPaymentCompareLabel && (
          <Text variant="bodySm" tone="subdued">
            {partialPaymentCompareLabel}
          </Text>
        )}
      </BlockStack>
    </>
  );

  const messageRatesSection = (messageRates || messageRatesNote) && (
    <>
      <Divider />
      <BlockStack gap="150">
        <Text variant="headingSm" as="h4">
          {I18n.t("plans_india.message_rates_title")}
        </Text>
        {messageRates ? (
          messageRates.map((rate) => (
            <InlineStack
              key={rate.key}
              align="space-between"
              blockAlign="center"
              wrap={false}
            >
              <Text variant="bodyMd">{rate.label}</Text>
              <Text variant="bodyMd" fontWeight="semibold">
                {rate.value}
              </Text>
            </InlineStack>
          ))
        ) : (
          <Text variant="bodySm" tone="subdued">
            {messageRatesNote}
          </Text>
        )}
        {messageRates && (
          <Text variant="bodySm" tone="subdued">
            {I18n.t("plans_india.message_rate_per_message")}
          </Text>
        )}
        {messageRatesCompareLabel && (
          <Text variant="bodySm" tone="subdued">
            {messageRatesCompareLabel}
          </Text>
        )}
      </BlockStack>
    </>
  );

  // Rate / limit blocks: the ones for switched-on features first, the usual order otherwise.
  const ratesBlock = {
    id: "rates",
    node: messageRatesSection,
    on: onTopics.sms || onTopics.whatsapp,
  };
  const partialBlock = { id: "partial", node: partialPaymentSection, on: onTopics.partial };
  const formBlock = { id: "form", node: formOrdersSection, on: onTopics.cod_form };
  const baseSections = (
    messageRatesFirst ? [ratesBlock, partialBlock] : [partialBlock, ratesBlock]
  ).concat(formBlock);
  const orderedSections = baseSections
    .filter((section) => section.on)
    .concat(baseSections.filter((section) => !section.on));

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
          title={I18n.t("single_plan_india.cancel_plan")}
          primaryAction={{
            content: I18n.t("single_plan_india.cancel_plan"),
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
                {I18n.t("single_plan_india.your_paid_features_may_stop_functioning")}
              </Text>
              {downgradeBlocked && (blockerKeys || []).length > 0 && (
                <>
                  <Text as="p" variant="bodyMd" tone="subdued">
                    {I18n.t("single_plan_india.you_are_currently_using")}
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
        {recommended && (
          <Badge tone="success">{I18n.t("plans_india.most_popular")}</Badge>
        )}
        {!recommended && badgeLabel && (
          <Badge tone={badgeTone}>{badgeLabel}</Badge>
        )}

        <BlockStack gap="200">
          <Text variant="headingMd" as="h3">
            {planName}
          </Text>

          {showTrial && (
            <InlineStack gap="200" blockAlign="center">
              <Badge tone="success">
                {countryOffer.badge ||
                  I18n.t("single_plan.offer_free_days", { days: countryOffer.trial_days })}
              </Badge>
              {countryOffer.slots_left != null && (
                <Text variant="bodySm" tone="subdued">
                  {I18n.t("single_plan.offer_slots_left", { count: countryOffer.slots_left })}
                </Text>
              )}
            </InlineStack>
          )}

          {limitedTimeOffer ? (
            <InlineStack gap="200" blockAlign="center">
              <Badge tone="success">{I18n.t("single_plan_india.limited_time_offer")}</Badge>
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
          ) : (
            originalPrice && (
              <InlineStack gap="200" blockAlign="center">
                <Text
                  variant="bodyMd"
                  tone="subdued"
                  textDecorationLine="line-through"
                >
                  {originalPrice}
                </Text>
                {savings && <Badge>{savings}</Badge>}
              </InlineStack>
            )
          )}

          <InlineStack gap="200" blockAlign="baseline">
            <Text variant="displayMd" fontWeight="bold">
              {priceDisplay}
            </Text>
            <Text variant="bodyMd" tone="subdued">
              {billing}
            </Text>
          </InlineStack>
          {usdDisplay && (
            <Text variant="bodySm" tone="subdued">
              {usdDisplay}
            </Text>
          )}
          {showTrial && (
            <Text variant="bodySm" fontWeight="semibold" tone="success">
              {`${I18n.t("single_plan.offer_free_days", { days: countryOffer.trial_days })} · ${I18n.t("single_plan.offer_then_price", { price: priceDisplay })}`}
            </Text>
          )}
          {highlightFeature && (
            <Text variant="bodySm" fontWeight="semibold" tone="success">
              {highlightFeature}
            </Text>
          )}
        </BlockStack>

        <Button
          variant={isCurrentPlan ? "secondary" : getButtonVariant()}
          tone={isCurrentPlan ? "critical" : undefined}
          size="large"
          fullWidth
          loading={loading}
          disabled={loading}
          onClick={handlePlanAction}
        >
          {getButtonText()}
        </Button>

        {!isFreePlan && !isCurrentPlan && (
          <Text variant="bodySm" tone="subdued" alignment="center">
            {I18n.t("plans_india.cancel_anytime_reassurance")}
          </Text>
        )}

        {orderedSections.map((section) => (
          <React.Fragment key={section.id}>{section.node}</React.Fragment>
        ))}

        <Divider />

        <BlockStack gap="300">
          <Text variant="headingSm" as="h4">
            {I18n.t("plans_india.whats_included")}
          </Text>
          <List>
            {visibleFeatures.map((feature, index) => (
              <List.Item key={index}>
                <Text fontWeight={planFeatureFontWeight(feature)}>
                  {planFeatureLabel(feature)}
                </Text>
              </List.Item>
            ))}
          </List>
          {hasMoreFeatures && (
            <Button
              variant="plain"
              onClick={() => setFeaturesExpanded((expanded) => !expanded)}
            >
              {featuresExpanded
                ? I18n.t("plans_india.show_less_features")
                : I18n.t("plans_india.show_more_features", {
                    count: hiddenFeatureCount,
                  })}
            </Button>
          )}
        </BlockStack>

        {upsellNote && (
          <Text variant="bodySm" tone="subdued">
            {upsellNote}
          </Text>
        )}

     </BlockStack>
    </Card>
  );
};

export default SinglePlanIndia;
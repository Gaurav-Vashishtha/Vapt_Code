import React, { useContext, useEffect, useState } from "react";
import { InlineGrid, Page } from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import Api from "../Services/Api";
// Removed: import { Redirect } from "@shopify/app-bridge/actions"; // App Bridge v4 - use window.open instead
import QuickCurrentStep from "./QuickCurrentStep";
import SinglePlan from "./SinglePlan";
import { navigateTo } from "../../utils/navigate";
import I18n from "../i18n-lang";
import CodKingFooter from "../../utils/codkingFooter";
import PlansIndia from "./PlansIndia";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";

export default function SubscriptionPlans() {
  const {
    shop: [shop, setShop],
    plan: [, setPlan],
    setting: [setting, setSetting],
  } = useContext(StoreContext);

  /**
   * App Bridge v4 Navigation Interceptor
   * Prevents full page reload and syncs with Shopify Admin
   */
  const handleRedirect = (e, path) => {
    if (e) e.preventDefault();
    navigateTo(path);
  };

  const [loadingPlan, setLoadingPlan] = useState(null);
  const [navigationSource, setNavigationSource] = useState(null);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);

  const handlePlanSelect = async (planKey, maxOrders) => {
    setLoadingPlan(planKey);

    // Track plan selection
    journeyTracker.trackButtonClick("plan_selected", {
      planKey: planKey,
      maxOrders: maxOrders,
      step: 3,
    });

    try {
      const response = await Api.post("/plans/upgrade", {
        name: planKey,
        orders: maxOrders,
      });

      // Track successful plan upgrade initiation
      journeyTracker.trackStepCompletion("billing_completed", {
        planKey: planKey,
        maxOrders: maxOrders,
        confirmationUrl: response.data.confirmationUrl,
      });

      // App Bridge v4: Use window.open with "_top" for external redirects
      if (response.data.confirmationUrl) {
        window.open(response.data.confirmationUrl, "_top");
      }
    } catch (error) {
      // Track plan selection error
      journeyTracker.trackError("plan_selection_error", error.message, {
        planKey: planKey,
        maxOrders: maxOrders,
      });
    } finally {
      setLoadingPlan(null);
      setPlan("");
      setShop({ ...shop, charge_id: "" });
    }
  };

  const allPlans = [
    {
      name: I18n.t("quick_onboarding_billing.plan_name_free"),
      planKey: "Free",
      planName: I18n.t("quick_onboarding_billing.plan_name_free"),
      price: "0",
      maxOrders: 0,
      features: [
        I18n.t("quick_onboarding_billing.feature_otp_verification"),
        I18n.t("quick_onboarding_billing.feature_abandoned_cart"),
        {
          text: I18n.t("quick_onboarding_billing.partial_payment_free"),
          bold: true,
        },
        I18n.t("quick_onboarding_billing.feature_order_alerts"),
        I18n.t("quick_onboarding_billing.feature_unlimited_orders"),
        I18n.t("quick_onboarding_billing.feature_1_1_setup"),
      ],
    },
    {
      name: I18n.t("quick_onboarding_billing.plan_name_pro"),
      planKey: "Pro",
      planName: I18n.t("quick_onboarding_billing.plan_name_pro"),
      price: "7.99",
      recommended: true,
      maxOrders: 560,
      features: [
        I18n.t("quick_onboarding_billing.feature_all_free"),
        {
          text: I18n.t("quick_onboarding_billing.feature_discount_15"),
          bold: true,
        },
        {
          text: I18n.t("quick_onboarding_billing.partial_payment_pro"),
          bold: true,
        },
        I18n.t("quick_onboarding_billing.feature_cod_fee"),
        I18n.t("quick_onboarding_billing.feature_cod_rules"),
        I18n.t("quick_onboarding_billing.feature_priority_support"),
      ],
    },
    {
      name: I18n.t("quick_onboarding_billing.plan_name_enterprise"),
      planKey: "Enterprise",
      planName: I18n.t("quick_onboarding_billing.plan_name_enterprise"),
      price: "39",
      maxOrders: -1,
      features: [
        I18n.t("quick_onboarding_billing.feature_all_pro"),
        {
          text: I18n.t("quick_onboarding_billing.feature_discount_35"),
          bold: true,
        },
        {
          text: I18n.t("quick_onboarding_billing.partial_payment_enterprise"),
          bold: true,
        },
        I18n.t("quick_onboarding_billing.feature_branded_sms"),
        I18n.t("quick_onboarding_billing.feature_local_gateway"),
        I18n.t("quick_onboarding_billing.feature_dedicated_manager"),
      ],
    },
  ];

  // Filter out free plan for specific onboarding flows
  const plans =
    navigationSource === "onboarding-codfees" ||
    navigationSource === "onboarding-codshowhide"
      ? allPlans.filter(
          (plan) =>
            plan.name !== I18n.t("quick_onboarding_billing.plan_name_free")
        )
      : allPlans;

  useEffect(() => {
    // Parse URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    const from = urlParams.get("from");

    if (from) {
      setNavigationSource(from);
      console.log("Navigation source:", from);
    }
    if (window.analytics) {
      window.analytics.track("billing_page_viewed", {
        source: from,
        timestamp: new Date().toISOString(),
      });
    }

    // Track page load
    journeyTracker.trackPageLoad({
      step: 3,
      navigationSource: from,
      availablePlans: allPlans.map((plan) => plan.planKey),
    });
  }, []);

  const getFallbackPath = () => {
    switch (navigationSource) {
      case "onboarding-notifications":
        return "/quick-onboarding/notifications";
      case "onboarding-partial-payment":
        return "/quick-onboarding/partial-payment";
      case "onboarding-codfees":
        return "/quick-onboarding/fees";
      case "onboarding-codshowhide":
        return "/quick-onboarding/limit-cod";
      case "onboarding-otp-pre":
        return "/quick-onboarding/otp/pre-order";
      case "onboarding-otp-post":
        return "/quick-onboarding/otp/post-order";
      default:
        return "/quick-onboarding";
    }
  };

  return (
    <Page
      compactTitle
      backAction={{
        content: I18n.t("quick_onboarding_billing.back_to_onboarding"),
        onAction: () => {
          journeyTracker.trackButtonClick("back_to_onboarding", {
            fromStep: 3,
            toStep: 2,
            navigationSource: navigationSource,
          });

          // Always navigate to quick-onboarding explicitly so we land on the wizard
          // instead of history.back() which can land on "/" and cause a blank screen.
          handleRedirect(null, getFallbackPath());
        },
      }}
      title={I18n.t("quick_onboarding_billing.choose_best_plan")}
      subtitle={I18n.t("quick_onboarding_billing.free_vs_pro")}
      secondaryActions={[
        {
          content: I18n.t("quick_onboarding_billing.view_message_pricing"),
          url: "https://notifiktech.com/message-pricing",
          external: true,
        },
      ]}
    >
      <QuickCurrentStep currentStep={3} />
      <br />
      {shop.country_code === "IN" ? (
        <PlansIndia isOnboardingFlow={true} />
      ) : (
        <InlineGrid columns={{ xs: 1, sm: 2, lg: 3 }} gap="500">
          {plans.map((plan) => (
            <SinglePlan key={plan.planKey} {...plan} />
          ))}
        </InlineGrid>
      )}
      <CodKingFooter />
    </Page>
  );
}

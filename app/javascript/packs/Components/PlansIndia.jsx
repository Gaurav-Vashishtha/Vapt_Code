import React, { useContext, useState, useEffect } from "react";
import {
  Page,
  Layout,
  BlockStack,
  InlineStack,
  Text,
  Card,
  InlineGrid,
  Badge,
  Button,
  Banner,
  List,
  Spinner,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import SinglePlanIndia from "./SinglePlanIndia";
import PlansIndiaV3 from "./PlansIndiaV3";
import CountrySelector from "./CountrySelector";
import Plans from "./Plans"; // Import the international Plans component

import { navigateTo } from "../../utils/navigate";
import CodKingFooter from "../../utils/codkingFooter";
import SinglePlan from "./SinglePlan";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import I18n from "../i18n-lang";
import Api from "../Services/Api";
import { usePaidPlanDowngradeGate } from "../Hooks/usePaidPlanDowngradeGate";
import OtpCampaignCouponCard from "./OtpCampaignCouponCard";

// Running country offers from /plans/india_pricing, keyed by plan name: { Pro: { trial_days, badge, slots_left } }.
const countryOffersByPlan = (data) => {
  const list = data?.countryOffers ?? data?.country_offers ?? [];
  return list.reduce((acc, o) => {
    const name = o.planName ?? o.plan_name;
    if (name) {
      acc[name] = {
        trial_days: o.trialDays ?? o.trial_days ?? null,
        badge: o.badge ?? null,
        slots_left: o.slotsLeft ?? o.slots_left ?? null,
      };
    }
    return acc;
  }, {});
};

const PlansIndiaLegacy = ({ isOnboardingFlow, shop }) => {
  const [onBoardingFlow, SetOnBoardingFlow] = useState(!!isOnboardingFlow);
  const [selectedCountry, setSelectedCountry] = useState("IN");
  const [indiaPricing, setIndiaPricing] = useState(null);
  const [countryOffers, setCountryOffers] = useState({});

  const {
    isPrepaidEnabled,
    plan: [plan],
    setting: [setting, setSetting],
  } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);
  const { downgradeBlocked, blockerKeys } = usePaidPlanDowngradeGate();

  // Fetch dynamic India plan pricing from backend (reads shop + Shopify subscription)
  useEffect(() => {
    if (selectedCountry !== "IN") return;
    Api.get("/plans/india_pricing", { params: { fetch_shopify: true } })
      .then((res) => {
        const byKey = {};
        (res.data?.plans || []).forEach((p) => {
          const key = p.planKey || p.plan_key;
          if (key) byKey[key] = p;
        });
        setIndiaPricing(byKey);
        setCountryOffers(countryOffersByPlan(res.data));
      })
      .catch(() => setIndiaPricing({}));
  }, [selectedCountry]);

  /**
   * App Bridge v4 Navigation Handler
   * Syncs URL with Admin and updates internal state
   */
  const handleAppNavigation = (path) => {
    navigateTo(path);
  };

  // Handle country change (redirect to international plans if not India)
  const handleCountryChange = (countryCode) => {
    journeyTracker.trackButtonClick("country_change", {
      step: 3,
      feature: "billing",
      fromCountry: selectedCountry,
      toCountry: countryCode,
      isOnboardingFlow: isOnboardingFlow,
    });
    setSelectedCountry(countryCode);
  };

  // Track page load
  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: 3,
      feature: "billing",
      page: "plans-india",
      selectedCountry: selectedCountry,
      isOnboardingFlow: isOnboardingFlow,
      availablePlans: ["Free", "Pro", "Enterprise", "Enterprise Plus"],
    });
    // Funnel stage: subscription page reached (onboarding billing only).
    if (window.location.pathname.includes("/quick-onboarding")) {
      journeyTracker.trackEvent("subscription_page_viewed", {
        step: 6,
        page: "plans-india",
      });
    }
  }, []);

  if (selectedCountry !== "IN") {
    return (
      <Plans
        isOnboardingFlow={isOnboardingFlow}
        shop={{ country_code: selectedCountry }}
      />
    );
  }

  const currentPlanKey = plan?.name;
  const pricingByKey = indiaPricing || {};
  const proPricing = pricingByKey.Pro;
  const indiaBudgetPricing = pricingByKey.india_budget;
  const enterprisePlusPricing = pricingByKey["Enterprise Plus"];

  // API response is camelized: rupeesDisplay, usdDisplay, isGrandfathered
  const plans = [
    {
      planKey: "Free",
      planName: "Free",
      price: 0,
      priceDisplay: "₹0",
      billing: I18n.t("plans_india.forever"),
      features: [
        I18n.t("plans_india.otp_verification_sms_whatsapp"),
        { text: I18n.t("plans.persistent_signin_feature"), bold: true },
        { text: I18n.t("plans_india.competitive_sms_rates"), bold: true },
        { text: I18n.t("plans_india.whatsapp_business_messaging"), bold: true },
        I18n.t("plans_india.automated_order_confirmation"),
        I18n.t("plans.order_fulfillment_notifications"),
        I18n.t("plans.reliable_sms_gateway"),
        I18n.t("plans.abandoned_cart_recovery"),
        { text: I18n.t("plans_india.partial_payment_1_5_percent"), bold: true },
        I18n.t("plans.cod_to_prepaid_incentives"),
        I18n.t("plans_india.basic_support"),
      ],
      recommended: false,
    },
    {
      planKey: "Pro",
      planName: "Pro",
      price: proPricing?.rupees ?? 899,
      priceDisplay: proPricing?.rupeesDisplay ?? "₹899",
      usdDisplay: proPricing?.usdDisplay ?? "$9.99 USD",
      limitedTimeOffer: proPricing?.limitedTimeOffer ?? false,
      offerOriginalPrice: proPricing?.originalRupeesDisplay,
      billing: I18n.t("plans_india.per_month"),
      originalPrice: "₹1299",
      features: [
        I18n.t("plans.all_free_features"),
        { text: I18n.t("plans_india.premium_sms_rates"), bold: true },
        { text: I18n.t("plans_india.whatsapp_rates_pro"), bold: true },
        { text: I18n.t("plans_india.partial_payment_0_8_percent"), bold: true },
        I18n.t("plans_india.advanced_cod_eligibility"),
        I18n.t("plans.configurable_cod_fees"),
        I18n.t("plans.abandoned_cart_reminders"),
        I18n.t("plans.priority_support"),
        I18n.t("plans_india.realtime_verification_dashboard"),
        I18n.t("plans_india.auto_filled_shipping"),
        I18n.t("plans_india.payment_rules_customization_available"),
        I18n.t("plans_india.partial_payment_shipping_rate_keyword"),
      ],
      recommended: false,
      savings: I18n.t("plans_india.save_amount", { amount: 400 }),
    },
    {
      planKey: "india_budget",
      planName: "Enterprise",
      price: indiaBudgetPricing?.rupees ?? 1999,
      priceDisplay: indiaBudgetPricing?.rupeesDisplay ?? "₹1,999",
      usdDisplay: indiaBudgetPricing?.usdDisplay ?? "$21.99 USD",
      limitedTimeOffer: indiaBudgetPricing?.limitedTimeOffer ?? false,
      offerOriginalPrice: indiaBudgetPricing?.originalRupeesDisplay,
      billing: I18n.t("plans_india.per_month"),
      originalPrice: "₹3,499",
      features: [
        I18n.t("plans.all_pro_features"),
        { text: I18n.t("plans_india.enterprise_sms_rates"), bold: true },
        { text: I18n.t("plans_india.whatsapp_rates_enterprise"), bold: true },
        { text: I18n.t("plans.branded_whatsapp_paid_plans"), bold: true },
        I18n.t("plans.whatsapp_chat_widget"),
        { text: I18n.t("plans_india.partial_payment_0_5_percent"), bold: true },
        I18n.t("plans.exportable_data"),
        I18n.t("plans.branded_sms_sender"),
        I18n.t("plans.branded_whatsapp"),
        I18n.t("plans.advanced_analytics"),
        I18n.t("plans_india.dedicated_indian_account_manager"),
        I18n.t("plans.priority_routing"),
        I18n.t("plans.priority_technical_support"),
      ],
      recommended: true,
      savings: I18n.t("plans_india.save_amount", { amount: 1500 }),
    },
    {
      planKey: "Enterprise Plus",
      planName: "Enterprise Plus",
      price: enterprisePlusPricing?.rupees ?? 4999,
      priceDisplay: enterprisePlusPricing?.rupeesDisplay ?? "₹4,999",
      usdDisplay: enterprisePlusPricing?.usdDisplay ?? "$59 USD",
      limitedTimeOffer: enterprisePlusPricing?.limitedTimeOffer ?? false,
      offerOriginalPrice: enterprisePlusPricing?.originalRupeesDisplay,
      billing: I18n.t("plans_india.per_month"),
      originalPrice: null,
      features: [
        I18n.t("plans.all_enterprise_features"),
        { text: I18n.t("plans.branded_whatsapp_paid_plans"), bold: true },
        I18n.t("plans.remove_cod_king_branding"),
        I18n.t("plans.otp_verification_checkout_shopify_plus"),
        I18n.t("plans_india.dedicated_indian_account_manager"),
        I18n.t("plans.priority_routing"),
        I18n.t("plans.priority_technical_support"),
      ],
      recommended: false,
      savings: null,
    },
  ];

  const currentPlanPrice = plans.find((p) => p.planKey === currentPlanKey)?.price;

  if (onBoardingFlow) {
    return (
      <div>
        <Layout>
          <Layout.Section>
            <Card>
              <BlockStack gap="400">
                <InlineStack align="space-between" blockAlign="start">
                  <BlockStack gap="200">
                    <Text variant="headingMd" as="h2">
                      {I18n.t("plans_india.built_for_india")}
                    </Text>
                    <Text variant="bodyMd" as="p" tone="subdued">
                      {I18n.t("plans_india.dlt_compliance")}
                    </Text>
                  </BlockStack>

          <CountrySelector
          selectedCountry={selectedCountry}
          onCountryChange={handleCountryChange}
          labelHidden={true}
          placeholder={I18n.t("plans_india.search_countries")}
          useSelect
          />
                </InlineStack>

                <InlineStack gap="200" wrap>
                  <Badge>{I18n.t("plans_india.dlt_compliant")}</Badge>
                  <Badge>{I18n.t("plans_india.local_sms_gateway")}</Badge>
                  <Badge>{I18n.t("plans_india.inr_pricing")}</Badge>
                </InlineStack>
              </BlockStack>
            </Card>
          </Layout.Section>

          <Layout.Section>
            <OtpCampaignCouponCard />
          </Layout.Section>

          <Layout.Section>
            <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="400">
              {plans.map((p) => (
                <SinglePlan
                  key={p.planKey}
                  {...p}
                  country={"India"}
                  countryCode={selectedCountry}
                  countryOffer={countryOffers[p.planKey] || null}
                  downgradeBlocked={downgradeBlocked}
                  blockerKeys={blockerKeys}
                  currentPlanKey={currentPlanKey}
                  currentPlanPrice={currentPlanPrice}
                />
              ))}
            </InlineGrid>
          </Layout.Section>
        </Layout>
      </div>
    );
  }

  const handleBack = () => {
    journeyTracker.trackButtonClick("back_from_billing", {
      step: 3,
      feature: "billing",
      page: "plans-india",
      isOnboardingFlow: isOnboardingFlow,
    });
    if (window.history.length > 1) {
      window.history.back();
      return;
    }
    handleAppNavigation("/");
  };

  /* Plans is a top-level destination in the admin nav, so there is nothing to
     go back to and no arrow. Inside the onboarding wizard it is a step, and
     the way back to the previous one still belongs there. */
  const inOnboardingBilling =
    !!isOnboardingFlow ||
    (typeof window !== "undefined" &&
      window.location.pathname === "/quick-onboarding/billing");

  return (
    <Page
      compactTitle
      backAction={
        inOnboardingBilling
          ? { content: I18n.t("plans_india.back"), onAction: handleBack }
          : undefined
      }
      fullWidth
      title={I18n.t("plans_india.choose_plan_title")}
      subtitle={I18n.t("plans_india.choose_plan_subtitle")}
      /* The country picker rides with View pricing details: the two are the
         same decision, and the card that used to hold the picker was a
         billboard sitting between the merchant and the prices. */
      secondaryActions={
        <InlineStack gap="300" blockAlign="center" wrap={false}>
          <CountrySelector
            selectedCountry={selectedCountry}
            onCountryChange={handleCountryChange}
            label={I18n.t("plans_india.select_country_region")}
            placeholder={I18n.t("plans_india.search_countries")}
            useSelect
          />
          <Button
            url="https://notifiktech.com/message-pricing"
            target="_blank"
            external
          >
            {I18n.t("plans_india.view_pricing_details")}
          </Button>
        </InlineStack>
      }
    >
      <Layout>
        <Layout.Section>
          <OtpCampaignCouponCard />
        </Layout.Section>

        <Layout.Section>
          <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="400">
            {plans.map((p) => (
              <SinglePlanIndia
                key={p.planKey}
                {...p}
                countryOffer={countryOffers[p.planKey] || null}
                downgradeBlocked={downgradeBlocked}
                blockerKeys={blockerKeys}
                currentPlanKey={currentPlanKey}
                currentPlanPrice={currentPlanPrice}
              />
            ))}
          </InlineGrid>
        </Layout.Section>
      </Layout>

      <CodKingFooter />
    </Page>
  );
};

const PlansIndia = (props) => {
  const [version, setVersion] = useState(null);

  useEffect(() => {
    Api.get("/plans/india_pricing", { params: { fetch_shopify: false } })
      .then((res) => {
        const v = res.data?.pricingVersion ?? res.data?.pricing_version;
        setVersion(v === "v3" ? "v3" : "v2");
      })
      .catch(() => setVersion("v2"));
  }, []);

  if (version === null) {
    return (
      <InlineStack align="center">
        <Spinner accessibilityLabel={I18n.t("plans_india.loading_plans")} />
      </InlineStack>
    );
  }

  return version === "v3" ? (
    <PlansIndiaV3 {...props} />
  ) : (
    <PlansIndiaLegacy {...props} />
  );
};

export default PlansIndia;

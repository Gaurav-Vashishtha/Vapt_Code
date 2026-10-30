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
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import SinglePlanIndia from "./SinglePlanIndia";
import CountrySelector from "./CountrySelector";
import Plans from "./Plans";
import { navigateTo } from "../../utils/navigate";
import CodKingFooter from "../../utils/codkingFooter";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import I18n from "../i18n-lang";
import Api from "../Services/Api";
import { usePaidPlanDowngradeGate } from "../Hooks/usePaidPlanDowngradeGate";
import OtpCampaignCouponCard from "./OtpCampaignCouponCard";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";

const pick = (obj, camel, snake) => obj?.[camel] ?? obj?.[snake];

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

const parseInrDisplay = (display) => {
  if (!display) return null;
  const paise = display.match(/([\d.]+)\s*paise/i);
  if (paise) return parseFloat(paise[1]) / 100;
  const rupees = display.match(/₹\s*([\d.]+)/);
  return rupees ? parseFloat(rupees[1]) : null;
};

const PlansIndiaV3 = ({ isOnboardingFlow }) => {
  const [selectedCountry, setSelectedCountry] = useState("IN");
  const [indiaPricing, setIndiaPricing] = useState(null);
  const [countryOffers, setCountryOffers] = useState({});
  const [messageRates, setMessageRates] = useState(null);
  const [freeMessageRates, setFreeMessageRates] = useState(null);
  const [partialPaymentRates, setPartialPaymentRates] = useState(null);
  // COD Form orders per month of each plan (plans.cod_form_orders), for stores that have the
  // COD Form. A plan without a limit shows nothing.
  const codForm = useCodFormBootstrap();
  const formOrdersOf = (planKey) => {
    if (!codForm || !codForm.moduleEnabled) return null;
    const value = (codForm.planFormOrders || {})[planKey];
    return value === null || value === undefined || value === "" ? null : Number(value);
  };

  const {
    plan: [plan],
    setting: [setting, setSetting],
  } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);
  const { downgradeBlocked, blockerKeys } = usePaidPlanDowngradeGate();

  useEffect(() => {
    if (selectedCountry !== "IN") return;
    Api.get("/plans/india_pricing", { params: { fetch_shopify: true } })
      .then((res) => {
        const byKey = {};
        (res.data?.plans || []).forEach((p) => {
          const key = pick(p, "planKey", "plan_key");
          if (key) byKey[key] = p;
        });
        setIndiaPricing(byKey);
        setCountryOffers(countryOffersByPlan(res.data));
        setMessageRates(pick(res.data, "messageRates", "message_rates") || null);
        setFreeMessageRates(pick(res.data, "freeMessageRates", "free_message_rates") || null);
        setPartialPaymentRates(pick(res.data, "partialPaymentRates", "partial_payment_rates") || null);
      })
      .catch(() => setIndiaPricing({}));
  }, [selectedCountry]);

  useEffect(() => {
    journeyTracker.trackPageLoad({
      step: 3,
      feature: "billing",
      page: "plans-india-v3",
      selectedCountry,
      isOnboardingFlow,
      availablePlans: ["Free", "Pro", "Enterprise", "Enterprise Plus"],
    });
    if (window.location.pathname.includes("/quick-onboarding")) {
      journeyTracker.trackEvent("subscription_page_viewed", {
        step: 6,
        page: "plans-india-v3",
      });
    }
  }, []);

  const handleCountryChange = (countryCode) => {
    journeyTracker.trackButtonClick("country_change", {
      step: 3,
      feature: "billing",
      fromCountry: selectedCountry,
      toCountry: countryCode,
      isOnboardingFlow,
    });
    setSelectedCountry(countryCode);
  };

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

  const freeRates = freeMessageRates
    ? [
        {
          key: "sms",
          label: I18n.t("plans_india.message_rate_sms"),
          value: freeMessageRates.sms,
        },
        {
          key: "utility",
          label: I18n.t("plans_india.message_rate_whatsapp_utility"),
          value: pick(freeMessageRates, "whatsappUtility", "whatsapp_utility"),
        },
        {
          key: "marketing",
          label: I18n.t("plans_india.message_rate_whatsapp_marketing"),
          value: pick(freeMessageRates, "whatsappMarketing", "whatsapp_marketing"),
        },
      ]
    : null;

  const paidRates = messageRates
    ? [
        {
          key: "sms",
          label: I18n.t("plans_india.message_rate_sms"),
          value: messageRates.sms,
        },
        {
          key: "utility",
          label: I18n.t("plans_india.message_rate_whatsapp_utility"),
          value: pick(messageRates, "whatsappUtility", "whatsapp_utility"),
        },
        {
          key: "marketing",
          label: I18n.t("plans_india.message_rate_whatsapp_marketing"),
          value: pick(messageRates, "whatsappMarketing", "whatsapp_marketing"),
        },
      ]
    : null;

  // Plans that can send from the merchant's own WhatsApp number (BSP) also
  // show COD King's flat per-message fee for those sends.
  const bspRateValue = pick(messageRates || {}, "bspWhatsapp", "bsp_whatsapp");
  const bspPlanRates =
    paidRates && bspRateValue
      ? [
          ...paidRates,
          {
            key: "bsp",
            label: I18n.t("plans_india.message_rate_bsp_whatsapp", {
              defaultValue: "WhatsApp from your own number",
            }),
            value: bspRateValue,
          },
        ]
      : paidRates;

  const freeRate = pick(partialPaymentRates, "free", "free");
  const compareToFree = (rate) =>
    freeRate && rate
      ? I18n.t("plans_india.partial_payment_vs_free", { rate: freeRate })
      : null;

  const messageRatesCompareLabel =
    freeMessageRates && paidRates
      ? I18n.t("plans_india.message_rates_vs_free", {
          sms: freeMessageRates.sms,
          utility: pick(freeMessageRates, "whatsappUtility", "whatsapp_utility"),
          marketing: pick(freeMessageRates, "whatsappMarketing", "whatsapp_marketing"),
        })
      : null;

  const freeSms = parseInrDisplay(freeMessageRates?.sms);
  const paidSms = parseInrDisplay(messageRates?.sms);
  const smsSavingsPercent =
    freeSms && paidSms ? Math.round((1 - paidSms / freeSms) * 100) : null;
  const upgradeNudge =
    smsSavingsPercent > 0
      ? I18n.t("plans_india.upgrade_savings_nudge", { percent: smsSavingsPercent })
      : null;

  const plans = [
    {
      planKey: "Free",
      planName: "Free",
      price: 0,
      priceDisplay: "₹0",
      billing: I18n.t("plans_india.forever"),
      messageRates: freeRates,
      messageRatesNote: I18n.t("plans_india.pay_as_you_go_rates"),
      messageRatesFirst: true,
      partialPaymentRate: pick(partialPaymentRates, "free", "free"),
      partialPaymentCompareLabel: null,
      upsellNote: upgradeNudge,
      features: [
        I18n.t("plans_india.otp_verification_sms_whatsapp"),
        { text: I18n.t("plans.persistent_signin_feature"), bold: true },
        I18n.t("plans_india.automated_order_confirmation"),
        I18n.t("plans.order_fulfillment_notifications"),
        I18n.t("plans.reliable_sms_gateway"),
        I18n.t("plans.abandoned_cart_recovery"),
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
      messageRates: paidRates,
      messageRatesCompareLabel,
      messageRatesFirst: true,
      partialPaymentRate: partialPaymentRates?.pro,
      partialPaymentCompareLabel: compareToFree(partialPaymentRates?.pro),
      features: [
        I18n.t("plans.all_free_features"),
        I18n.t("plans_india.auto_filled_shipping"),
        I18n.t("plans_india.advanced_cod_eligibility"),
        I18n.t("plans.configurable_cod_fees"),
        I18n.t("plans.abandoned_cart_reminders"),
        I18n.t("plans.priority_support"),
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
      messageRates: bspPlanRates,
      messageRatesCompareLabel,
      partialPaymentRate: partialPaymentRates?.enterprise,
      partialPaymentCompareLabel: compareToFree(partialPaymentRates?.enterprise),
      highlightFeature: I18n.t("plans.branded_whatsapp_paid_plans"),
      features: [
        I18n.t("plans.all_pro_features"),
        I18n.t("plans.whatsapp_chat_widget"),
        I18n.t("plans_india.branded_sms_sender_v3"),
        I18n.t("plans_india.dedicated_indian_account_manager"),
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
      messageRates: bspPlanRates,
      messageRatesCompareLabel,
      partialPaymentRate: pick(partialPaymentRates, "enterprisePlus", "enterprise_plus"),
      partialPaymentCompareLabel: compareToFree(pick(partialPaymentRates, "enterprisePlus", "enterprise_plus")),
      highlightFeature: I18n.t("plans.remove_cod_king_branding"),
      badgeLabel: I18n.t("plans_india.built_to_scale"),
      badgeTone: "info",
      features: [
        I18n.t("plans_india.everything_in_enterprise"),
        { text: I18n.t("plans.branded_whatsapp_paid_plans"), bold: true },
        I18n.t("plans.whatsapp_chat_widget"),
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

  const planGrid = (
    <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="400">
        {plans.map((p) => (
          <SinglePlanIndia
            key={p.planKey}
            {...p}
            formOrders={formOrdersOf(p.planKey)}
            countryOffer={countryOffers[p.planKey] || null}
            downgradeBlocked={downgradeBlocked}
            blockerKeys={blockerKeys}
            currentPlanKey={currentPlanKey}
            currentPlanPrice={currentPlanPrice}
          />
        ))}
    </InlineGrid>
  );

  if (isOnboardingFlow) {
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
          <Layout.Section>{planGrid}</Layout.Section>
          <Layout.Section>
            <Text variant="bodySm" tone="subdued" alignment="center">
              {I18n.t("plans_india.billing_via_shopify_invoice")}
            </Text>
          </Layout.Section>
        </Layout>
      </div>
    );
  }

  const inOnboardingBilling =
    typeof window !== "undefined" &&
    window.location.pathname === "/quick-onboarding/billing";

  const handleBack = () => {
    journeyTracker.trackButtonClick("back_from_billing", {
      step: 3,
      feature: "billing",
      page: "plans-india-v3",
      isOnboardingFlow,
    });
    if (window.history.length > 1) {
      window.history.back();
      return;
    }
    navigateTo("/");
  };

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
      subtitle={I18n.t("plans_india.same_rates_all_paid_plans")}
      secondaryActions={
        <Button
          url="https://notifiktech.com/message-pricing"
          target="_blank"
          external
        >
          {I18n.t("plans_india.view_pricing_details")}
        </Button>
      }
    >
      <Layout>
        <Layout.Section>
          <OtpCampaignCouponCard />
        </Layout.Section>
        <Layout.Section>{planGrid}</Layout.Section>
        <Layout.Section>
          <BlockStack gap="200" inlineAlign="center">
            <Text variant="bodySm" tone="subdued" alignment="center">
              {I18n.t("plans_india.billing_via_shopify_invoice")}
            </Text>
            <InlineStack gap="200" blockAlign="center" align="center">
              <Text variant="bodySm" tone="subdued">
                {I18n.t("plans_india.not_in_india_prompt")}
              </Text>
              <CountrySelector
                selectedCountry={selectedCountry}
                onCountryChange={handleCountryChange}
                labelHidden
                placeholder={I18n.t("plans_india.search_countries")}
                useSelect
              />
            </InlineStack>
          </BlockStack>
        </Layout.Section>
      </Layout>
      <CodKingFooter />
    </Page>
  );
};

export default PlansIndiaV3;

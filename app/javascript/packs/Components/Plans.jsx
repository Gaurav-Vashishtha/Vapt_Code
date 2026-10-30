import React, {
  useContext,
  useState,
  useMemo,
  useEffect,
  useCallback,
} from "react";
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
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
  Banner,
  List,
} from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import SinglePlan from "./SinglePlan";
import { usePaidPlanDowngradeGate } from "../Hooks/usePaidPlanDowngradeGate";
import CountrySelector, { allCountries } from "./CountrySelector";
import PlansIndia from "./PlansIndia"; // Import your existing India plans component

import { navigateTo } from "../../utils/navigate";
import CodKingFooter from "../../utils/codkingFooter";
import { useUserJourneyTracker } from "../utils/userJourneyTracker";
import I18n from "../i18n-lang";

const Plans = ({ isOnboardingFlow, shop: shopProp }) => {
  const [onBoardingFlow, SetOnBoardingFlow] = useState(!!isOnboardingFlow);
  const [selectedCountry, setSelectedCountry] = useState("");
  const [pricingData, setPricingData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const {
    tab: [, setTab],
    isPrepaidEnabled,
    setting: [setting, setSetting],
    shop: [shop],
    plan: [plan],
  } = useContext(StoreContext);
  const journeyTracker = useUserJourneyTracker(setting, setSetting);
  const { downgradeBlocked, blockerKeys } = usePaidPlanDowngradeGate();

  // Initialize default country: prefer shopProp when coming from PlansIndia (country switch), else context shop
  useEffect(() => {
    const country = shopProp?.country_code || shop?.country_code || "US";
    setSelectedCountry(country);

    // Track page load
    journeyTracker.trackPageLoad({
      step: 3,
      feature: "billing",
      page: "plans-international",
      selectedCountry: country,
      isOnboardingFlow: isOnboardingFlow,
      availablePlans: ["Free", "Pro", "Enterprise", "Enterprise Plus"],
      currentPlan: plan?.name,
    });
    // Funnel stage: subscription page reached (onboarding billing only). India
    // delegates to <PlansIndia>, which emits its own — so skip IN here to avoid
    // double-firing.
    if (country !== "IN" && window.location.pathname.includes("/quick-onboarding")) {
      journeyTracker.trackEvent("subscription_page_viewed", {
        step: 6,
        page: "plans-international",
      });
    }
  }, [shop, plan, shopProp?.country_code]);

  // Handle country change - FIXED: No early returns
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

  const fetchPricingData = useCallback(async (countryCode) => {
    setLoading(true);
    setError(null);

    try {
      const shopDomain =
        shopProp?.shopify_domain || shop?.shopify_domain || "";
      const shopQuery = shopDomain
        ? `&shop=${encodeURIComponent(shopDomain)}`
        : "";
      const response = await fetch(
        `https://${process.env.APP_HOST}/order_confirmations/pricing?country_code=${countryCode}${shopQuery}`,
      );
      if (!response.ok) {
        throw new Error("Failed to fetch pricing data");
      }
      const data = await response.json();
      setPricingData(data);
    } catch (err) {
      setError(err.message);
      console.error("Error fetching pricing data:", err);
    } finally {
      setLoading(false);
    }
  }, [shopProp?.shopify_domain, shop?.shopify_domain]);

  // Fetch pricing when country or shop domain changes (excluding India)
  useEffect(() => {
    if (selectedCountry && selectedCountry !== "IN") {
      fetchPricingData(selectedCountry);
    }
  }, [selectedCountry, fetchPricingData]);

  // Get current country info
  const currentCountry = useMemo(() => {
    return (
      allCountries.find((country) => country.code === selectedCountry) ||
      allCountries.find((c) => c.code === "US")
    );
  }, [selectedCountry]);

  // Generate dynamic plans based on API data
  const dynamicPlans = useMemo(() => {
    if (!pricingData || !currentCountry) return [];

    const baseSmsPrice = parseFloat(pricingData.sms_price);
    const baseWhatsAppPrice = parseFloat(pricingData.whatsapp_price);
    // Category rates fall back to the single WhatsApp rate, exactly as billing does.
    const positiveOr = (v, fallback) => {
      const n = parseFloat(v);
      return Number.isFinite(n) && n > 0 ? n : fallback;
    };
    const baseUtilityPrice = positiveOr(pricingData.whatsapp_utility_price, baseWhatsAppPrice);
    const baseMarketingPrice = positiveOr(pricingData.whatsapp_marketing_price, baseWhatsAppPrice);
    // Plan multipliers mirror MessagePricing (what is actually billed):
    //   WhatsApp — Free 1.0, Pro 0.8, Enterprise / Enterprise Plus 0.6
    //   SMS      — Free 1.0, Pro 0.85, Enterprise 0.7, Enterprise Plus 0.3
    const r4 = (v) => +v.toFixed(4);
    const waRates = (m) => ({
      whatsappUtility: r4(baseUtilityPrice * m),
      whatsappMarketing: r4(baseMarketingPrice * m),
    });
    // Flat COD King fee per message sent from the merchant's own number (BSP),
    // same on every plan that has BSP; Meta bills its own fees to the merchant.
    const bspPrice = positiveOr(pricingData.bsp_whatsapp_price, null);
    const bspRates = bspPrice ? { bspWhatsapp: bspPrice } : {};
    const bspFeature = bspPrice
      ? [
          {
            text: I18n.t("plans.bsp_whatsapp_rate_feature", {
              price: bspPrice,
              defaultValue:
                "WhatsApp from your own number: $%{price} per message COD King fee (Meta bills its message fees to you directly)",
            }),
            bold: true,
          },
        ]
      : [];
    const waFeature = (m) => {
      const discount = Math.round((1 - m) * 100);
      const values = {
        utility: r4(baseUtilityPrice * m),
        marketing: r4(baseMarketingPrice * m),
        discount,
      };
      return {
        text:
          discount > 0
            ? I18n.t("plans.whatsapp_split_rates_discount", {
                ...values,
                defaultValue:
                  "WhatsApp rates: $%{utility} utility · $%{marketing} marketing per message (%{discount}% discount)",
              })
            : I18n.t("plans.whatsapp_split_rates", {
                ...values,
                defaultValue: "WhatsApp rates: $%{utility} utility · $%{marketing} marketing per message",
              }),
        bold: true,
      };
    };

    // Partial-payment fee per plan, as billed (PartialTransactionFee via the pricing endpoint).
    const partialRates = pricingData.partial_payment_rates || {};
    const partialRate = (key, fallback) => {
      const value = partialRates[key];
      if (value === null || value === undefined || value === "") return fallback;
      const n = Number(value);
      return Number.isFinite(n) ? n : fallback;
    };
    const freePartialRate = partialRate("free", 1.5);
    const proPartialRate = partialRate("pro", 0.8);
    const enterprisePartialRate = partialRate("enterprise", 0.5);
    const enterprisePlusPartialRate = partialRate("enterprise_plus", 0);
    const partialFeature = (rate) => ({
      text: I18n.t("plans.partial_payment_rate", {
        rate,
        defaultValue: "Partial payment collection (%{rate}% transaction fee per order)",
      }),
      bold: true,
    });

    const plans = [
      {
        planKey: "Free",
        planName: I18n.t("plans.plan_name_free"),
        price: 0,
        priceDisplay: "$0",
        billing: I18n.t("plans.billing_forever"),
        originalPrice: null,
        savings: null,
        recommended: false,
        rates: {
          sms: baseSmsPrice,
          ...waRates(1),
          transactionFee: freePartialRate,
        },
        features: [
          I18n.t("plans.otp_verification_sms_whatsapp"),
          { text: I18n.t("plans.persistent_signin_feature"), bold: true },
          {
            text: I18n.t("plans.competitive_sms_rates", { price: baseSmsPrice }),
            bold: true,
          },
          waFeature(1),
          I18n.t("plans.automated_order_confirmation"),
          I18n.t("plans.order_fulfillment_notifications"),
          I18n.t("plans.reliable_sms_gateway"),
          I18n.t("plans.abandoned_cart_recovery"),
          partialFeature(freePartialRate),
          I18n.t("plans.cod_to_prepaid_incentives"),
          I18n.t("plans.basic_support"),
        ],
      },
      {
        planKey: "Pro",
        planName: I18n.t("plans.plan_name_pro"),
        price: 9.99,
        priceDisplay: "$9.99",
        billing: I18n.t("plans.billing_per_month"),
        originalPrice: "$29.99",
        savings: I18n.t("plans.save_amount_month", { amount: 20 }),
        recommended: false,
        rates: {
          sms: +(baseSmsPrice * 0.85).toFixed(4),
          ...waRates(0.8),
          transactionFee: proPartialRate,
        },
        features: [
          I18n.t("plans.all_free_features"),
          {
            text: I18n.t("plans.premium_sms_rates", {
              price: +(baseSmsPrice * 0.85).toFixed(4),
            }),
            bold: true,
          },
          waFeature(0.8),
          
          partialFeature(proPartialRate),
          I18n.t("plans.advanced_cod_eligibility_rules"),
          I18n.t("plans.configurable_cod_fees"),
          I18n.t("plans.abandoned_cart_reminders"),
          I18n.t("plans.priority_support"),
          I18n.t("plans.realtime_verification_dashboard"),
          I18n.t("plans.auto_filled_shipping"),
          I18n.t("plans.payment_rules_customization_available"),
          I18n.t("plans.partial_payment_shipping_rate_keyword"),
        ],
      },
      {
        planKey: "Enterprise",
        planName: I18n.t("plans.plan_name_enterprise"),
        price: 39,
        priceDisplay: "$39",
        billing: I18n.t("plans.billing_per_month"),
        originalPrice: "$79",
        savings: I18n.t("plans.save_amount_month", { amount: 40 }),
        recommended: true,
        rates: {
          sms: r4(baseSmsPrice * 0.7),
          ...waRates(0.6),
          ...bspRates,
          transactionFee: enterprisePartialRate,
        },
        features: [
          I18n.t("plans.all_pro_features"),
          {
            text: I18n.t("plans.enterprise_sms_rates_discount", {
              price: r4(baseSmsPrice * 0.7),
              discount: 30,
              defaultValue: "Enterprise SMS rates: $%{price} per message (%{discount}% discount)",
            }),
            bold: true,
          },
          waFeature(0.6),
          I18n.t("plans.whatsapp_chat_widget"),
          { text: I18n.t("plans.branded_whatsapp_paid_plans"), bold: true },
          ...bspFeature,
          partialFeature(enterprisePartialRate),
          I18n.t("plans.exportable_data"),
          I18n.t("plans.branded_sms_sender"),
          I18n.t("plans.branded_whatsapp"),
          I18n.t("plans.advanced_analytics"),
          I18n.t("plans.dedicated_country_account_manager", {
            country: currentCountry.name,
          }),
          I18n.t("plans.priority_routing"),
          I18n.t("plans.priority_technical_support"),
          I18n.t("plans.auto_filled_shipping"),
          I18n.t("plans.payment_rules_customization_available"),
          I18n.t("plans.partial_payment_shipping_rate_keyword"),
        ],
      },
      {
        planKey: "Enterprise Plus",
        planName: I18n.t("plans.plan_name_enterprise_plus"),
        price: 59,
        priceDisplay: "$59",
        billing: I18n.t("plans.billing_per_month"),
        originalPrice: null,
        savings: null,
        recommended: false,
        rates: {
          sms: r4(baseSmsPrice * 0.3),
          ...waRates(0.6),
          ...bspRates,
          transactionFee: enterprisePlusPartialRate,
        },
        features: [
          I18n.t("plans.all_enterprise_features"),
          partialFeature(enterprisePlusPartialRate),
          ...bspFeature,
          I18n.t("plans.dedicated_account_manager"),
          I18n.t("plans.remove_cod_king_branding"),
          I18n.t("plans.otp_verification_checkout_shopify_plus"),
        ],
      },
    ];

    // Country offers from /admin/country_plan_offers, keyed by plan name (trial and/or price).
    const countryOffers = pricingData.country_offers || {};
    const withCountryOffers = (list) =>
      list.map((p) => {
        const o = countryOffers[p.planKey];
        if (!o) return p;
        const hasPrice = o.price_usd !== null && o.price_usd !== undefined;
        return {
          ...p,
          countryOffer: o,
          priceDisplay: hasPrice ? `$${Number(o.price_usd).toFixed(2)}` : p.priceDisplay,
          originalPrice: hasPrice ? p.priceDisplay : null,
          savings: null,
          limitedTimeOffer: false,
        };
      });

    const offer = pricingData.subscription_offer || {};
    if (offer.active) {
      return withCountryOffers(plans.map((p) =>
        p.planKey === "Free"
          ? p
          : {
              ...p,
              limitedTimeOffer: true,
              offerOriginalPrice: p.priceDisplay,
              priceDisplay: offer.charge_display || "$0.01 USD",
              originalPrice: null,
              savings: null,
            }
      ));
    }

    return withCountryOffers(plans);
  }, [pricingData, currentCountry, setting?.selectedLocale]);

  const currentPlanKey = plan?.name;
  const currentPlanPrice = dynamicPlans.find(
    (p) => p.planKey === currentPlanKey
  )?.price;

  // FIXED: Move India check to the very end, after all hooks
  // If India is selected, show PlansIndia component
  if (selectedCountry === "IN") {
    return (
      <PlansIndia isOnboardingFlow={isOnboardingFlow} shop={shopProp || shop} />
    );
  }

  if (loading) {
    return (
      <SkeletonPage fullWidth title={I18n.t("plans.choose_plan_title")}>
        <Layout>
          <Layout.Section>
            <Card>
              <BlockStack gap="400">
                <SkeletonDisplayText size="small" />
                <SkeletonBodyText lines={2} />
              </BlockStack>
            </Card>
          </Layout.Section>
          <Layout.Section>
            <InlineGrid columns={{ xs: 1, sm: 2, lg: 3 }} gap="400">
              {[...Array(3)].map((_, i) => (
                <Card key={i}>
                  <BlockStack gap="300">
                    <SkeletonDisplayText size="medium" />
                    <SkeletonBodyText lines={1} />
                    <SkeletonDisplayText size="small" />
                    <SkeletonBodyText lines={6} />
                  </BlockStack>
                </Card>
              ))}
            </InlineGrid>
          </Layout.Section>
        </Layout>
      </SkeletonPage>
    );
  }

  if (error) {
    return (
      <Card>
        <BlockStack gap="400">
          <Text variant="headingMd" as="h2" tone="critical">
            {I18n.t("plans.error_loading_pricing")}
          </Text>
          <Text variant="bodyMd">
            {I18n.t("plans.error_try_again", { error: error })}
          </Text>
        </BlockStack>
      </Card>
    );
  }

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
                      {I18n.t("plans.built_for_country", {
                        country: currentCountry.name,
                      })}
                    </Text>
                    <Text variant="bodyMd" as="p" tone="subdued">
                      {I18n.t("plans.premium_gateways_for_country", {
                        country: currentCountry.name,
                      })}
                    </Text>
                  </BlockStack>

                  {/* Country Selector */}
          <CountrySelector
          selectedCountry={selectedCountry}
          onCountryChange={handleCountryChange}
          labelHidden={true}
          placeholder={I18n.t("plans.search_countries")}
          />
                </InlineStack>

                <InlineStack gap="200" wrap>
                  <Badge>{I18n.t("plans.premium_gateway")}</Badge>
                  <Badge>{I18n.t("plans.local_compliance")}</Badge>
                  <Badge>{I18n.t("plans.usd_pricing")}</Badge>
                </InlineStack>
              </BlockStack>
            </Card>
          </Layout.Section>

          <Layout.Section>
            <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="400">
              {dynamicPlans.map((plan) => (
                <SinglePlan
                  key={plan.planKey}
                  {...plan}
                  country={currentCountry.name}
                  countryCode={selectedCountry}
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
    const isQuickOnboardingBilling =
      window.location.pathname === "/quick-onboarding/billing";
    journeyTracker.trackButtonClick("back_from_billing", {
      step: 3,
      feature: "billing",
      page: "plans-international",
      selectedCountry: selectedCountry,
      isOnboardingFlow: isOnboardingFlow ?? isQuickOnboardingBilling,
    });
    // history.back is unreliable in embedded apps, so the wizard is named.
    if (isQuickOnboardingBilling) {
      navigateTo("/quick-onboarding");
      return;
    }
    if (window.history.length > 1) {
      window.history.back();
      return;
    }
    navigateTo("/");
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
          ? { content: I18n.t("plans.back"), onAction: handleBack }
          : undefined
      }
      fullWidth
      title={I18n.t("plans.choose_plan_title")}
      subtitle={I18n.t("plans.choose_plan_subtitle", {
        country: currentCountry.name,
      })}
      /* The country picker rides with View pricing details: the two are the
         same decision, and the card that used to hold the picker was a
         billboard sitting between the merchant and the prices. */
      secondaryActions={
        <InlineStack gap="300" blockAlign="center" wrap={false}>
          <CountrySelector
            selectedCountry={selectedCountry}
            onCountryChange={handleCountryChange}
            label={I18n.t("plans.select_country_region")}
            placeholder={I18n.t("plans.search_countries")}
          />
          <Button
            url="https://notifiktech.com/message-pricing"
            target="_blank"
            external
          >
            {I18n.t("plans.view_pricing_details")}
          </Button>
        </InlineStack>
      }
    >
      <Layout>
        <Layout.Section>
          <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="400">
            {dynamicPlans.map((plan) => (
              <SinglePlan
                key={plan.planKey}
                {...plan}
                country={currentCountry.name}
                countryCode={selectedCountry}
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

export default Plans;

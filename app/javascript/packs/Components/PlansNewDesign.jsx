import React, { useState, useContext } from "react";
import { StoreContext } from "../Context/Store";
import {
  Layout,
  Page,
  Button,
  Icon,
  Card,
  Link,
  DataTable,
  Text,
  BlockStack,
  InlineStack,
  Banner,
  List,
} from "@shopify/polaris";
import I18n from "../i18n-lang";
import SinglePlanNewDesign, { IconText } from "./SinglePlanNewDesign";
import SinglePlan from "./SinglePlan";
import "./plans.css";
import { usePaidPlanDowngradeGate } from "../Hooks/usePaidPlanDowngradeGate";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";
import { isUnlimitedFormOrders } from "../Pages/CodForm/utils";

import {
  MobileAcceptMajor,
  ConnectMinor,
  ChevronUpMinor,
  ChevronDownMinor,
} from "@shopify/polaris-icons";

const defaultIcon = <Icon source={MobileAcceptMajor} tone="success" />;

const FeatureLink = ({
  url,
  onClick,
  icon = defaultIcon,
  text,
  external = false,
}) => {
  return (
    <BlockStack gap="100">
      <InlineStack
        gap="400"
        align="start"
        blockAlign="center"
        style={{ cursor: "pointer" }}
      >
        <span>{icon}</span>
        <Link url={url} onClick={onClick} external={external}>
          {text}
        </Link>
      </InlineStack>
    </BlockStack>
  );
};

const PlansNewDesign = () => {
  const {
    shop: [shop],
    plan: [currentPlan],
    visiblePlans,
    twilioPricing,
    tab: [, setTab],
    isPrepaidEnabled,
  } = useContext(StoreContext);
  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;
  const currentPlanKey = currentPlan?.name;

  const [showComparison, setShowComparison] = useState(true);

  /**
   * App Bridge v4 Internal Navigation
   */
  const handleInternalNav = (path, tabIndex) => {
    window.history.pushState({}, '', path);
    window.dispatchEvent(new PopStateEvent('popstate'));
    if (typeof setTab === 'function') {
      setTab(tabIndex);
    }
  };

  const handleToggleComparison = () => {
    setShowComparison(!showComparison);
  };

  const comparisonTable = (
    <DataTable
      columnContentTypes={["text", "text", "text", "text"]}
      headings={["Features", "Free", "Pro", "Enterprise"]}
      rows={[
        ["Order verification via OTP", "✔️", "✔️", "✔️"],
        [
          "Abandoned Cart Recovery Messages via SMS and Whatsapp",
          "✔️",
          "✔️",
          "✔️",
        ],
        ["Order placed & fulfillment notifications", "✔️", "✔️", "✔️"],
        ["Unlimited Orders", "✔️", "✔️", "✔️"],
        ["COD Fees - Add additional fees for COD orders", "❌", "✔️", "✔️"],
        ["Setup rules to Show or hide COD payment method", "❌", "✔️", "✔️"],
        [
          "Send WhatsApp from your brand (service messages are free from Meta)",
          "❌",
          "✔️",
          "✔️",
        ],
        ["Branded SMS with custom template", "❌", "❌", "✔️"],
        ["Local SMS gateway integration", "❌", "❌", "✔️"],
        ["Support Team", "✔️", "✔️", "✔️"],
      ]}
      headerRow={{
        style: { backgroundColor: "rgb(247, 247, 247)" },
      }}
    />
  );

  const customFeatures = [
    <FeatureLink
      key="network-integration"
      icon={<Icon source={ConnectMinor} tone="info" />}
      onClick={() => {
        if (shop.charge_id) {
          handleInternalNav('/networks', 6 + prepaidTabIncrement);
        } else {
          handleInternalNav('/', 0);
        }
      }}
      text={`Network provider integration Support`}
      external
    />,
    <IconText key="sms-extra" icon={<Icon source={MobileAcceptMajor} tone="success" />}>
      {I18n.t("admin.sms_cost_extra")}
    </IconText>,
    I18n.t("admin.feature_4"),
  ];

  const multiplier =
    shop.charge_multiplier && shop.charge_multiplier > 0
      ? shop.charge_multiplier
      : 1;

  const { downgradeBlocked, blockerKeys } = usePaidPlanDowngradeGate();

  // COD Form orders per month of a plan (plans.cod_form_orders). Shown only to stores that
  // have the COD Form, and only for plans that set a limit.
  const codForm = useCodFormBootstrap();
  const formOrdersOf = (planRow, name) => {
    if (!codForm || !codForm.moduleEnabled) return null;
    // planFormOrders already reflects a shop / country-group limit (e.g. unlimited in launch markets).
    const fromBootstrap = (codForm.planFormOrders || {})[name];
    const value = fromBootstrap != null ? fromBootstrap : planRow ? planRow.cod_form_orders : null;
    return value === null || value === undefined || value === "" ? null : Number(value);
  };
  const formOrdersText = (count) =>
    isUnlimitedFormOrders(count)
      ? I18n.t("plans.cod_form_orders_unlimited", { defaultValue: "Unlimited COD Form orders" })
      : I18n.t("plans.cod_form_orders", {
      defaultValue: "Up to %{count} COD Form orders per month",
      count: Number(count).toLocaleString(),
    });

  const currentPlanPrice = (visiblePlans || []).find(
    (p) => p.name === currentPlanKey
  )?.price;

  return (
    /* Plans is its own destination in the admin nav now rather than a row in
       Settings, so it carries a page heading of its own. */
    <Page
      title={I18n.t("nav.plans", { defaultValue: "Plans" })}
      subtitle={I18n.t("plans.page_subtitle", {
        defaultValue: "Choose the plan that works best for you.",
      })}
      fullWidth
    >
    <div style={{ padding: 15 }}>
      {visiblePlans?.map((plan, index) => {
        const formOrders = formOrdersOf(plan, plan.name);
        const features = customFeatures.concat(
          I18n.t("admin.upto_x_orders", { count: plan.max_sms || "-" }),
          I18n.t("admin.sms_cost_extra"),
          formOrders === null ? [] : [formOrdersText(formOrders)]
        );
        return (
          <SinglePlan
            key={plan.id}
            planKey={plan.name}
            planName={plan.name}
            recommended={plan.recommended}
            features={
              visiblePlans.length - 1 === index
                ? features.concat(
                    <FeatureLink
                      onClick={() => window.$crisp.push(["do", "chat:open"])}
                      external={true}
                      text={I18n.t("admin.need_more_sms")}
                    />
                  )
                : features
            }
            price={plan.price}
            strikePrice={plan.strike_price}
            maxOrders={plan.max_sms}
            downgradeBlocked={downgradeBlocked}
            blockerKeys={blockerKeys}
            currentPlanKey={currentPlanKey}
            currentPlanPrice={currentPlanPrice}
          />
        );
      })}

      {!visiblePlans && (
        <div className="plans-ctr">
          <div className="plans-ctr-hdr">
            <Text variant="headingLg" as="h2">
              {I18n.t("plans_new_design.plans")}
            </Text>
            <Text variant="bodyMd" tone="subdued">
              {I18n.t("plans_new_design.choose_the_plan_that_works_best")}
            </Text>
          </div>
          <div className="plans-ctr-content">
            <Layout>
              <SinglePlanNewDesign
                planKey="Free"
                formOrdersText={formOrdersOf(null, "Free") === null ? null : formOrdersText(formOrdersOf(null, "Free"))}
                planName={I18n.t("admin.free_plan")}
                price={0}
                multiplier={multiplier}
                planBriefTxt={`Explore our app's features with the free Plan`}
                addSpace={true}
                downgradeBlocked={downgradeBlocked}
                blockerKeys={blockerKeys}
                currentPlanKey={currentPlanKey}
                text={
                  twilioPricing.country_code == "IN"
                    ? `₹ ${multiplier} per Message in ${twilioPricing.country} `
                    : I18n.t("admin.price_for_country", {
                        price:
                          (twilioPricing.sms_price * multiplier).toFixed(3) ||
                          "-",
                        country: twilioPricing.country,
                      })
                }
              />
              <SinglePlanNewDesign
                planKey="Pro"
                formOrdersText={formOrdersOf(null, "Pro") === null ? null : formOrdersText(formOrdersOf(null, "Pro"))}
                planName={"Pro"}
                price={7.99}
                strikePrice={25}
                multiplier={multiplier}
                planBriefTxt={"Ideal for businesses with less number of orders"}
                addSpace={true}
                downgradeBlocked={downgradeBlocked}
                blockerKeys={blockerKeys}
                currentPlanKey={currentPlanKey}
                text={
                  twilioPricing.country_code == "IN"
                    ? "₹ " +
                      0.85 * multiplier +
                      `per Message in ${twilioPricing.country} `
                    : I18n.t("admin.price_for_country", {
                        price:
                          (twilioPricing.sms_price * 0.85 * multiplier).toFixed(
                            3
                          ) || "-",
                        country: twilioPricing.country,
                      })
                }
              />
              <SinglePlanNewDesign
                planKey="Premium"
                formOrdersText={formOrdersOf(null, "Premium") === null ? null : formOrdersText(formOrdersOf(null, "Premium"))}
                planName={"Enterprise"}
                price={39}
                strikePrice={59}
                multiplier={multiplier}
                planBriefTxt={
                  "Ideal for growing businesses, striving to build their brand"
                }
                downgradeBlocked={downgradeBlocked}
                blockerKeys={blockerKeys}
                currentPlanKey={currentPlanKey}
                text={
                  twilioPricing.country_code == "IN"
                    ? "₹ " +
                      0.7 * multiplier +
                      `per Message in ${twilioPricing.country} `
                    : I18n.t("admin.price_for_country", {
                        price:
                          (twilioPricing.sms_price * 0.7 * multiplier).toFixed(
                            3
                          ) || "-",
                        country: twilioPricing.country,
                      })
                }
              />
            </Layout>
          </div>

          <BlockStack align="center" gap="400" inlineAlign="center">
            <InlineStack gap="300">
              <Button
                variant={showComparison ? "secondary" : "primary"}
                onClick={handleToggleComparison}
              >
                <InlineStack gap="100" blockAlign="center">
                  <span>
                    {showComparison ? "Hide Comparison" : "Compare Plans"}
                  </span>
                  <Icon
                    source={showComparison ? ChevronDownMinor : ChevronUpMinor}
                  />
                </InlineStack>
              </Button>
              <Button
                variant="primary"
                onClick={() => handleInternalNav('/settings', 9 + prepaidTabIncrement)}
              >
                {I18n.t("plans_new_design.skip_plans_decide_later")}
              </Button>
            </InlineStack>

            {showComparison && (
              <BlockStack gap="400" inlineAlign="center">
                <Text variant="headingMd" as="h3">
                  {I18n.t("plans_new_design.plans_comparison")}
                </Text>
                <Text variant="bodyMd" tone="subdued" alignment="center">
                  {I18n.t("plans_new_design.compare_the_features_of_each_plan")}
                </Text>
                {comparisonTable}
              </BlockStack>
            )}
          </BlockStack>

          <div style={{ textAlign: "center" }}>
            <div style={{ width: "50%", margin: "2rem auto" }}>
              <Card>
                <BlockStack gap="400">
                  <Text variant="headingMd" as="h3">
                    {I18n.t("plans_new_design.looking_for_more")}
                  </Text>
                  <BlockStack gap="300">
                    <Text variant="bodyMd" tone="subdued">
                      {I18n.t("plans_new_design.don_t_stress_about_any_hidden")}
                      <br /> {I18n.t("plans_new_design.you_ll_only_be_charged_up")}
                    </Text>
                    <Text variant="bodyMd" tone="subdued">
                      {I18n.t("plans_new_design.if_you_have_any_specific_requirements")}
                    </Text>
                  </BlockStack>
                  <Button
                    onClick={() => window.$crisp.push(["do", "chat:open"])}
                    fullWidth
                  >
                    {I18n.t("plans_new_design.chat_with_us")}
                  </Button>
                </BlockStack>
              </Card>
            </div>
          </div>
        </div>
      )}
    </div>
    </Page>
  );
};

export default PlansNewDesign;
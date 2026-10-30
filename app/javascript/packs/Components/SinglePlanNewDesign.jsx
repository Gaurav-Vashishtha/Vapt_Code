import React, { useState, useContext, useEffect } from "react";
import { useAppBridge } from "@shopify/app-bridge-react";
import { StoreContext } from "../Context/Store";
import { usePlanFeatureOrder } from "../utils/planFeatureOrder";
import {
  Layout,
  Button,
  Badge,
  Card,
  Text,
  Link,
  Tooltip,
  Icon,
  InlineStack,
  BlockStack,
  Divider,
  Modal,
  List,
} from "@shopify/polaris";
// 1. REMOVED: import { Redirect } from "@shopify/app-bridge/actions";
import I18n from "../i18n-lang";
import Api from "../Services/Api";
import { MobileAcceptMajor } from "@shopify/polaris-icons";
import {
  consumePendingAndGoCustomSetup,
  shouldRedirectToCustomSetupAfterUpgrade,
} from "../utils/customSetupFlow";
import {
  filterBlockerKeysForTarget,
  isUpgradeToTarget,
} from "../utils/paidPlanDowngradeBlockers";

export const IconText = ({
  children,
  icon = <Icon source={MobileAcceptMajor} />,
}) => {
  return (
    <InlineStack gap="400" align="start" blockAlign="center">
      <span>{icon}</span>
      <span>{children}</span>
    </InlineStack>
  );
};

export const Price = ({ strikePrice, price = 19.99, recommended = false }) => {
  return (
    <InlineStack gap="200" align="start" blockAlign="center">
      {strikePrice && (
        <InlineStack gap="050" align="start" blockAlign="center">
          <Text
            variant="bodyMd"
            tone="subdued"
            textDecorationLine="line-through"
          >
            ${strikePrice}
          </Text>
        </InlineStack>
      )}
      <InlineStack gap="100" align="start" blockAlign="center">
        <Text variant="bodyMd" tone="subdued">
          $
        </Text>
        <Text variant="headingMd" as="span">
          {price}
        </Text>
        <Text variant="bodyMd" tone="subdued">
          /m
        </Text>
        {recommended && <Badge tone="success">{I18n.t("single_plan_new_design.most_popular")}</Badge>}
      </InlineStack>
    </InlineStack>
  );
};

const FeaturePrice = ({ strikePrice, price = 19.99, recommended = false }) => {
  return (
    <InlineStack gap="200" align="start" blockAlign="center">
      {strikePrice && (
        <Text variant="bodyMd" tone="subdued" textDecorationLine="line-through">
          ${strikePrice}
        </Text>
      )}
      <InlineStack gap="100" align="start" blockAlign="center">
        <Text variant="bodyMd" tone="subdued">
          $
        </Text>
        <Text variant="headingLg" as="span" tone="success">
          {price}
        </Text>
        <Text variant="bodyMd" tone="subdued">
          /m
        </Text>
        {recommended && <Badge tone="success">{I18n.t("single_plan_new_design.most_popular")}</Badge>}
      </InlineStack>
    </InlineStack>
  );
};

const SinglePlanNewDesign = ({
  features,
  planName,
  planKey,
  price = 10,
  strikePrice,
  recommended = false,
  maxOrders,
  planBriefTxt,
  multiplier,
  addSpace = false,
  text,
  downgradeBlocked = false,
  blockerKeys = [],
  currentPlanKey,
  currentPlanPrice,
  formOrdersText = null,
}) => {
  const shopify = useAppBridge();
  const MSG_TEXT_ARRAY = text.split("per Message in");
  const [loading, setLoading] = useState(false);
  const [orders, setOrders] = useState(maxOrders);
  const {
    shop: [shop, setShop],
    plan: [plan, setPlan],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [tab, setTab],
  } = useContext(StoreContext);

  const isFreePlanKey =
    planKey === "Free" || String(planName || "").toLowerCase().includes("free");

  const relevantBlockerKeys = filterBlockerKeysForTarget(blockerKeys, planKey);
  const isUpgrade = isUpgradeToTarget({
    currentPlanKey: currentPlanKey || plan?.name,
    currentPlanPrice,
    targetPlanKey: planKey,
    targetPrice: price,
  });
  const isDowngradeBlockedForTarget =
    downgradeBlocked && !isUpgrade && relevantBlockerKeys.length > 0;

  const [showDowngradeBlockedModal, setShowDowngradeBlockedModal] =
    useState(false);
  const [showCancelConfirmModal, setShowCancelConfirmModal] = useState(false);
  // Server-side error (e.g. a 422 downgrade block) to surface to the merchant.
  const [upgradeError, setUpgradeError] = useState(null);

  useEffect(() => {
    Api.get("/plans/opted_plan")
      .then((response) => {
        if (response?.data) {
          setPlan(response?.data);
        }
      })
      .catch((e) => {
        console.error("Error occurred:", e);
        return;
      });
  }, []);

  const onPlanSelect = (name) => () => {
    if (isDowngradeBlockedForTarget) {
      setShowDowngradeBlockedModal(true);
      return;
    }
    setLoading(true);
    Api.post("/plans/upgrade", { name, orders })
      .then((response) => {
        // 2. Updated for App Bridge v4
        // Use window.open with "_top" to redirect the parent Shopify frame
        if (response.data.confirmationUrl) {
          window.open(response.data.confirmationUrl, "_top");
        } else if (
          shouldRedirectToCustomSetupAfterUpgrade(response.data.confirmationUrl)
        ) {
          consumePendingAndGoCustomSetup();
        }
      })
      .catch((error) => {
        console.error("Error occurred:", error);
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

  const runCancel = (name) => {
    setLoading(true);
    Api.post("/plans/cancel", { name })
      .then((response) => {
        setPlan(response.data);
        setSetting({ ...setting, syncMusic: false });
        setOriginalSetting({ ...setting, syncMusic: false });
        
        // 3. Updated Internal Navigation for v4
        window.history.pushState({}, '', '/');
        window.dispatchEvent(new PopStateEvent('popstate'));
        setTab(0);
      })
      .catch((error) => {
        console.error(error);
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

  // The COD Form limit goes above the message rate when the store has the COD Form switched on.
  const { topics: onTopics } = usePlanFeatureOrder(setting);
  const codFormFirst = onTopics.cod_form;
  const messageRateRow = (
          <InlineStack gap="200" align="start" blockAlign="center">
            <Icon source={MobileAcceptMajor} tone="success" />
            <BlockStack gap="100">
              <Text variant="bodyMd" tone="subdued" fontWeight="bold">
                {I18n.t("single_plan_new_design.price_per_message_in", {
                  symbol: MSG_TEXT_ARRAY[0].charAt(0),
                  price: MSG_TEXT_ARRAY[0].substring(
                    1,
                    MSG_TEXT_ARRAY[0].length
                  ),
                  region: MSG_TEXT_ARRAY[2],
                  unit: MSG_TEXT_ARRAY[1],
                })}
              </Text>
              <Link
                url={`https://${process.env.APP_HOST}/pricing?multiplier=${multiplier}`}
                external={true}
              >
                {I18n.t("single_plan_new_design.rate_chart")}
              </Link>
            </BlockStack>
          </InlineStack>
  );
  const formOrdersRow = formOrdersText && (
            <InlineStack gap="200" align="start" blockAlign="center">
              <Icon source={MobileAcceptMajor} tone="success" />
              <Text variant="bodyMd" tone="subdued" fontWeight="bold">
                {formOrdersText}
              </Text>
            </InlineStack>
          );

  return (
    <Layout.Section oneThird>
      <Card>
        <BlockStack gap="400">
          <BlockStack gap="200">
            <Text variant="headingMd" as="h2">
              {planName}
            </Text>
            <Text variant="bodyMd" tone="subdued">
              {planBriefTxt}
              {addSpace && (
                <span>
                  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                </span>
              )}
            </Text>
            <FeaturePrice
              price={price}
              strikePrice={strikePrice}
              recommended={false}
            />
          </BlockStack>

          <Divider />

          {codFormFirst && formOrdersRow}
          {messageRateRow}
          {!codFormFirst && formOrdersRow}

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
            title={I18n.t("single_plan_new_design.cancel_plan")}
            primaryAction={{
              content: I18n.t("single_plan_new_design.cancel_plan"),
              destructive: true,
              loading,
              onAction: () => {
                setShowCancelConfirmModal(false);
                runCancel(planKey);
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
                  {I18n.t("single_plan_new_design.your_paid_features_may_stop_functioning")}
                </Text>
                {downgradeBlocked && (blockerKeys || []).length > 0 && (
                  <>
                    <Text as="p" variant="bodyMd" tone="subdued">
                      {I18n.t("single_plan_new_design.you_are_currently_using")}
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

          {plan.name === planKey && shop.charge_id && (
            <div style={{ textAlign: "center" }}>
              <Button
                loading={loading}
                variant="primary"
                tone="critical"
                onClick={() => setShowCancelConfirmModal(true)}
              >
                {I18n.t("single_plan_new_design.cancel_plan")}
              </Button>
            </div>
          )}

          {(!shop.charge_id || plan.name !== planKey) && (
            <div style={{ textAlign: "center" }}>
              <Tooltip content={"Subscribe"}>
                <Button
                  disabled={price < 0}
                  variant="primary"
                  onClick={onPlanSelect(planKey)}
                >
                  {planName.includes("Free") ? "Select Plan" : "Subscribe"}
                </Button>
              </Tooltip>
            </div>
          )}
        </BlockStack>
      </Card>
    </Layout.Section>
  );
};

export default SinglePlanNewDesign;
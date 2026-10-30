import React, { useContext, useEffect } from "react";
import {
  Card,
  Button,
  Text,
  InlineStack,
  BlockStack,
  ProgressBar,
  Banner,
  Link,
  Icon,
  Box,
  Badge,
} from "@shopify/polaris";
import { BalanceMajor } from "@shopify/polaris-icons";
import { StoreContext } from "../Context/Store";
import useApi from "../Hooks/useApi";
import { navigateTo } from "../../utils/navigate";
import I18n from "../i18n-lang";

const FreeWalletBalance = () => {
  const {
    setting: [setting],
    shop: [shop],
    twilioPricing,
    tab: [, setTab],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const [{ data: paymentMethods, loading, error }, getPaymentMethods] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/wallet_balance`,
      method: "GET",
    },
    { manual: true },
  );

  useEffect(() => {
    if (paymentMethods === undefined) {
      getPaymentMethods();
    }
  }, [paymentMethods, getPaymentMethods]);

  const totalBalance = paymentMethods?.wallet?.totalBalance
    ? parseFloat(paymentMethods.wallet.totalBalance)
    : 0;
  const balanceUsed = paymentMethods?.wallet?.balanceUsed
    ? parseFloat(paymentMethods.wallet.balanceUsed)
    : 0;

  const remainingBalance = totalBalance - balanceUsed;
  const isBalanceLow = remainingBalance <= 1.0;
  const isBalanceExhausted = remainingBalance <= 0;
  const progressPercent =
    totalBalance > 0 ? (remainingBalance / totalBalance) * 100 : 0;

  // Don't show if billing is already enabled
  if (shop.charge_id) return null;

  const getBalanceStatus = () => {
    if (isBalanceExhausted)
      return { color: "warning", text: I18n.t("free_wallet.status_exhausted") };
    if (isBalanceLow)
      return { color: "warning", text: I18n.t("free_wallet.status_low") };
    return { color: "success", text: I18n.t("free_wallet.status_active") };
  };

  const balanceStatus = getBalanceStatus();

  return (
    <div>
      <Card>
        <BlockStack gap="300">
          {/* Compact Header */}
          <InlineStack align="space-between" blockAlign="center">
            <InlineStack gap="150" blockAlign="center">
              <Icon source={BalanceMajor} tone="base" />
              <Text as="h3" variant="headingSm">
                {I18n.t("free_wallet.title")}
              </Text>
              <Badge tone={balanceStatus.color} size="small">
                {balanceStatus.text}
              </Badge>
            </InlineStack>
            <Text as="span" variant="headingMd" tone="base">
              ${remainingBalance.toFixed(2)}
            </Text>
          </InlineStack>

          {/* Compact Progress */}
          <BlockStack gap="100">
            <InlineStack align="space-between">
              <Text as="span" variant="bodyXs" tone="subdued">
                {I18n.t("free_wallet.used_of", {
                  used: balanceUsed.toFixed(2),
                  total: totalBalance.toFixed(2),
                })}
              </Text>
              <Text as="span" variant="bodyXs" tone="subdued">
                {I18n.t("free_wallet.percent_left", {
                  percent: progressPercent.toFixed(0),
                })}
              </Text>
            </InlineStack>
            <ProgressBar
              value={Math.max(0, progressPercent)}
              tone={
                isBalanceExhausted
                  ? "warning"
                  : isBalanceLow
                    ? "warning"
                    : "success"
              }
              size="small"
            />
          </BlockStack>

          {/* Compact Alert */}
          {isBalanceExhausted && (
            <Banner tone="warning" hideIcon>
              <Text as="p" variant="bodySm">
                {I18n.t("free_wallet.balance_exhausted")}{" "}
                <Link
                  onClick={() => navigateTo("/subscription")}
                  removeUnderline
                >
                  {I18n.t("free_wallet.enable_billing")}
                </Link>
              </Text>
            </Banner>
          )}

          {isBalanceLow && !isBalanceExhausted && (
            <Banner tone="warning" hideIcon>
              <Text as="p" variant="bodySm">
                {I18n.t("free_wallet.running_low")}{" "}
                <strong>{shop.owner_email}</strong>{" "}
                {I18n.t("free_wallet.when_exhausted")}{" "}
                <Link
                  onClick={() => navigateTo("/subscription")}
                  removeUnderline
                >
                  {I18n.t("free_wallet.enable_billing")}
                </Link>
              </Text>
            </Banner>
          )}

          {/* Compact Upgrade Section - Only show if not exhausted */}
          {!isBalanceExhausted && (
            <Box
              background="bg-surface-secondary"
              borderRadius="150"
              padding="300"
            >
              <InlineStack align="space-between" blockAlign="center" gap="200">
                <BlockStack gap="050">
                  <Text as="span" variant="bodySm" tone="base">
                    {I18n.t("free_wallet.unlock_unlimited")}
                  </Text>
                  <Text as="span" variant="bodyXs" tone="subdued">
                    {I18n.t("free_wallet.enable_billing_unlimited")}
                  </Text>
                </BlockStack>
                <Button
                  variant="primary"
                  size="slim"
                  onClick={() => navigateTo("/subscription")}
                >
                  {I18n.t("free_wallet.view_plans")}
                </Button>
              </InlineStack>
            </Box>
          )}
        </BlockStack>
      </Card>
      <br />
    </div>
  );
};

export default FreeWalletBalance;

import React from "react";
import { Card, BlockStack, InlineStack, Text, Button, Icon, Badge } from "@shopify/polaris";
import { LockMinor } from "@shopify/polaris-icons";
import { navigateTo } from "../../../../utils/navigate";
import useCodFormBootstrap from "../useCodFormBootstrap";
import { PATHS, tierName } from "../constants";
import { t } from "../i18n";

/** {allowed, minTier} for a feature key of the gate table (J.1). A key the
    server did not send is treated as allowed; the API still enforces it (402). */
export const useGate = (feature) => {
  const bootstrap = useCodFormBootstrap();
  const gate = bootstrap && bootstrap.gates ? bootstrap.gates[feature] : null;
  return {
    allowed: !gate || gate.allowed !== false,
    minTier: (gate && gate.min_tier) || "pro",
    tier: bootstrap ? bootstrap.tier : "free",
  };
};

/** Locked card: plan name + upgrade button (PM decision Q9). */
export const UpgradeCard = ({ title, description, minTier, compact }) => {
  const plan = tierName(minTier || "pro");
  const body = (
    <BlockStack gap="300">
      <InlineStack gap="200" blockAlign="center" wrap={false}>
        <span style={{ display: "inline-flex", flex: "0 0 auto" }}>
          <Icon source={LockMinor} tone="subdued" />
        </span>
        <Text as="h3" variant="headingSm">
          {title || t("common.upgrade_required", "Upgrade required")}
        </Text>
        <Badge tone="info">{plan}</Badge>
      </InlineStack>
      <Text as="p" variant="bodyMd" tone="subdued">
        {description ||
          t("common.upgrade_body", "This feature is available on the %{plan} plan and above. Your saved settings are kept.", { plan })}
      </Text>
      <InlineStack>
        <Button variant="primary" onClick={() => navigateTo(PATHS.subscription)}>
          {t("common.upgrade_cta", "Upgrade to %{plan}", { plan })}
        </Button>
      </InlineStack>
    </BlockStack>
  );
  return compact ? body : <Card>{body}</Card>;
};

/**
 * <Gate feature="order_bumps">…</Gate> renders its children when the shop's
 * plan allows the feature, otherwise the locked card.
 */
const Gate = ({ feature, title, description, compact, children }) => {
  const { allowed, minTier } = useGate(feature);
  if (allowed) return <>{children}</>;
  return <UpgradeCard title={title} description={description} minTier={minTier} compact={compact} />;
};

export default Gate;

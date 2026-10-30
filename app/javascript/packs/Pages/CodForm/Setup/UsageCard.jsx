import React from "react";
import { BlockStack, Banner } from "@shopify/polaris";
import { navigateTo } from "../../../../utils/navigate";
import { SectionCard } from "../../../Components/SettingsPrimitives";
import UsageMeter from "../components/UsageMeter";
import { PATHS, nextTier, tierName } from "../constants";
import { t } from "../i18n";

/** In-app usage notice shared by Setup and the Summary card (CAP-8, H.8). */
export const UsageNotice = ({ usage, tier }) => {
  if (!usage || usage.cap === null || usage.cap === undefined) return null;
  const percent = usage.percent != null ? Number(usage.percent) : usage.cap > 0 ? (Number(usage.orders) / usage.cap) * 100 : 0;
  const upgradeTo = nextTier(tier || "free");
  const upgrade = upgradeTo
    ? {
        content: t("summary.flagged_cta", "Upgrade to %{plan}", { plan: tierName(upgradeTo) }),
        onAction: () => navigateTo(PATHS.subscription),
      }
    : undefined;

  if (usage.state === "flagged") {
    return (
      <Banner tone="info" action={upgrade}>
        <p>{t("summary.flagged_body", "You have passed %{cap} form orders this month. Your form keeps working.", { cap: usage.cap })}</p>
      </Banner>
    );
  }
  if (usage.state === "fallback") {
    return (
      <Banner tone="critical" action={upgrade}>
        <p>{t("summary.notice_fallback", "You have used all %{cap} form orders for this month. The Buy with COD button is off on your store until next month, or until you upgrade.", { cap: usage.cap })}</p>
      </Banner>
    );
  }
  if (usage.state === "grace" || percent >= 100) {
    return (
      <Banner tone="warning" action={upgrade}>
        <p>{t("summary.notice_100", "You have reached %{cap} form orders this month. A few more orders still go through the form; after that the Buy with COD button is switched off until next month.", { cap: usage.cap })}</p>
      </Banner>
    );
  }
  if (percent >= 80) {
    return (
      <Banner tone="warning" action={upgrade}>
        <p>{t("summary.notice_80", "You have used %{orders} of %{cap} form orders this month.", { orders: usage.orders, cap: usage.cap })}</p>
      </Banner>
    );
  }
  return null;
};

/** Usage against the order cap on the Setup screen. */
const UsageCard = ({ usage, tier }) => {
  if (!usage) return null;
  return (
    <SectionCard
      title={t("setup.usage_title", "Form orders this month")}
      description={t("setup.usage_help", "Orders created by the COD Form, counted per calendar month. Test orders and prepaid redirects do not count.")}
    >
      <BlockStack gap="300">
        <UsageMeter usage={usage} />
        <UsageNotice usage={usage} tier={tier} />
      </BlockStack>
    </SectionCard>
  );
};

export default UsageCard;

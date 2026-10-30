import React from "react";
import { Page, Layout, BlockStack, InlineGrid } from "@shopify/polaris";
import I18n from "../../i18n-lang";
import BillingPlanCard from "./cards/BillingPlanCard";
import RevenueCard from "./cards/RevenueCard";
import AovCard from "./cards/AovCard";
import OrdersBreakdownCard from "./cards/OrdersBreakdownCard";
import PartialRevenueCard from "./cards/PartialRevenueCard";
import CodToPrepaidCard from "./cards/CodToPrepaidCard";
import MessageSummaryCard from "./cards/MessageSummaryCard";
import RtoCard from "./cards/RtoCard";
import FormFunnelCard from "./cards/FormFunnelCard";
import FeatureSummaryCard from "./cards/FeatureSummaryCard";

const SummaryV2 = () => {
  return (
    <Page
      title={I18n.t("summary_v2.title", { defaultValue: "Dashboard" })}
      subtitle={
        I18n.t("summary_v2.subtitle", { defaultValue: "A fast overview of your COD performance." })
      }
    >
      <Layout>
        <Layout.Section>
          <BlockStack gap="400">
            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
              <RevenueCard />
              <AovCard />
            </InlineGrid>

            <FormFunnelCard />

            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
              <OrdersBreakdownCard />
              <PartialRevenueCard />
              <CodToPrepaidCard />
              <RtoCard />
            </InlineGrid>

            <InlineGrid columns={{ xs: 1, sm: 2 }} gap="400">
              <MessageSummaryCard />
              <FeatureSummaryCard />
            </InlineGrid>
          </BlockStack>
        </Layout.Section>

        <Layout.Section variant="oneThird">
          <BillingPlanCard />
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default SummaryV2;

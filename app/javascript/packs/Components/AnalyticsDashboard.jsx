import React, { useState } from "react";
import { Page, Select, BlockStack } from "@shopify/polaris";
import I18n from "../i18n-lang";
import MessageSummaryCard from "./Analytics/MessageSummaryCard";
import ImpactStats from "./Analytics/ImpactStats";
import { DEFAULT_DAYS, dayOptions } from "./Analytics/dateRange";

const AnalyticsDashboard = () => {
  const [days, setDays] = useState(DEFAULT_DAYS);

  return (
    <Page
      fullWidth
      title={I18n.t("analytics.dashboard_title")}
      primaryAction={
        <Select
          label={I18n.t("analytics.select_time_range")}
          labelHidden
          options={dayOptions()}
          onChange={setDays}
          value={days}
        />
      }
    >
      <BlockStack gap="500">
        <ImpactStats days={days} />
        <MessageSummaryCard days={days} />
      </BlockStack>
    </Page>
  );
};

export default AnalyticsDashboard;

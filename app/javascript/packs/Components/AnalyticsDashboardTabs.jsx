import React, { useEffect, useState, lazy, Suspense } from "react";
import {
  Page,
  Tabs,
  Card,
  Box,
  BlockStack,
  SkeletonBodyText,
} from "@shopify/polaris";
import styled from "styled-components";
import I18n from "../i18n-lang";
import useCodFormBootstrap from "../Pages/CodForm/useCodFormBootstrap";

/* Each tab renders a whole screen, Page and all. Nested inside this one they
   were paying the page gutter twice and, until now, sitting inside a Card as
   well. The frame comes from the outer Page; the inner one just supplies its
   title and actions. */
const TabContent = styled.div`
  .Polaris-Page {
    padding-inline-start: 0;
    padding-inline-end: 0;
    padding-left: 0;
    padding-right: 0;
    max-width: none;
  }
`;

// Lazy-loaded components
const AnalyticsDashboard = lazy(() => import("./AnalyticsDashboard"));
const Logs = lazy(() => import("./Logs"));
const MessageLogs = lazy(() => import("./MessageLogs"));
const UsageLogs = lazy(() => import("./UsageLogs"));
const CodKingAbandonedCarts = lazy(() => import("./CodKingAbandonedCarts"));
const WhatsappLogsPage = lazy(() => import("../Pages/Whatsapp/WhatsappLogsPage"));
const ImpactOrders = lazy(() => import("./Analytics/ImpactOrders"));
const CodFormAnalytics = lazy(() =>
  import(
    /* webpackChunkName: "cod-form-admin" */ "../Pages/CodForm/Analytics/CodFormAnalytics"
  ),
);

const getTabRoutes = () => [
  { path: "/usage-analytics", content: I18n.t("analytics_tabs.overview", { defaultValue: "Overview" }) },
  { path: "/usage-analytics/orders", content: I18n.t("analytics_tabs.orders_by_feature", { defaultValue: "Orders by feature" }) },
  { path: "/usage-analytics/message-logs", content: I18n.t("analytics_tabs.message_logs") },
  { path: "/usage-analytics/usage-logs", content: I18n.t("analytics_tabs.usage_charges") },
  {
    path: "/usage-analytics/branded-notifications",
    content: I18n.t("analytics_tabs.branded_notifications", { defaultValue: "Branded Notifications" }),
  },
  { path: "/usage-analytics/cod-king-abandoned-carts", content: I18n.t("analytics_dashboard_tabs.cod_king_abandoned_carts") },
  { path: "/usage-analytics/order-logs", content: I18n.t("analytics_tabs.order_logs") },
];

const AnalyticsDashboardTabs = () => {
  // The COD Form tab is appended last (index 7) and only for shops that have the module.
  const codForm = useCodFormBootstrap();
  const tabRoutes = getTabRoutes().concat(
    codForm?.moduleEnabled
      ? [{ path: "/usage-analytics/cod-form", content: I18n.t("analytics_tabs.cod_form", { defaultValue: "COD Form" }) }]
      : [],
  );
  const [currentPath, setCurrentPath] = useState(window.location.pathname);

  useEffect(() => {
    const syncPath = () => {
      setCurrentPath(window.location.pathname);
    };

    syncPath();
    window.addEventListener("popstate", syncPath);
    return () => window.removeEventListener("popstate", syncPath);
  }, []);

  const selectedTab = Math.max(
    0,
    tabRoutes.findIndex((tab) => tab.path === currentPath),
  );

  const handleTabChange = (index) => {
    if (index === selectedTab) return;

    const newPath = tabRoutes[index].path;

    // App Bridge v4: Use window.history.pushState for navigation
    window.history.pushState({}, "", newPath);
    window.dispatchEvent(new PopStateEvent("popstate"));
  };

  const renderTabContent = () => {
    switch (selectedTab) {
      case 0:
        return <AnalyticsDashboard />;
      case 1:
        return <ImpactOrders />;
      case 2:
        return <MessageLogs />;
      case 3:
        return <UsageLogs />;
      case 4:
        return <WhatsappLogsPage />;
      case 5:
        return <CodKingAbandonedCarts />;
      case 6:
        return <Logs />;
      case 7:
        return <CodFormAnalytics />;
      default:
        return null;
    }
  };

  return (
    <Page fullWidth>
      <BlockStack gap="400">
        <Card padding="200">
          <Tabs
            tabs={tabRoutes.map((tab, idx) => ({
              id: `tab-${idx}`,
              content: tab.content,
              panelID: `tab-content-${idx}`,
            }))}
            selected={selectedTab}
            onSelect={handleTabChange}
            fitted
          />
        </Card>

        <TabContent>
          <Suspense
            fallback={
              <Card>
                <Box padding="400">
                  <BlockStack gap="400">
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                    <SkeletonBodyText lines={1} />
                  </BlockStack>
                </Box>
              </Card>
            }
          >
            {renderTabContent()}
          </Suspense>
        </TabContent>
      </BlockStack>
    </Page>
  );
};

export default AnalyticsDashboardTabs;

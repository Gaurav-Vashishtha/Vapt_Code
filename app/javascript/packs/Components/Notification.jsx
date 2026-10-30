import React, {
  useState,
  useContext,
  useCallback,
  useEffect,
  useMemo,
} from "react";
import { StoreContext } from "../Context/Store";
import {
  Layout,
  Button,
  Card,
  BlockStack,
  Text,
  Icon,
  Page,
  Box,
  Divider,
  SkeletonPage,
  SkeletonBodyText,
  SkeletonDisplayText,
} from "@shopify/polaris";
import useApi from "../Hooks/useApi";
import NetworkSettingTab from "./Tabs/NetworkSettingTab";
import NotificationSettingsTab from "./Tabs/NotificationSettingsTab";
import BrandNotificationTab from "./Tabs/BrandNotificationTab";
import WhatsappTemplateList from "./Tabs/WhatsappTemplateList";
// WhatsApp tabs now live in /features/whatsapp — see Pages/Whatsapp/*
import {
  NotificationMajor,
  SettingsMajor,
  StoreMajor,
  ConversationMinor,
} from "@shopify/polaris-icons";

import I18n from "../i18n-lang";
import FeatureCallout from "./FeatureCallout";

const CUSTOMER_NOTIFICATIONS_CALLOUT_IMAGE =
  "https://cdn.shopify.com/s/files/1/0776/0058/7973/files/WhatsApp_Image_2026-09-17_at_2.13.15_PM_2.jpg?v=1791393038";
import { navigateTo } from "../../utils/navigate";

const Notification = () => {
  const { contextualBar: [contextualBar] } = useContext(StoreContext);
  const [selected, setSelected] = useState(0);
  // Remove mobile logic, Polaris Tabs are now responsive

  const [{ data: apiData, loading, error }, saveSettings] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings`,
      method: "POST",
    },
    { manual: true }
  );

  const [{ data, loading: settingsLoading }, refetchSettings] = useApi(
    {
      url: "/settings/setting",
      method: "get",
    },
    { manual: true }
  );

  const tabs = [
    {
      id: "customer-notifications",
      content: (
        <BlockStack align="center" gap="100">
          {/* <Icon source={NotificationMajor} /> */}
          {I18n.t("notification.customer_notifications")}
        </BlockStack>
      ),
      accessibilityLabel: I18n.t("notification.customer_notifications"),
      panelID: "customer-notifications-content",
    },
    // {
    //   id: "network-settings",
    //   content: (
    //     <BlockStack align="center" gap="100">
    //       {/* <Icon source={SettingsMajor} /> */}
    //       {I18n.t("notification.network_settings")}
    //     </BlockStack>
    //   ),
    //   accessibilityLabel: I18n.t("notification.network_settings"),
    //   panelID: "network-settings-content",
    // },
    // {
    //   id: "branded-notifications",
    //   content: (
    //     <BlockStack align="center" gap="100">
    //       {/* <Icon source={StoreMajor} /> */}
    //       {I18n.t("notification.branded_notifications")}
    //     </BlockStack>
    //   ),
    //   accessibilityLabel: I18n.t("notification.branded_notifications"),
    //   panelID: "branded-notifications-content",
    // },
    // {
    //   id: "whatsapp-template-management",
    //   content: (
    //     <BlockStack align="center" gap="100">
    //       {/* <Icon source={ConversationMinor} /> */}
    //       {I18n.t("notification.whatsapp_template_management")}
    //     </BlockStack>
    //   ),
    //   accessibilityLabel: I18n.t("notification.whatsapp_template_management"),
    //   panelID: "whatsapp-template-management-content",
    // },
  ];

  const handleTabChange = useCallback((selectedTabIndex) => {
    setSelected(selectedTabIndex);
  }, []);

  useEffect(() => {
    refetchSettings();
  }, [refetchSettings]);

  // Loading skeleton – matches Notification: single content area (customer notifications panel)
  if (settingsLoading && !data) {
    return (
      <SkeletonPage primaryAction>
        <BlockStack gap="400">
          <Card>
            <Box padding="400">
              <BlockStack gap="300">
                <SkeletonDisplayText size="small" />
                <SkeletonBodyText lines={2} />
                <Divider />
                <SkeletonBodyText lines={3} />
                <SkeletonBodyText lines={2} />
              </BlockStack>
            </Box>
          </Card>
          <Card>
            <Box padding="400">
              <BlockStack gap="200">
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
                <SkeletonBodyText lines={1} />
              </BlockStack>
            </Box>
          </Card>
        </BlockStack>
      </SkeletonPage>
    );
  }

  const tabPanels = [
    <NotificationSettingsTab key="notification" />,
    // <NetworkSettingTab key="network" />,
    // <BrandNotificationTab key="branded" />,
    // <WhatsappTemplateList key="whatsapp" />,
  ];

  return (
    <Page
      title={I18n.t("notification.customer_notifications")}
      subtitle={I18n.t("notification.customer_notifications_help")}
      fullWidth={true}
    >
      <BlockStack gap="400">
        <FeatureCallout
          illustration="notify"
          image={CUSTOMER_NOTIFICATIONS_CALLOUT_IMAGE}
          title={I18n.t("notification.customer_notifications")}
          description={I18n.t("notification.customer_notifications_help")}
          docsUrl="https://codking.tech/documentation/"
          actions={
            <Button onClick={() => navigateTo("/features/whatsapp")}>
              {I18n.t("whatsapp_integration.integrate_whatsapp_number")}
            </Button>
          }
          showChat
        />

        {/* One tab left, so the tab strip was a card wrapping a single label. */}
        {tabPanels.map((panel, index) => (
          <div key={tabs[index].id} hidden={index !== selected}>
            <Box>{panel}</Box>
          </div>
        ))}
      </BlockStack>
    </Page>
  );
};

export default Notification;

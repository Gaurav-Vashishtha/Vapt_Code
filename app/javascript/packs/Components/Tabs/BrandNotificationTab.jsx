import React, {
  useContext,
  useCallback,
  useState,
  useEffect,
  useRef,
} from "react";
// 1. Correct Import for App Bridge v4
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  Card,
  Layout,
  FormLayout,
  Form,
  TextField,
  Button,
  OptionList,
  Tag,
  Scrollable,
  Popover,
  Banner,
  Text,
  Link,
  InlineStack,
  BlockStack,
} from "@shopify/polaris";
import countries from "../Country";
import I18n from "../../i18n-lang";
import useApi from "../../Hooks/useApi";
import { navigateTo } from "../../../utils/navigate";
import { StoreContext } from "../../Context/Store";

const BrandNotificationTab = () => {
  const shopify = useAppBridge(); // Initialize App Bridge v4
  const {
    loading: [loading, setLoading],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    contextualBar: [contextualBar, setContextualBar],
    plan: [plan],
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const prepaidTabIncrement = isPrepaidEnabled ? 1 : 0;
  const [selectedCountries, setSelectedCountries] = useState(
    setting.countryCodes || ""
  );
  const [status, setStatus] = useState(null);
  const [popoverActive, setPopoverActive] = useState(false);
  const settingRef = useRef(setting);

  const togglePopoverActive = useCallback(
    () => setPopoverActive((prev) => !prev),
    []
  );

  const activator = (
    <Button onClick={togglePopoverActive} disclosure>
      {I18n.t("notification.select_at_least_one_country")}
    </Button>
  );

  const [{}, saveSettings] = useApi(
    {
      url: `https://${process.env.APP_HOST}/headers`,
      method: "POST",
    },
    { manual: true }
  );

  const handleSettingChange = (key) => (value) => {
    setStatus(null);
    const updatedValue = key === "countryCodes" ? value.toString() : value;
    
    if (key === "countryCodes") {
      setSelectedCountries(updatedValue);
    }
    
    setSetting((prev) => ({
      ...prev,
      [key]: updatedValue,
    }));
    
    if (!contextualBar) setContextualBar(true);
  };

  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  const handleSubmit = async () => {
    if (plan.name === "Premium" || plan.name === "Enterprise" || plan.name === "india_budget") {
      setLoading(true);
      try {
        const resp = await saveSettings({
          data: { header: settingRef.current },
        });

        if (resp?.status === 200) {
          setContextualBar(false);
          setStatus(true);
          setOriginalSetting(settingRef.current);
          shopify.toast.show(I18n.t("admin.settings_saved"));
        } else {
          setStatus(false);
        }
      } catch (error) {
        setStatus(false);
      } finally {
        setLoading(false);
      }
    } else {
      setStatus("info");
    }
  };

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setSelectedCountries(cloned.countryCodes || "");
    setStatus(null);
    setContextualBar(false);
  }, [originalSetting, setSetting, setContextualBar]);

  return (
    <Form onSubmit={handleSubmit}>
      {/* 2. Declarative SaveBar for App Bridge v4 */}
      <SaveBar data-save-bar open={contextualBar}>
        <button
          variant="primary"
          onClick={handleSubmit}
          loading={loading ? "" : undefined}
          disabled={loading}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>
          {I18n.t("admin.discard")}
        </button>
      </SaveBar>

      <BlockStack gap="400">
        {status === true && (
          <Banner tone="success" title={I18n.t("admin.settings_saved")}>
            <div dangerouslySetInnerHTML={{ __html: I18n.t("notification.header_submit_success") }} />
          </Banner>
        )}

        {status === false && (
          <Banner tone="critical" title={I18n.t("notification.error")}>
            <div dangerouslySetInnerHTML={{ __html: I18n.t("admin.something_went_wrong") }} />
          </Banner>
        )}

        {status === "info" && (
          <Banner tone="info" title={I18n.t("notification.upgrade_title")}>
            <Text variant="bodySm" tone="subdued">
              {I18n.t("notification.upgrade_text")}{" "}
              <Link onClick={() => navigateTo("/subscription")}>
                <Text as="span" fontWeight="bold">{I18n.t("notification.enterprise_plan")}</Text>
              </Link>{" "}
              {I18n.t("notification.upgrade_tail")}
            </Text>
          </Banner>
        )}

        <Layout>
          <Layout.Section>
            <Card>
              <BlockStack gap="400">
                <Text variant="headingMd" as="h2">{I18n.t("notification.add_sender_id")}</Text>

                <FormLayout>
                  <FormLayout.Group>
                    <BlockStack gap="200">
                      <Text variant="bodyMd" fontWeight="bold">{I18n.t("notification.destination_country")}</Text>
                      <Text variant="bodySm" tone="subdued">{I18n.t("notification.destination_country_help")}</Text>
                    </BlockStack>

                    <BlockStack gap="200">
                      {selectedCountries && (
                        <InlineStack gap="100">
                          {selectedCountries.split(",").map((c) => (
                            <Tag key={c}>{c}</Tag>
                          ))}
                        </InlineStack>
                      )}
                      <Popover active={popoverActive} activator={activator} onClose={togglePopoverActive}>
                        <Scrollable shadow style={{ height: "300px" }} focusable>
                          <OptionList
                            title={I18n.t("pre_order.select_countries")}
                            onChange={handleSettingChange("countryCodes")}
                            options={countries}
                            selected={selectedCountries ? selectedCountries.split(",") : []}
                            allowMultiple
                          />
                        </Scrollable>
                      </Popover>
                    </BlockStack>
                  </FormLayout.Group>

                  <TextField
                    label={I18n.t("notification.sender_id")}
                    value={setting.headerId || ""}
                    onChange={handleSettingChange("headerId")}
                    placeholder={I18n.t("brand_notification_tab.alphanumeric_3_14")}
                    requiredIndicator
                    autoComplete="off"
                  />

                  <TextField
                    label={I18n.t("notification.dlt_entity")}
                    value={setting.dltPrincipalEntityId || ""}
                    onChange={handleSettingChange("dltPrincipalEntityId")}
                    placeholder={I18n.t("notification.dlt_placeholder")}
                    helpText={I18n.t("notification.dlt_help")}
                    autoComplete="off"
                  />
                </FormLayout>

                {plan.name !== "Premium" && plan.name !== "Enterprise" && plan.name !== "india_budget" ? (
                  <BlockStack gap="400">
                    <Text variant="bodySm" tone="subdued">
                      {I18n.t("notification.upgrade_text")}{" "}
                      <Link onClick={() => navigateTo("/subscription")}>
                        <Text as="span" fontWeight="bold">{I18n.t("notification.enterprise_plan")}</Text>
                      </Link>{" "}
                      {I18n.t("notification.upgrade_tail")}
                    </Text>
                    <InlineStack align="end">
                      <Button variant="primary" disabled>{I18n.t("notification.send_review")}</Button>
                    </InlineStack>
                  </BlockStack>
                ) : (
                  <InlineStack align="end">
                    <Button variant="primary" onClick={handleSubmit} loading={loading}>
                      {I18n.t("notification.send_review")}
                    </Button>
                  </InlineStack>
                )}
              </BlockStack>
            </Card>
          </Layout.Section>
        </Layout>
      </BlockStack>
    </Form>
  );
};

export default BrandNotificationTab;
import React, {
  useState,
  useContext,
  useCallback,
  useEffect,
  useRef,
} from "react";
// 1. Updated Import for App Bridge v4
import { SaveBar, useAppBridge } from "@shopify/app-bridge-react";
import {
  Page,
  Layout,
  Card,
  Form,
  BlockStack,
  InlineStack,
  Box,
  Banner,
  Select,
  TextField,
  Button,
  Text,
  Icon,
  Divider,
  Badge,
  EmptyState,
} from "@shopify/polaris";

import { DeleteMinor, EditMinor, PlusMinor } from "@shopify/polaris-icons";
import { StoreContext } from "../../Context/Store";
import Api from "../../Services/Api";
import I18n from "../../i18n-lang";
import useApi from "../../Hooks/useApi";
import { debugLog } from "../../Modal/utilities/otpUtils";

const defaultSelect = { get label() {
      return I18n.t("branded_whatsapp_tab.select_an_option");
    }, value: "" };

const BrandedWhatsappTab = ({ templateId: initialTemplateId }) => {
  const shopify = useAppBridge(); // Initialize App Bridge v4
  const [template, setTemplate] = useState({ templateId: initialTemplateId });

  const {
    loading: [loading, setLoading],
    shop: [shop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
  } = useContext(StoreContext);

  const [isDirty, setIsDirty] = useState(false);
  const [formSubmitBanner, setFormSubmitBanner] = useState(false);
  const settingRef = useRef(setting);

  const [messageTypeOptions, setMessageTypeOptions] = useState([
    { label: I18n.t("notification.otp"), value: "OTP" },
    { label: I18n.t("notification.order_confirmation"), value: "Order_Confirmation" },
    { label: I18n.t("notification.order_fulfilment"), value: "Order_Fulfilment" },
    { label: I18n.t("notification.abandoned_checkout"), value: "Abandoned_Checkout" },
    { label: I18n.t("notification.cod_prepaid"), value: "COD_Prepaid" },
    { label: I18n.t("notification.first_time_purchase"), value: "First_Time_Purchase" },
  ]);

  const [templateDataExistingList, setTemplateDataExistingList] = useState();

  const languageOptions = [
    { label: I18n.t("branded_whatsapp_tab.english"), value: "en" },
    { label: I18n.t("branded_whatsapp_tab.english_uk"), value: "en_GB" },
    { label: I18n.t("branded_whatsapp_tab.english_us"), value: "en_US" },
    { label: I18n.t("branded_whatsapp_tab.hindi"), value: "hi" },
    { label: I18n.t("branded_whatsapp_tab.spanish"), value: "es" },
    { label: I18n.t("branded_whatsapp_tab.french"), value: "fr" },
    { label: I18n.t("branded_whatsapp_tab.german"), value: "de" },
    // ... rest of your language options remain the same
  ];

  const [language, setLanguage] = useState(template?.templateId?.language || "en");

  const handleLanguageChange = (selectedOption) => {
    setLanguage(selectedOption);
    setIsDirty(true);
  };

  let prepopulatedVariable = template?.templateId?.variables;

  const [selectList, setSelectList] = useState(() => {
    if (prepopulatedVariable) {
      const prepopulatedVariables = prepopulatedVariable.split(":");
      return prepopulatedVariables.map((val) => ({
        value: val,
        prepopulatedVariable: val,
      }));
    }
    return [{ value: "", prepopulatedVariable: "" }];
  });

  const [showMaxAlert, setShowMaxAlert] = useState(false);
  const [templateName, setTemplateName] = useState(template?.templateId?.name || "");
  const [messageType, setMessageType] = useState(template?.templateId?.type || "OTP");

  const [{}, getTemplateList] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/branded_whatsapp_templates/?message_type=${messageType}&shop_id=${shop.id}`,
      method: "GET",
    },
    { manual: true }
  );

  const loadTemplates = () => {
    getTemplateList()
      .then((resp) => {
        setTemplateDataExistingList(resp?.data?.data);
      })
      .catch();
  };

  useEffect(() => {
    loadTemplates();
  }, [messageType]);

  useEffect(() => {
    settingRef.current = setting;
  }, [setting]);

  const [readOnly, setReadOnly] = useState(true);
  const [operator, setOperator] = useState("MSG_91");
  const [authToken, setAuthToken] = useState("");

  const toggleReadOnly = () => setReadOnly(!readOnly);

  const [{}, save_branded_whatsapp_template] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/save_branded_whatsapp_template`,
      method: "POST",
    },
    { manual: true }
  );

  /**
   * REFACTORED: Internal App Save logic
   */
  const handleSaveSettings = useCallback(() => {
    setReadOnly(true);
    setLoading(true);

    const newSetting = {
      ...setting,
      whatsappOperatorConfig: `${operator}:${authToken}`,
    };

    Api.post("/settings", newSetting)
      .then((response) => {
        setIsDirty(false);
        setSetting(response.data);
        setOriginalSetting(response.data);
        shopify.toast.show(I18n.t("admin.settings_saved"));
      })
      .catch((error) => debugLog(error))
      .finally(() => setLoading(false));
  }, [setting, operator, authToken, shopify]);

  const handleDiscard = useCallback(() => {
    const cloned = JSON.parse(JSON.stringify(originalSetting));
    setSetting(cloned);
    setIsDirty(false);
  }, [originalSetting]);

  const handleFormSubmit = async (event) => {
    if (event) event.preventDefault();
    
    const nextErrors = selectList.map((select) =>
      select.value === "" ? I18n.t("notification.error_variable_msg") : ""
    );
    const hasEmptySelect = nextErrors.some(Boolean);
    if (hasEmptySelect) {
      setVariableErrors(nextErrors);
      return;
    }
    setVariableErrors([]);

    const variableValues = selectList.map((select) => select.value);
    const data = { operator, templateName, language, variableValues, authToken, messageType, shop };

    setLoading(true);
    try {
      await save_branded_whatsapp_template({ data });
      setIsDirty(false);
      shopify.toast.show("Template saved successfully");
    } catch (error) {
      debugLog(error);
    } finally {
      setLoading(false);
    }
  };

  const whatsappAllowedVariables = [
    { type: "OTP", allowed_variables: ["otp", "store"] },
    { type: "Order_Confirmation", allowed_variables: ["order_number", "customer_name", "order_amount", "store"] },
    { type: "Order_Fulfilment", allowed_variables: ["customer_name", "order_number", "order_amount", "store"] },
    { type: "Abandoned_Checkout", allowed_variables: ["product_info", "abandoned_cart_discount_code", "abandoned_cart_discount_value", "store"] },
    { type: "COD_Prepaid", allowed_variables: ["customer_name", "order_number", "prepaid_discount", "prepaid_amount_after_discount", "store"] },
    { type: "First_Time_Purchase", allowed_variables: ["customer_name", "first_purchase_discount_value", "first_purchase_discount_code", "store"] },
  ];

  const [variableErrors, setVariableErrors] = useState([]);

  const generateOptions = (index) => {
    const allowedVariables = whatsappAllowedVariables.find((v) => v.type === messageType)?.allowed_variables || [];
    return allowedVariables.map((variable) => ({
      label: variable,
      value: variable,
    }));
  };

  const handleAddSelect = () => {
    if (selectList.length < 5) {
      setSelectList([...selectList, { value: "" }]);
      setVariableErrors((prev) => [...prev, ""]);
      setIsDirty(true);
    } else {
      setShowMaxAlert(true);
    }
  };

  const handleSelectChange = (value, index) => {
    setIsDirty(true);
    const updatedSelectList = [...selectList];
    updatedSelectList[index].value = value;
    setSelectList(updatedSelectList);
    setVariableErrors((prev) => {
      const next = [...prev];
      next[index] = "";
      return next;
    });
  };

  const handleRemoveSelect = (indexToRemove) => {
    const updatedSelectList = [...selectList];
    updatedSelectList.splice(indexToRemove, 1);
    setSelectList(updatedSelectList);
    setVariableErrors((prev) => {
      const next = [...prev];
      next.splice(indexToRemove, 1);
      return next;
    });
    setIsDirty(true);
  };

  useEffect(() => {
    if (setting?.whatsappOperatorConfig) {
      const splitConfig = setting.whatsappOperatorConfig.split(":");
      if (splitConfig[0]) setOperator(splitConfig[0]);
      if (splitConfig[1]) setAuthToken(splitConfig[1]);
    }
  }, [setting]);

  return (
    <Page>
      {/* 2. Declarative SaveBar for App Bridge v4 */}
      <SaveBar data-save-bar open={isDirty}>
        <button
          variant="primary"
          onClick={handleSaveSettings}
          loading={loading ? "" : undefined}
          disabled={loading}
        >
          {I18n.t("admin.save")}
        </button>
        <button onClick={handleDiscard}>
          {I18n.t("admin.discard")}
        </button>
      </SaveBar>

      <Layout>
        {showMaxAlert && (
          <Layout.Section>
            <BlockStack gap="400">
              {showMaxAlert && (
                <Banner title={I18n.t("notification.max_variables_title")} tone="warning" onDismiss={() => setShowMaxAlert(false)}>
                  <p>{I18n.t("notification.max_variables_msg")}</p>
                </Banner>
              )}
            </BlockStack>
          </Layout.Section>
        )}

        <Layout.Section>
          <BlockStack gap="500">
            <Card>
              <BlockStack gap="500">
                <InlineStack align="space-between">
                  <Text variant="headingMd" as="h2">{I18n.t("notification.operator_settings")}</Text>
                  <Badge tone={readOnly ? "info" : "attention"}>{readOnly ? "View mode" : "Edit mode"}</Badge>
                </InlineStack>
                <Divider />
                <BlockStack gap="400">
                  <InlineStack gap="400" wrap={false}>
                    <Box minWidth="200px">
                      <Select label={I18n.t("notification.operator")} options={[{ label: I18n.t("branded_whatsapp_tab.msg_91"), value: "MSG_91" }]} onChange={setOperator} value={operator} disabled={readOnly} />
                    </Box>
                    <Box minWidth="300px">
                      <TextField label={I18n.t("notification.auth_token")} value={authToken} onChange={(val) => { setAuthToken(val); setIsDirty(true); }} readOnly={readOnly} type="password" />
                    </Box>
                  </InlineStack>
                  <TextField label={I18n.t("notification.branded_whatsapp")} value={setting.brandedWhatsappNumber || ""} onChange={(val) => { setSetting({...setting, brandedWhatsappNumber: val}); setIsDirty(true); }} readOnly={readOnly} />
                  {!readOnly && (
                    <Button variant="primary" onClick={handleSaveSettings} loading={loading}>{I18n.t("admin.save")}</Button>
                  )}
                  {readOnly && (
                    <Button onClick={toggleReadOnly} icon={EditMinor}>{I18n.t("notification.edit")}</Button>
                  )}
                </BlockStack>
              </BlockStack>
            </Card>

            <Card>
              <Form onSubmit={handleFormSubmit}>
                <BlockStack gap="500">
                  <Text variant="headingMd" as="h2">{I18n.t("notification.template_details")}</Text>
                  <Divider />
                  <InlineStack gap="400" wrap={false}>
                    <Select label={I18n.t("notification.message_type")} options={messageTypeOptions} onChange={(val) => { setMessageType(val); setIsDirty(true); }} value={messageType} disabled={!!template.templateId} />
                    <Select label={I18n.t("notification.language_meta")} options={languageOptions} onChange={handleLanguageChange} value={language} />
                  </InlineStack>
                  <TextField label={I18n.t("branded_whatsapp_tab.template_name")} value={templateName} onChange={(val) => { setTemplateName(val); setIsDirty(true); }} />
                  
                  <Divider />
                  
                  <BlockStack gap="400">
                    <Text variant="headingSm">
                {I18n.t("branded_whatsapp_tab.variables_count", {
                  count: selectList.length,
                })}
              </Text>
                    {selectList.map((select, index) => (
                      <Card key={index} background="bg-surface-secondary">
                        <InlineStack gap="400" align="space-between">
                          <Select
                            label={`Variable ${index + 1}`}
                            options={[{ label: I18n.t("branded_whatsapp_tab.select"), value: "" }, ...generateOptions()]}
                            onChange={(val) => handleSelectChange(val, index)}
                            value={select.value}
                            error={variableErrors[index] || undefined}
                          />
                          <Button variant="tertiary" tone="critical" onClick={() => handleRemoveSelect(index)} icon={DeleteMinor} />
                        </InlineStack>
                      </Card>
                    ))}
                    {selectList.length < 5 && (
                      <Button onClick={handleAddSelect} icon={PlusMinor}>{I18n.t("notification.add_variable")}</Button>
                    )}
                  </BlockStack>

                  <Button variant="primary" submit loading={loading}>{template.templateId ? "Update Template" : I18n.t("admin.submit")}</Button>
                </BlockStack>
              </Form>
            </Card>
          </BlockStack>
        </Layout.Section>
      </Layout>
    </Page>
  );
};

export default BrandedWhatsappTab;
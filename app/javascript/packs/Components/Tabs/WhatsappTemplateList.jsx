import React, { useState, useEffect, useContext } from "react";
import {
  Button,
  Link,
  Text,
  TopBar,
  Modal,
  FormLayout,
  BlockStack,
  InlineStack,
  Card,
  DataTable,
} from "@shopify/polaris";
import BrandedWhatsappTab from "./BrandedWhatsappTab";
import { StoreContext } from "../../Context/Store";
import useApi from "../../Hooks/useApi";
import { debugLog } from "../../Modal/utilities/otpUtils";

import I18n from "../../i18n-lang";
const WhatsappTemplateList = () => {
  const [templates, setTemplates] = useState([]);
  const {
    loading: [loading, setLoading],
    plan: [plan, setPlan],
    shop: [shop, setShop],
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
    tab: [tab, setTab],
    templateFocus: [templateFocus, setTemplateFocus],
    crispUrl,
    twilioPricing,
    isPrepaidEnabled,
  } = useContext(StoreContext);

  const [{ data: templateData, plloading, plerror }, getTemplateList] = useApi(
    {
      url: `https://${process.env.APP_HOST}/settings/branded_whatsapp_templates/?shop_id=${shop.id}`,
      method: "GET",
    },
    { manual: true }
  );

  const loadTemplates = () => {
    getTemplateList()
      .then((resp) => {
        debugLog("Loaded template Data", templateData);
      })
      .catch();
  };

  useEffect(() => {
    if (templateData == undefined) {
      loadTemplates();
    }
  }, [templateData]);

  useEffect(() => {
    if (templateData?.data && Array.isArray(templateData.data)) {
      const formattedTemplates = templateData.data.map((template) => ({
        id: template.id,
        type: template.templateType,
        name: template.templateName,
        variables: template.variables,
        language: template.language,
      }));
      setTemplates(formattedTemplates);
      debugLog(formattedTemplates);
      if (formattedTemplates.length === 6) {
        debugLog("hide create template");
        setShowCreateButton(false);
      }
    }
  }, [templateData]);

  const [isEditing, setIsEditing] = useState(false);
  const [selectedTemplate, setSelectedTemplate] = useState(null);

  const handleEditClick = (template) => {
    setSelectedTemplate(template);
    setIsEditing(true);
  };

  const [showTemplateTable, setShowTemplateTable] = useState(true);
  const [showBrandedTab, setShowBrandedTab] = useState(false);
  const [showCreateButton, setShowCreateButton] = useState(true);

  const handleCreateClick = () => {
    setShowTemplateTable(false);
    setIsEditing(false);
    setShowBrandedTab(true);
    setShowCreateButton(false);
  };

  const handleTemplateList = () => {
    setIsEditing(false);
    setShowCreateButton(true);
    setShowTemplateTable(true);
    setShowBrandedTab(false);
    loadTemplates();
  };

  const rows = templates.map((template) => [
    template.type,
    <Link key={template.id} onClick={() => handleEditClick(template)}>
      {template.name}
    </Link>,
    <Button key={template.id} onClick={() => handleEditClick(template)}>
      {I18n.t("whatsapp_template_list.edit")}
    </Button>,
  ]);

  return (
    <>
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <FormLayout.Group>
          {(!showTemplateTable || isEditing) && (
            <Button variant="primary" onClick={handleTemplateList}>
              {I18n.t("whatsapp_template_list.template_list")}
            </Button>
          )}
          {showCreateButton && (
            <Button
              variant="primary"
              style={{ marginLeft: "10px" }}
              onClick={handleCreateClick}
            >
              {I18n.t("whatsapp_template_list.create_template")}
            </Button>
          )}
        </FormLayout.Group>
      </div>
      {isEditing && <BrandedWhatsappTab templateId={selectedTemplate} />}
      {!isEditing && showTemplateTable && (
        <>
          <Text variant="headingMd" as="h2">
            {I18n.t("whatsapp_template_list.branded_whatsapp_templates")}
          </Text>
          <Card>
            <DataTable
              columnContentTypes={["text", "text", "text"]}
              headings={["Type", "Name", "Actions"]}
              rows={rows}
            />
          </Card>
        </>
      )}
      {showBrandedTab && <BrandedWhatsappTab />}
    </>
  );
};

export default WhatsappTemplateList;

import React, { useEffect, useState } from "react";
import { Card, Tabs, Box } from "@shopify/polaris";
import WhatsappLayout from "./WhatsappLayout";
import WhatsappTemplatesList from "./WhatsappTemplatesList";
import WhatsappTemplateLibrary from "./WhatsappTemplateLibrary";
import WhatsappEventMappings from "./WhatsappEventMappings";
import WhatsappTemplateCreateTab from "../../Components/Tabs/WhatsappTemplateCreateTab";

import I18n from "../../i18n-lang";
const TAB_KEYS = ["list", "create", "library", "mappings"];

const WhatsappTemplatesPage = () => {
  // Deep-link support: /features/whatsapp/templates?tab=mappings
  const [selected, setSelected] = useState(() => {
    const idx = TAB_KEYS.indexOf(new URLSearchParams(window.location.search).get("tab"));
    return idx >= 0 ? idx : 0;
  });

  // Allow other components to request a tab switch (e.g. "go to Create" link from mappings page).
  useEffect(() => {
    const handler = (e) => {
      const idx = TAB_KEYS.indexOf(e.detail);
      if (idx >= 0) setSelected(idx);
    };
    window.addEventListener("whatsapp:goto-tab", handler);
    return () => window.removeEventListener("whatsapp:goto-tab", handler);
  }, []);

  const tabs = [
    { id: "list", content: I18n.t("whatsapp_templates_page.my_templates"), panelID: "template-list-panel" },
    { id: "create", content: I18n.t("whatsapp_templates_page.create_new_template"), panelID: "template-create-panel" },
    { id: "library", content: I18n.t("whatsapp_templates_page.pre_made_templates"), panelID: "template-library-panel" },
    { id: "mappings", content: I18n.t("whatsapp_templates_page.notifications"), panelID: "template-mappings-panel" },
  ];

  const panels = [
    <WhatsappTemplatesList key="list" />,
    <WhatsappTemplateCreateTab key="create" />,
    <WhatsappTemplateLibrary key="library" />,
    <WhatsappEventMappings key="mappings" />,
  ];

  return (
    /* Reached from Business Brand WhatsApp, so it carries the way back. Without it a
       merchant had to click Business Brand WhatsApp in the sidebar again to return. */
    <WhatsappLayout
      title={I18n.t("whatsapp_templates_page.templates")}
      subtitle={I18n.t("whatsapp_templates_page.the_messages_you_send_the_ones")}
      backTo="/features/whatsapp"
      backLabel="Business Brand WhatsApp"
    >
      <Card padding="200">
        <Tabs tabs={tabs} selected={selected} onSelect={setSelected} fitted />
      </Card>
      <br />
      <Box>{panels[selected]}</Box>
    </WhatsappLayout>
  );
};

export default WhatsappTemplatesPage;

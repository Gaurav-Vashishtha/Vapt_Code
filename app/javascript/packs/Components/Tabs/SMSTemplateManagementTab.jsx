import { Page, Card, DataTable, Badge, Button } from "@shopify/polaris";
import React, { useState, useEffect } from "react";
import CommonModal from "../CommonModal";

import { Copy, RefreshCw, Edit, Trash2 } from "lucide-react";

import CreateTemplateForm from "./Modals/createTemplateModal";
import { debugLog } from "../../Modal/utilities/otpUtils";
import I18n from "../../i18n-lang";
function SMSTemplateManagementTab() {
  const rows = [
    [
      <>
        {I18n.t("sms_template_management_tab.template_name")} <br /> <Badge status="success">{I18n.t("sms_template_management_tab.active")}</Badge>
      </>,
      "content content content content",
      <>
        {I18n.t("sms_template_management_tab.jdsfgjshkghdskfgh9w84yrt9834u0824u")}
        <Button
          plain
          icon={Copy}
          onClick={() =>
            navigator.clipboard.writeText("jdsfgjshkghdskfgh9w84yrt9834u0824u")
          }
        ></Button>
      </>,
      <>
        <Edit /> &nbsp; <Trash2 />
      </>,
    ],
    [
      <>
        {I18n.t("sms_template_management_tab.template_name")} <br /> <Badge status="attention">{I18n.t("sms_template_management_tab.pending")}</Badge>
      </>,
      "content content content content",
      <>
        {I18n.t("sms_template_management_tab.abcdwertyuiosdfghjdxcvbnfghj")}
        <Button
          // loading
          plain
          icon={Copy}
          onClick={() =>
            navigator.clipboard.writeText("abcdwertyuiosdfghjdxcvbnfghj")
          }
        ></Button>
      </>,
      <>
        <Edit /> &nbsp; <Trash2 />
      </>,
    ],
  ];
  const [modalActive, setModalActive] = useState(false);
  const [modalType, setModalType] = useState(null);
  const [modalContent, setModalContent] = useState({
    title: "",
    primaryActionContent: "",
    primaryAction: () => {},
    secondaryActionContent: "Cancel",
    children: null,
  });

  useEffect(() => {
    const openModal = () => {
      switch (modalType) {
        case "sms_schedule":
          handleOpenSMSModal();
          break;
        // Add more cases for other modal types as needed
        default:
          // Handle default case or do nothing
          break;
      }
    };

    if (modalActive) {
      openModal();
    }
  }, [modalActive, modalType]);

  const handleOpenSMSModal = () => {
    const content = (
      // <Card sectioned title="Select Time Preference for SMS"></Card>
      <CreateTemplateForm />
    );
    setModalContent({
      title: I18n.t("sms_template_management_tab.create_template"),
      primaryActionContent: "Close",
      primaryAction: () => setModalActive(false),
      children: content,
    });
    setModalType("sms_schedule");
    setModalActive(true);
  };
  return (
    <Page
      title={I18n.t("sms_template_management_tab.sms_template_management")}
      primaryAction={{
        content: I18n.t("sms_template_management_tab.create_template_2"),
        onAction: () => handleOpenSMSModal(),
      }}
      secondaryActions={[
        {
          content: <RefreshCw />,
          onAction: () => debugLog("Refresh clicked"),
        },
      ]}
    >
      <Card>
        <DataTable
          columnContentTypes={["text", "text", "text", "text"]}
          headings={[
            <strong>{I18n.t("sms_template_management_tab.template")}</strong>,
            <strong>{I18n.t("sms_template_management_tab.content")}</strong>,
            <strong>{I18n.t("sms_template_management_tab.template_id")}</strong>,
            <strong>{I18n.t("sms_template_management_tab.action")}</strong>,
          ]}
          rows={rows}
        />
      </Card>
      <CommonModal
        open={modalActive}
        onClose={() => setModalActive(false)}
        title={modalContent.title}
        primaryActionContent={modalContent.primaryActionContent}
        primaryAction={modalContent.primaryAction}
      >
        {modalContent.children}
      </CommonModal>
    </Page>
  );
}

export default SMSTemplateManagementTab;

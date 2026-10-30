import React, { useState, useContext, useCallback } from "react";
import { Button, Banner } from "@shopify/polaris";
import { StoreContext } from "../Context/Store";
import useApi from "../Hooks/useApi";
import I18n from "../i18n-lang";

const EnableWhatsAppComp = () => {
  const {
    setting: [setting, setSetting],
    originalSetting: [originalSetting, setOriginalSetting],
  } = useContext(StoreContext);
  const [inlineError, setInlineError] = useState("");

  const APPROVAL_SENT_TEXT = I18n.t("admin.whatsapp_approval_request_sent");
  const APPROVAL_SENT_FAILURE_TEXT = I18n.t(
    "admin.whatsapp_approval_request_sent_failure"
  );

  const [whatsappApprovalNote] = useState(
    "Click the below button for WhatsApp Approval"
  );

  const [whatsappRequestToastMarkup, setWhatsappRequestToastMarkup] =
    useState(false);
  const [toastContent, setToastContent] = useState("");
  const toggleSendWhatsappReqActive = useCallback(
    () => setWhatsappRequestToastMarkup((active) => !active),
    []
  );
  // const sendWhatsappRequestToastMarkup = whatsappRequestToastMarkup ? (
  //   <Toast content={toastContent} onDismiss={toggleSendWhatsappReqActive} />
  // ) : null;

  const [{ data, loading: sendingWhatsappRequest }, sendWhatsappRequest] =
    useApi(
      {
        url: "/settings/send_whatsapp_approval_request",
        method: "post",
      },
      { manual: true }
    );

  const requestWhatsAppApproval = () => {
    sendWhatsappRequest()
      .then((resp) => {
        if (resp.status === 200) {
          setWhatsappRequestToastMarkup(true);
          // setToastContent(APPROVAL_SENT_TEXT);
          setSetting(resp.data.setting);
          setOriginalSetting(resp.data.setting);
          setInlineError("");
        } else {
          setWhatsappRequestToastMarkup(true);
          // setToastContent(APPROVAL_SENT_FAILURE_TEXT);
          setInlineError(APPROVAL_SENT_FAILURE_TEXT);
        }
      })
      .catch((error) => {
        setWhatsappRequestToastMarkup(true);
        // setToastContent(APPROVAL_SENT_FAILURE_TEXT);
        setInlineError(APPROVAL_SENT_FAILURE_TEXT);
      });
  };

  const getApprovalText = () => {
    if (setting.whatsappApprovalStatus === "approved") {
      if (
        setting.whatsappApprovalNotes === "Whatsapp approval request sent" ||
        !setting.whatsappApprovalNotes
      ) {
        return "Request approved";
      }
      return setting.whatsappApprovalNotes;
    }
    if (setting.whatsappApprovalStatus === "rejected") {
      if (setting.whatsappApprovalNotes === "Whatsapp approval request sent") {
        return "Request rejected";
      }
      return setting.whatsappApprovalNotes || "Request rejected";
    }
    if (setting.whatsappApprovalStatus === "requested") {
      if (setting.whatsappApprovalNotes !== "Whatsapp approval request sent") {
        return "Whatsapp approval request sent";
      }
      return setting.whatsappApprovalNotes || "Approval requested";
    }
    return whatsappApprovalNote;
  };

  return (
    <>
      {/* {sendWhatsappRequestToastMarkup} */}
      <div style={{ textAlign: "center", lineHeight: "35px" }}>
        {setting.whatsappApprovalStatus != "approved" && (
          <>
            <div style={{ marginBottom: 12 }}>{getApprovalText()}</div>
            <Button
              variant="primary"
              disabled={
                setting.whatsappApprovalStatus === "approved" ||
                setting.whatsappApprovalStatus === "requested" ||
                setting.whatsappApprovalStatus == "rejected"
              }
              onClick={requestWhatsAppApproval}
              loading={sendingWhatsappRequest}
            >
              {I18n.t("enable_whats_app_comp.send_whatsapp_approval_request")}
            </Button>

            {inlineError && (
              <div style={{ marginTop: 12 }}>
                <Banner status="critical" onDismiss={() => setInlineError("")}>
                  {inlineError}
                </Banner>
              </div>
            )}
          </>
        )}

        <div style={{ marginTop: 10 }}>
          {setting.whatsappApprovalStatus == "send_request" && (
            <div>
              <span>{I18n.t("enable_whats_app_comp.the_approval_takes_around_24_48")}</span>
              <br />
              <span className="">
                {I18n.t("enable_whats_app_comp.once_approved_you_will_be_able")}
              </span>
              <br />
            </div>
          )}

          {setting.whatsappApprovalStatus == "requested" && (
            <div>
              <span>{I18n.t("enable_whats_app_comp.approval_request_sent")}</span>
              <br />
              <span className="">
                {I18n.t("enable_whats_app_comp.once_approved_you_will_be_able")}
              </span>
              <br />
            </div>
          )}

          {setting.whatsappApprovalStatus == "rejected" && (
            <div>
              <span>
                {I18n.t("enable_whats_app_comp.your_request_could_not_be_approved")}
              </span>
              <br />
              <span className="">
                {I18n.t("enable_whats_app_comp.once_you_make_updates_to_your")}
              </span>
              <br />
            </div>
          )}
          {setting.whatsappApprovalStatus == "approved" && (
            <div>
              <span>
                {I18n.t("enable_whats_app_comp.congratulations_your_whatsapp_account_with_cod")}
              </span>
              <br />
            </div>
          )}
          {setting.whatsappApprovalStatus != "approved" && (
            <span style={{ textAlign: "center", marginTop: "2rem" }}>
              <Button
                external
                onClick={() => window.$crisp.push(["do", "chat:open"])}
              >
                {I18n.t("enable_whats_app_comp.have_queries_chat_with_us")}
              </Button>
            </span>
          )}
        </div>
      </div>
    </>
  );
};

export default EnableWhatsAppComp;

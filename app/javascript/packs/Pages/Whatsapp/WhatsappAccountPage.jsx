import React from "react";
import WhatsappLayout from "./WhatsappLayout";
import WhatsappAccountsTab from "../../Components/Tabs/WhatsappAccountsTab";

import I18n from "../../i18n-lang";
const WhatsappAccountPage = () => (
  <WhatsappLayout
    title={I18n.t("whatsapp_account_page.account")}
    subtitle={I18n.t("whatsapp_account_page.the_whatsapp_number_you_send_from")}
  >
    <WhatsappAccountsTab />
  </WhatsappLayout>
);

export default WhatsappAccountPage;
